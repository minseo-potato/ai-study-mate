"""스터디 생성·조회·계획 수정 API."""
import json
import math
import re
from datetime import date, timedelta
from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from pydantic import BaseModel, Field
import ai
import guard
from auth import current_user
from db import connect
from common import AVATAR_PATTERN, INITIAL_UNDERSTANDING, LEVELS, MEMBER_LEVELS, PEER_NAMES, PERSPECTIVES, add_file_message, clean_speech, read_file, required, study_data


router = APIRouter(dependencies=[Depends(current_user)])


@router.get("/studies")
def list_studies(user: dict = Depends(current_user)):
    """채팅 목록용: 스터디마다 지금 주차와 마지막 메시지를 함께 돌려준다(스터디 수와 상관없이 쿼리 3번)."""
    uid = user["id"]
    with connect() as db:
        items = [dict(r) for r in db.execute(
            "SELECT * FROM studies WHERE user_id=? ORDER BY archived ASC,pinned DESC,id DESC", (uid,))]
        current = {}
        for w in db.execute("SELECT w.study_id,w.week_no,w.title,w.meeting_date,w.status FROM weeks w "
                            "JOIN studies st ON st.id=w.study_id WHERE st.user_id=? ORDER BY w.study_id,w.week_no",
                            (uid,)):
            seen = current.get(w["study_id"])
            if seen is None or seen["status"] == "complete":
                current[w["study_id"]] = dict(w)
        last = {r["study_id"]: r for r in db.execute(
            "SELECT s.study_id,m.role,m.body,mb.name FROM messages m JOIN sessions s ON s.id=m.session_id "
            "LEFT JOIN members mb ON mb.study_id=s.study_id AND mb.member_no=m.member_no "
            "WHERE m.id IN (SELECT MAX(m2.id) FROM messages m2 JOIN sessions s2 ON s2.id=m2.session_id "
            "JOIN studies st ON st.id=s2.study_id WHERE st.user_id=? GROUP BY s2.study_id)", (uid,))}
        for item in items:
            week = current.get(item["id"])
            item["current_week"] = None if week is None else {
                k: week[k] for k in ("week_no", "title", "meeting_date")}
            msg = last.get(item["id"])
            item["last_message"] = None if msg is None else {
                "body": f"파일: {msg['body']}" if msg["role"] == "user_file" else msg["body"] if msg["role"] == "user" else clean_speech(msg["body"], [dict(msg)]),
                "mine": msg["role"].startswith("user"), "name": msg["name"] or ""}
        return items


@router.put("/studies/{study_id}/pin")
def pin_study(study_id: int, user: dict = Depends(current_user)):
    with connect() as db:
        required(db, "SELECT id FROM studies WHERE id=? AND archived=0", (study_id,))
        db.execute("UPDATE studies SET pinned=0 WHERE user_id=?", (user["id"],))
        db.execute("UPDATE studies SET pinned=1 WHERE id=?", (study_id,))
        return study_data(db, study_id)


class StudyDetails(BaseModel):
    title: str | None = Field(default=None, max_length=120)
    archived: bool | None = None
    avatar: str | None = Field(default=None, pattern=AVATAR_PATTERN)


@router.put("/studies/{study_id}/details")
def edit_study_details(study_id: int, body: StudyDetails):
    with connect() as db:
        study = required(db, "SELECT * FROM studies WHERE id=?", (study_id,))
        title = study["title"] if body.title is None else guard.clean_label(body.title, 120)
        if not title:
            raise HTTPException(400, "채팅방 이름을 입력해 주세요.")
        archived = study["archived"] if body.archived is None else int(body.archived)
        avatar = study["avatar"] if body.avatar is None else body.avatar
        db.execute("UPDATE studies SET title=?,archived=?,pinned=?,avatar=? WHERE id=?",
                   (title, archived, 0 if archived else study["pinned"], avatar, study_id))
        return study_data(db, study_id)


@router.put("/studies/{study_id}/pdf")
async def replace_pdf(study_id: int, pdf: UploadFile = File(...)):
    pages, size = await read_file(pdf)
    with connect() as db:
        study = required(db, "SELECT * FROM studies WHERE id=?", (study_id,))
        db.execute("INSERT INTO page_history(study_id,pdf_version,page_no,body,pdf_name) "
                   "SELECT study_id,?,page_no,body,? FROM pages WHERE study_id=?",
                   (study["pdf_version"], study["pdf_name"], study_id))
        db.execute("DELETE FROM pages WHERE study_id=?", (study_id,))
        db.executemany("INSERT INTO pages VALUES(?,?,?)", [(study_id, n, text) for n, text in pages])
        db.execute("UPDATE studies SET pdf_name=?,pdf_size=?,pdf_version=pdf_version+1 WHERE id=?",
                   (guard.clean_filename(pdf.filename), size, study_id))
        active = db.execute("SELECT id FROM sessions WHERE study_id=? AND status='active' ORDER BY id DESC LIMIT 1", (study_id,)).fetchone()
        if active:
            add_file_message(db, study_id, active["id"], guard.clean_filename(pdf.filename), size, pages)
        for week in db.execute("SELECT week_no,scope FROM weeks WHERE study_id=? AND status!='complete'", (study_id,)):
            if study["pdf_name"] and not re.fullmatch(r"\d+\s*[~\-]\s*\d+\s*쪽", week["scope"]):
                continue
            first = min(len(pages), math.ceil((week["week_no"] - 1) * len(pages) / study["weeks"]) + 1)
            last = max(first, math.ceil(week["week_no"] * len(pages) / study["weeks"]))
            db.execute("UPDATE weeks SET scope=? WHERE study_id=? AND week_no=?",
                       (f"{first}~{last}쪽", study_id, week["week_no"]))
        return study_data(db, study_id)


async def first_plan(title: str, goal: str, weeks: int, pages: list) -> dict:
    """주제에 맞는 주차별 제목과 범위를 정한다. AI를 쓸 수 없으면 주차 번호만 쓴다."""
    if ai.demo_mode():
        return {}
    try:
        result = await ai.generate_json(
            "한국어 주간 학습 계획을 제안하세요. JSON 키는 weeks이며 항목은 week_no,title,scope입니다. 주차 수를 정확히 맞추세요. "
            "title은 그 주에 실제로 다룰 내용 이름(15자 안팎), scope는 공부할 것을 구체적으로 한 문장으로 쓰세요. "
            "마지막 주는 그동안 공부한 것을 발표하고 피드백받는 주입니다. 교안이 있으면 쪽 순서를 나눈 흐름을 따르세요.",
            {"title": title, "goal": goal, "weeks": [{"week_no": n, "title": "", "scope": ""} for n in range(1, weeks + 1)],
             "pages": [{"page_no": n, "body": text[:500]} for n, text in pages[:30]]})
        return {w["week_no"]: w for w in result.get("weeks", []) if isinstance(w, dict) and isinstance(w.get("week_no"), int)}
    except Exception:
        return {}


@router.post("/studies")
async def create_study(
    title: str = Form(...), goal: str = Form(""), start_date: date | None = Form(None),
    weeks: int = Form(4), hours_per_week: float = Form(3),
    member_count: int | None = Form(None), rules: str = Form(""),
    member_profiles: str = Form(""),
    pdf: UploadFile | None = File(None),
    user: dict = Depends(current_user),
):
    """주제만 있으면 만들 수 있다. 목표·기간·시작일·스터디원은 비워 두면 기본값을 쓴다."""
    title = guard.clean_label(title, 120)
    goal = guard.clean_label(goal, 300) or title
    start_date = start_date or date.today()
    if not title:
        raise HTTPException(400, "학습 주제를 입력해 주세요.")
    if guard.is_trick(title) or guard.is_trick(goal):
        raise HTTPException(400, "공부할 주제를 적어 주세요.")
    try:
        profiles = json.loads(member_profiles) if member_profiles else []
    except ValueError as exc:
        raise HTTPException(400, "AI 스터디원 설정을 읽지 못했습니다.") from exc
    member_count = member_count or len(profiles) or 3
    if not 1 <= weeks <= 26 or not 0.5 <= hours_per_week <= 80 or not 1 <= member_count <= 4:
        raise HTTPException(400, "기간 또는 AI 스터디원 수가 범위를 벗어났습니다.")
    if profiles and (not isinstance(profiles, list) or len(profiles) != member_count or any(
        not isinstance(p, dict) or p.get("level") not in LEVELS or
        not isinstance(p.get("understanding", ""), str) or len(p.get("understanding", "")) > 500 or
        not isinstance(p.get("name", ""), str) or len(p.get("name", "").strip()) > 12 or
        p.get("role", 0) not in range(len(PERSPECTIVES))
        for p in profiles
    )):
        raise HTTPException(400, "AI 스터디원 이름(12자 이하)과 학습 단계를 확인해 주세요.")
    pages, size = await read_file(pdf) if pdf is not None else ([], 0)
    page_count = len(pages)
    plans = await first_plan(title, goal, weeks, pages)
    with connect() as db:
        cur = db.execute(
            "INSERT INTO studies(title,goal,start_date,weeks,hours_per_week,member_count,rules,pdf_name,pdf_size,user_id) "
            "VALUES(?,?,?,?,?,?,?,?,?,?)",
            (title, goal, start_date.isoformat(), weeks, hours_per_week, member_count,
             rules.strip(), guard.clean_filename(pdf.filename) if pdf else "", size, user["id"]),
        )
        study_id = cur.lastrowid
        db.executemany("INSERT INTO pages VALUES(?,?,?)", [(study_id, n, body) for n, body in pages])
        for number in range(1, weeks + 1):
            first = min(page_count, math.ceil((number - 1) * page_count / weeks) + 1) if page_count else 1
            last = max(first, math.ceil(number * page_count / weeks)) if page_count else 0
            plan = plans.get(number, {})
            week_title = str(plan.get("title") or ("발표" if number == weeks > 1 else f"{number}주차"))[:120]
            # 교안이 있으면 쪽 범위를 지켜 근거 쪽을 정확히 고른다.
            scope = (f"{first}~{last}쪽" if pages and first <= last else str(plan.get("scope") or goal))[:300]
            meeting = start_date + timedelta(days=number * 7 - 1)
            db.execute("INSERT INTO weeks(study_id,week_no,title,scope,meeting_date) VALUES(?,?,?,?,?)",
                       (study_id, number, week_title, scope, meeting.isoformat()))
        for number in range(1, member_count + 1):
            profile = profiles[number-1] if profiles else {}
            role = profile.get("role", (number - 1) % 4)
            avatar = str(profile.get("avatar") or "")
            if not re.match(AVATAR_PATTERN, avatar):
                avatar = ""
            db.execute("INSERT INTO members(study_id,member_no,name,perspective,level,understanding,avatar) "
                       "VALUES(?,?,?,?,?,?,?)",
                       (study_id, number, guard.clean_label(profile.get("name", ""), 12) or PEER_NAMES[role], PERSPECTIVES[role],
                        profile.get("level", LEVELS[role]),
                        (profile.get("understanding") or INITIAL_UNDERSTANDING[role]).strip(), avatar))
        return study_data(db, study_id)


class Preferences(BaseModel):
    items: list[str] = Field(max_length=6)


@router.put("/studies/{study_id}/preferences")
def edit_preferences(study_id: int, body: Preferences):
    """채팅으로 정한 진행 방식을 채팅방 정보에서 지우거나 정리한다."""
    items = [x for x in dict.fromkeys(guard.clean_label(x, 60) for x in body.items) if x and not guard.is_trick(x)]
    with connect() as db:
        db.execute("UPDATE studies SET preferences=? WHERE id=?", (json.dumps(items, ensure_ascii=False), study_id))
        return study_data(db, study_id)


class MemberEdit(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=12)
    level: str | None = None
    avatar: str | None = Field(default=None, pattern=AVATAR_PATTERN)


@router.put("/studies/{study_id}/members/{member_no}")
def edit_member(study_id: int, member_no: int, body: MemberEdit):
    """채팅방 정보에서 AI 스터디원의 이름·학습 단계·프로필 모양을 바꾼다."""
    with connect() as db:
        member = required(db, "SELECT * FROM members WHERE study_id=? AND member_no=?", (study_id, member_no))
        name = member["name"] if body.name is None else guard.clean_label(body.name, 12)
        if not name:
            raise HTTPException(400, "이름을 입력해 주세요.")
        level = body.level or member["level"]
        if level not in MEMBER_LEVELS:
            raise HTTPException(400, "학습 단계는 기초, 중급, 심화 중 하나예요.")
        avatar = member["avatar"] if body.avatar is None else body.avatar
        db.execute("UPDATE members SET name=?,level=?,avatar=? WHERE study_id=? AND member_no=?",
                   (name, level, avatar, study_id, member_no))
        return study_data(db, study_id)


@router.get("/studies/{study_id}")
def get_study(study_id: int):
    with connect() as db:
        return study_data(db, study_id)


class WeekEdit(BaseModel):
    title: str = Field(min_length=1, max_length=120)
    scope: str = Field(min_length=1, max_length=300)
    meeting_date: date
    status: str = "planned"
    progress_percent: int | None = Field(default=None, ge=0, le=100)
    remaining_scope: str | None = Field(default=None, max_length=300)
    include_previous_questions: bool | None = None


@router.put("/studies/{study_id}/weeks/{week_no}")
def edit_week(study_id: int, week_no: int, body: WeekEdit):
    if body.status not in ("planned", "in_progress", "complete"):
        raise HTTPException(400, "잘못된 주차 상태입니다.")
    with connect() as db:
        old = required(db, "SELECT * FROM weeks WHERE study_id=? AND week_no=?", (study_id, week_no))
        progress = old["progress_percent"] if body.progress_percent is None else body.progress_percent
        remaining_scope = old["remaining_scope"] if body.remaining_scope is None else body.remaining_scope.strip()
        include_previous = old["include_previous_questions"] if body.include_previous_questions is None else int(body.include_previous_questions)
        status = "in_progress" if body.status == "planned" and progress > 0 else body.status
        db.execute("UPDATE weeks SET title=?,scope=?,meeting_date=?,status=?,progress_percent=?,remaining_scope=?,include_previous_questions=? WHERE study_id=? AND week_no=?",
                   (body.title, body.scope, body.meeting_date.isoformat(), status, progress,
                    remaining_scope, include_previous, study_id, week_no))
        return study_data(db, study_id)


class WeekDraft(BaseModel):
    week_no: int
    title: str = Field(min_length=1, max_length=120)
    scope: str = Field(min_length=1, max_length=300)


class WeekBatch(BaseModel):
    weeks: list[WeekDraft] = Field(max_length=26)


@router.put("/studies/{study_id}/weeks")
def edit_weeks(study_id: int, body: WeekBatch):
    """AI 계획안처럼 여러 주차의 제목·범위를 한 번에 바꾼다(날짜·상태는 그대로)."""
    with connect() as db:
        db.executemany("UPDATE weeks SET title=?,scope=? WHERE study_id=? AND week_no=?",
                       [(w.title.strip(), w.scope.strip(), study_id, w.week_no) for w in body.weeks])
        return study_data(db, study_id)


@router.delete("/studies/{study_id}")
def delete_study(study_id: int):
    """스터디와 대화·기록을 모두 지운다."""
    with connect() as db:
        db.execute("DELETE FROM messages WHERE session_id IN (SELECT id FROM sessions WHERE study_id=?)", (study_id,))
        for table in ("attachments", "sessions", "weeks", "members", "pages", "page_history", "review_items"):
            db.execute(f"DELETE FROM {table} WHERE study_id=?", (study_id,))
        db.execute("DELETE FROM studies WHERE id=?", (study_id,))
        return {"ok": True}


@router.post("/studies/{study_id}/plan-draft")
async def plan_draft(study_id: int):
    with connect() as db:
        study = study_data(db, study_id)
        samples = [dict(r) for r in db.execute(
            "SELECT page_no,substr(body,1,1000) AS body FROM pages WHERE study_id=? ORDER BY page_no LIMIT 20", (study_id,))]
    result = await ai.generate_json(
        "한국어 주간 학습 계획을 제안하세요. weeks 배열에 week_no,title,scope를 넣으세요. "
        "주차 수를 정확히 맞추세요. 교안이 있으면 실제 페이지 범위를 사용하고, "
        "교안이 없으면 학습 목표에 맞는 주제별 범위를 제안하며 페이지 번호를 만들지 마세요.",
        {"goal": study["goal"], "hours_per_week": study["hours_per_week"], "weeks": study["weeks"], "pages": samples},
    )
    drafts = result.get("weeks", [])
    if not isinstance(drafts, list) or len(drafts) != len(study["weeks"]) or any(
        not isinstance(w, dict) or w.get("week_no") != i + 1 or not w.get("title") or not w.get("scope")
        for i, w in enumerate(drafts)
    ):
        raise HTTPException(502, "AI 학습 계획 형식이 올바르지 않습니다.")
    return {"weeks": drafts, "message": "제안입니다. 각 주차를 확인하고 저장해 주세요."}


@router.post("/studies/{study_id}/replan-draft")
async def replan_draft(study_id: int):
    with connect() as db:
        study = study_data(db, study_id)
    remaining = [w for w in study["weeks"] if w["status"] != "complete"]
    if not remaining:
        raise HTTPException(400, "변경할 남은 주차가 없습니다.")
    result = await ai.generate_json(
        "완료하지 못한 범위와 복습 항목을 남은 주차에 재배분한 한국어 계획을 제안하세요. "
        "각 주차의 progress_percent와 remaining_scope를 확인해 미완료 학습량을 반영하세요. "
        "JSON 키는 weeks이며, 각 항목에 week_no,title,scope를 넣으세요. 날짜는 수정하지 마세요.",
        {"goal": study["goal"], "hours_per_week": study["hours_per_week"],
         "completed": [w for w in study["weeks"] if w["status"] == "complete"], "remaining": remaining},
    )
    drafts = result.get("weeks", [])
    expected = {w["week_no"] for w in remaining}
    if not isinstance(drafts, list) or {w.get("week_no") for w in drafts if isinstance(w, dict)} != expected \
            or len(drafts) != len(remaining) or any(not w.get("title") or not w.get("scope") for w in drafts):
        raise HTTPException(502, "AI 변경안 형식이 올바르지 않습니다.")
    return {"weeks": drafts, "message": "변경안입니다. 적용 전에 확인해 주세요."}
