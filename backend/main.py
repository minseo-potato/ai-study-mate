"""AI 스터디메이트 local demo API. Start with: uvicorn main:app --reload"""
import io
import json
import math
import os
import re
from datetime import date, datetime, timedelta, timezone

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from pydantic import BaseModel, Field
from pypdf import PdfReader
from fastapi.middleware.cors import CORSMiddleware

from ai import demo_mode, generate_json
import planner
from db import connect, dumps, loads, obj

app = FastAPI(title="AI 스터디메이트")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])
PERSPECTIVES = ["개념과 정의", "예시와 적용", "앞 주차와의 연결", "다른 해석"]
LEVELS = ["기초", "중급", "심화", "중급"]
PEER_NAMES = ["지식이", "사례이", "융합이", "탐구이"]
INITIAL_UNDERSTANDING = [
    "핵심 용어는 조금 알지만 정의와 원리를 다시 확인하고 싶다.",
    "개념은 들었지만 실제 사례에 적용하는 방법이 아직 헷갈린다.",
    "기본 원리를 알고 있어 이전 내용과의 연결을 궁금해한다.",
    "여러 설명을 비교할 수 있지만 다른 해석의 근거를 확인하고 싶다.",
]


def required(db, sql, args=()):
    row = db.execute(sql, args).fetchone()
    if not row:
        raise HTTPException(404, "대상을 찾을 수 없습니다.")
    return row


def study_data(db, study_id):
    study = obj(required(db, "SELECT * FROM studies WHERE id=?", (study_id,)))
    study["weeks"] = [dict(r) for r in db.execute(
        "SELECT * FROM weeks WHERE study_id=? ORDER BY week_no", (study_id,))]
    active_sessions = {r["week_no"]: r["id"] for r in db.execute(
        "SELECT id,week_no FROM sessions WHERE study_id=? AND status='active' ORDER BY id",
        (study_id,))}
    for week in study["weeks"]:
        week["review"] = loads(week["review"])
        week["active_session_id"] = active_sessions.get(week["week_no"])
    study["members"] = [dict(r) for r in db.execute(
        "SELECT * FROM members WHERE study_id=? ORDER BY member_no", (study_id,))]
    return study


@app.get("/health")
def health():
    return {"ok": True, "demo_mode": demo_mode(),
            "ai_ready": bool(os.getenv("OPENAI_API_KEY")) and not demo_mode()}


@app.get("/studies")
def list_studies():
    with connect() as db:
        return [dict(r) for r in db.execute("SELECT * FROM studies ORDER BY archived ASC,pinned DESC,id DESC")]


@app.put("/studies/{study_id}/pin")
def pin_study(study_id: int):
    with connect() as db:
        required(db, "SELECT id FROM studies WHERE id=? AND archived=0", (study_id,))
        db.execute("UPDATE studies SET pinned=0")
        db.execute("UPDATE studies SET pinned=1 WHERE id=?", (study_id,))
        return study_data(db, study_id)


class StudyDetails(BaseModel):
    title: str | None = Field(default=None, max_length=120)
    archived: bool | None = None


@app.put("/studies/{study_id}/details")
def edit_study_details(study_id: int, body: StudyDetails):
    with connect() as db:
        study = required(db, "SELECT * FROM studies WHERE id=?", (study_id,))
        title = study["title"] if body.title is None else body.title.strip()
        if not title:
            raise HTTPException(400, "채팅방 이름을 입력해 주세요.")
        archived = study["archived"] if body.archived is None else int(body.archived)
        db.execute("UPDATE studies SET title=?,archived=?,pinned=? WHERE id=?",
                   (title, archived, 0 if archived else study["pinned"], study_id))
        return study_data(db, study_id)


async def read_pdf(upload: UploadFile):
    if not (upload.filename or "").lower().endswith(".pdf"):
        raise HTTPException(400, "PDF 파일을 선택해 주세요.")
    data = await upload.read(10_000_001)
    if len(data) > 10_000_000 or not data.startswith(b"%PDF"):
        raise HTTPException(400, "10MB 이하의 PDF 파일만 사용할 수 있습니다.")
    try:
        source = PdfReader(io.BytesIO(data))
        if len(source.pages) > 100:
            raise HTTPException(400, "교안은 100페이지 이하여야 합니다.")
        pages = [(i + 1, (page.extract_text() or "").strip()) for i, page in enumerate(source.pages)]
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(400, "PDF를 읽지 못했습니다.") from exc
    if sum(len(body) for _, body in pages) < 80:
        raise HTTPException(400, "텍스트가 부족한 PDF입니다. 스캔 문서는 OCR 후 업로드해 주세요.")
    return pages


@app.put("/studies/{study_id}/pdf")
async def replace_pdf(study_id: int, pdf: UploadFile = File(...)):
    pages = await read_pdf(pdf)
    with connect() as db:
        study = required(db, "SELECT * FROM studies WHERE id=?", (study_id,))
        db.execute("INSERT INTO page_history(study_id,pdf_version,page_no,body,pdf_name) "
                   "SELECT study_id,?,page_no,body,? FROM pages WHERE study_id=?",
                   (study["pdf_version"], study["pdf_name"], study_id))
        db.execute("DELETE FROM pages WHERE study_id=?", (study_id,))
        db.executemany("INSERT INTO pages VALUES(?,?,?)", [(study_id, n, text) for n, text in pages])
        db.execute("UPDATE studies SET pdf_name=?,pdf_version=pdf_version+1 WHERE id=?",
                   (pdf.filename, study_id))
        for week in db.execute("SELECT week_no,scope FROM weeks WHERE study_id=? AND status!='complete'", (study_id,)):
            if study["pdf_name"] and not re.fullmatch(r"\d+\s*[~\-]\s*\d+\s*쪽", week["scope"]):
                continue
            first = min(len(pages), math.ceil((week["week_no"] - 1) * len(pages) / study["weeks"]) + 1)
            last = max(first, math.ceil(week["week_no"] * len(pages) / study["weeks"]))
            db.execute("UPDATE weeks SET scope=? WHERE study_id=? AND week_no=?",
                       (f"{first}~{last}쪽", study_id, week["week_no"]))
        return study_data(db, study_id)


@app.post("/studies")
async def create_study(
    title: str = Form(...), goal: str = Form(...), start_date: date = Form(...),
    weeks: int = Form(...), hours_per_week: float = Form(...),
    member_count: int = Form(3), rules: str = Form("매주 정해진 범위를 공부하고 랩미팅에서 발표한다."),
    member_profiles: str = Form(""),
    pdf: UploadFile | None = File(None),
):
    if not 1 <= weeks <= 26 or not 0.5 <= hours_per_week <= 80 or not 1 <= member_count <= 4:
        raise HTTPException(400, "기간, 시간 또는 AI 스터디원 수가 범위를 벗어났습니다.")
    if not title.strip() or not goal.strip():
        raise HTTPException(400, "주제와 목표를 입력해 주세요.")
    try:
        profiles = json.loads(member_profiles) if member_profiles else []
    except ValueError as exc:
        raise HTTPException(400, "AI 스터디원 설정을 읽지 못했습니다.") from exc
    if profiles and (not isinstance(profiles, list) or len(profiles) != member_count or any(
        not isinstance(p, dict) or p.get("level") not in LEVELS or
        not isinstance(p.get("understanding"), str) or len(p["understanding"]) > 500
        for p in profiles
    )):
        raise HTTPException(400, "AI 스터디원 수준과 이해 상태를 확인해 주세요.")
    pages = []
    if pdf is not None:
        pages = await read_pdf(pdf)
    page_count = len(pages)
    with connect() as db:
        cur = db.execute(
            "INSERT INTO studies(title,goal,start_date,weeks,hours_per_week,member_count,rules,pdf_name) VALUES(?,?,?,?,?,?,?,?)",
            (title.strip(), goal.strip(), start_date.isoformat(), weeks, hours_per_week, member_count,
             rules.strip(), pdf.filename if pdf else ""),
        )
        study_id = cur.lastrowid
        db.executemany("INSERT INTO pages VALUES(?,?,?)", [(study_id, n, body) for n, body in pages])
        for number in range(1, weeks + 1):
            first = min(page_count, math.ceil((number - 1) * page_count / weeks) + 1) if page_count else 1
            last = max(first, math.ceil(number * page_count / weeks)) if page_count else 0
            if pages:
                week_title = f"{number}주차"
                scope = f"{first}~{last}쪽" if first <= last else "이전 범위 복습"
            elif weeks == 1:
                week_title, scope = "학습 목표 정리", "핵심 개념과 예시를 찾아 내 말로 설명하기"
            elif number == 1:
                week_title, scope = "핵심 개념 찾기", "학습 목표와 관련된 핵심 용어와 정의 정리하기"
            elif number == weeks:
                week_title, scope = "설명과 복습", "배운 내용을 연결해 설명하고 남은 질문 정리하기"
            else:
                week_title, scope = "원리와 예시", "작동 원리를 이해하고 실제 예시에 적용하기"
            meeting = start_date + timedelta(days=number * 7 - 1)
            db.execute("INSERT INTO weeks(study_id,week_no,title,scope,meeting_date) VALUES(?,?,?,?,?)",
                       (study_id, number, week_title, scope, meeting.isoformat()))
        for number in range(1, member_count + 1):
            profile = profiles[number-1] if profiles else {}
            db.execute("INSERT INTO members(study_id,member_no,name,perspective,level,understanding) VALUES(?,?,?,?,?,?)",
                       (study_id, number, PEER_NAMES[(number-1) % 4], PERSPECTIVES[(number-1) % 4],
                        profile.get("level", LEVELS[(number-1) % 4]),
                        profile.get("understanding", INITIAL_UNDERSTANDING[(number-1) % 4]).strip()))
        return study_data(db, study_id)


@app.get("/studies/{study_id}")
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


@app.put("/studies/{study_id}/weeks/{week_no}")
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


@app.post("/studies/{study_id}/plan-draft")
async def plan_draft(study_id: int):
    with connect() as db:
        study = study_data(db, study_id)
        samples = [dict(r) for r in db.execute(
            "SELECT page_no,substr(body,1,1000) AS body FROM pages WHERE study_id=? ORDER BY page_no LIMIT 20", (study_id,))]
    result = await generate_json(
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


@app.post("/studies/{study_id}/replan-draft")
async def replan_draft(study_id: int):
    with connect() as db:
        study = study_data(db, study_id)
    remaining = [w for w in study["weeks"] if w["status"] != "complete"]
    if not remaining:
        raise HTTPException(400, "변경할 남은 주차가 없습니다.")
    result = await generate_json(
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


class Note(BaseModel):
    text: str = Field(default="", max_length=12000)


@app.post("/studies/{study_id}/weeks/{week_no}/sessions")
def start_session(study_id: int, week_no: int, body: Note):
    with connect() as db:
        required(db, "SELECT 1 FROM weeks WHERE study_id=? AND week_no=?", (study_id, week_no))
        note = body.text.strip()
        if note and len(note) < 10:
            raise HTTPException(400, "학습 정리를 적는다면 10자 이상 적어 주세요.")
        active = db.execute("SELECT id FROM sessions WHERE study_id=? AND week_no=? AND status='active'", (study_id, week_no)).fetchone()
        if active:
            raise HTTPException(409, f"진행 중인 세션이 있습니다: {active['id']}")
        cur = db.execute("INSERT INTO sessions(study_id,week_no,initial_note) VALUES(?,?,?)",
                         (study_id, week_no, note))
        db.execute("UPDATE weeks SET status='in_progress' WHERE study_id=? AND week_no=?", (study_id, week_no))
        return {"session_id": cur.lastrowid}


def session_data(db, session_id):
    session = obj(required(db, "SELECT * FROM sessions WHERE id=?", (session_id,)))
    study = required(db, "SELECT pdf_name,pdf_version,weeks FROM studies WHERE id=?", (session["study_id"],))
    session["pdf_name"] = study["pdf_name"]
    session["pdf_version"] = study["pdf_version"]
    session["total_weeks"] = study["weeks"]
    session["page_count"] = db.execute("SELECT COUNT(*) FROM pages WHERE study_id=?",
                                       (session["study_id"],)).fetchone()[0]
    session["week"] = obj(required(db, "SELECT * FROM weeks WHERE study_id=? AND week_no=?",
                                   (session["study_id"], session["week_no"])))
    session["week"]["review"] = loads(session["week"]["review"])
    session["unanswered"] = loads(session["unanswered"])
    session["messages"] = [dict(r) for r in db.execute(
        "SELECT * FROM messages WHERE session_id=? ORDER BY id", (session_id,))]
    session["members"] = [dict(r) for r in db.execute(
        "SELECT * FROM members WHERE study_id=? ORDER BY member_no", (session["study_id"],))]
    return session


@app.get("/sessions/{session_id}")
def get_session(session_id: int):
    with connect() as db:
        return session_data(db, session_id)


@app.get("/sessions/{session_id}/sources/{message_id}")
def message_source(session_id: int, message_id: int):
    with connect() as db:
        session = required(db, "SELECT study_id FROM sessions WHERE id=?", (session_id,))
        message = required(db, "SELECT page_no,pdf_version FROM messages WHERE id=? AND session_id=?",
                           (message_id, session_id))
        if message["page_no"] is None:
            raise HTTPException(404, "이 메시지에는 교안 쪽수가 없습니다.")
        study = required(db, "SELECT pdf_name,pdf_version FROM studies WHERE id=?", (session["study_id"],))
        version = message["pdf_version"] if message["pdf_version"] is not None else 0
        if version == study["pdf_version"]:
            page = required(db, "SELECT body FROM pages WHERE study_id=? AND page_no=?",
                            (session["study_id"], message["page_no"]))
            name = study["pdf_name"]
        else:
            page = required(db, "SELECT body,pdf_name FROM page_history "
                            "WHERE study_id=? AND pdf_version=? AND page_no=?",
                            (session["study_id"], version, message["page_no"]))
            name = page["pdf_name"]
        return {"page_no": message["page_no"], "text": page["body"], "pdf_name": name}


def source_pages(db, study_id, scope, note, week_no=None, total_weeks=None):
    all_pages = [dict(r) for r in db.execute("SELECT page_no,body FROM pages WHERE study_id=?", (study_id,))]
    match = re.search(r"(\d+)\s*[~\-]\s*(\d+)\s*쪽", scope)
    if match:
        a, b = map(int, match.groups())
        all_pages = [p for p in all_pages if a <= p["page_no"] <= b]
    elif week_no is not None and total_weeks:
        page_count = len(all_pages)
        a = min(page_count, math.ceil((week_no - 1) * page_count / total_weeks) + 1) if page_count else 1
        b = max(a, math.ceil(week_no * page_count / total_weeks)) if page_count else 0
        all_pages = [p for p in all_pages if a <= p["page_no"] <= b]
    terms = set(re.findall(r"[가-힣A-Za-z0-9]{3,}", note.lower()))
    all_pages.sort(key=lambda p: sum(p["body"].lower().count(t) for t in terms), reverse=True)
    return [{"page_no": p["page_no"], "text": p["body"][:2500]} for p in all_pages[:3]]


@app.post("/sessions/{session_id}/question")
async def next_question(session_id: int):
    with connect() as db:
        session = session_data(db, session_id)
        if session["status"] != "active":
            raise HTTPException(409, "종료된 세션입니다.")
        if session["messages"] and session["messages"][-1]["role"] in ("assistant", "assistant_hint"):
            raise HTTPException(409, "먼저 현재 질문에 답해 주세요.")
        study = study_data(db, session["study_id"])
        member = study["members"][(session["next_member"] - 1) % len(study["members"])]
        week = study["weeks"][session["week_no"] - 1]
        question_week = {**week, "review": week["review"] if week["include_previous_questions"] else []}
        question_count = sum(m["role"] == "assistant" for m in session["messages"])
        review_focus = (week["review"][0] if week["include_previous_questions"] and
                        session["week_no"] > 1 and question_count == 0 and week["review"] else "")
        pages = source_pages(db, session["study_id"], week["scope"],
                             session["initial_note"] or study["goal"], session["week_no"], len(study["weeks"]))
        previous_context, previous_pages = [], []
        if week["include_previous_questions"]:
            previous_context = [{"week_no": row["week_no"], "initial_note": row["initial_note"],
                                 "revised_note": row["revised_note"], "minutes": loads(row["minutes"]) if row["minutes"] else {}}
                                for row in db.execute(
                                    "SELECT week_no,initial_note,revised_note,minutes FROM sessions "
                                    "WHERE study_id=? AND week_no<? AND status='finished' ORDER BY week_no DESC,id DESC LIMIT 4",
                                    (session["study_id"], session["week_no"]))]
            seen = {p["page_no"] for p in pages}
            for older in reversed(study["weeks"][:session["week_no"] - 1]):
                for page in source_pages(db, session["study_id"], older["scope"], study["goal"],
                                         older["week_no"], len(study["weeks"]))[:1]:
                    if page["page_no"] not in seen and len(previous_pages) < 3:
                        previous_pages.append(page)
                        seen.add(page["page_no"])
    result = await generate_json(
        "여러 사람이 함께 공부하는 대화의 다음 차례를 만드세요. JSON 키는 speaker_no,comment,comment_member_no,question,page_no,understanding입니다. "
        "members 중 대화 맥락에 어울리는 speaker_no를 고르세요. suggested_member_no는 참고일 뿐이고, 필요하면 같은 동료가 후속 질문을 해도 됩니다. "
        "comment는 다른 동료의 짧은 공감·보충 의견이 실제로 도움이 될 때만 넣고, 아니면 빈 문자열로 두세요. comment_member_no는 그 동료 번호입니다. "
        "질문은 한 개만 하세요. 각 동료의 수준·누적 이해·앞선 발언을 반영하고, 반복적인 칭찬이나 시험 문제 같은 말투를 피하세요. "
        "사용자 답변과 직전 동료의 반응에 맞춰 후속 질문을 바꾸세요. 발표문이 비어 있으면 current_source_pages의 교안 내용을 중심으로 질문하세요. "
        "사용자 답변을 그대로 인용해 질문하지 마세요. 무관한 답변을 받았다면 교안의 핵심 개념으로 부드럽게 돌아오세요. "
        "include_previous_questions가 참이고 review_focus가 있으면 이번 세션 첫 질문은 그 복습 내용을 먼저 확인하세요. "
        "거짓이면 이번 주차 범위만 질문하세요. "
        "거짓이어도 동료들의 누적 understanding을 지우거나 되돌리지 마세요. 기존 질문을 반복하지 말고 바로 정답을 알려주지 마세요. "
        "교안 근거가 있다면 page_no에 제공된 쪽수 하나를 쓰고, understanding에는 질문자가 이번 대화에서 이해한 내용을 짧게 적으세요.",
        {"study_goal": study["goal"], "week": question_week, "member": member,
         "members": study["members"], "suggested_member_no": member["member_no"],
         "initial_note": session["initial_note"], "messages": session["messages"][-12:],
         "question_count": question_count, "review_focus": review_focus,
         "asked_questions": [m["body"] for m in session["messages"] if m["role"] == "assistant"][-20:],
         "include_previous_questions": bool(week["include_previous_questions"]),
         "current_source_pages": pages, "previous_source_pages": previous_pages,
         "previous_study": previous_context, "source_pages": pages + previous_pages},
    )
    question = str(result.get("question", "")).strip()
    if not question:
        raise HTTPException(502, "질문이 비어 있습니다.")
    prior_questions = {m["body"].strip() for m in session["messages"] if m["role"] == "assistant"}
    if question in prior_questions:
        result = await generate_json(
            "앞선 질문과 겹쳤습니다. 아래 질문과 다른 새 질문 한 개를 만드세요. "
            "JSON 키는 speaker_no,comment,comment_member_no,question,page_no,understanding입니다. "
            "이번 주 범위와 교안에 근거하고, 답변의 맥락을 이어 가세요.",
            {"study_goal": study["goal"], "week": question_week, "member": member,
             "members": study["members"], "messages": session["messages"][-12:],
             "question_count": question_count, "review_focus": review_focus,
             "asked_questions": list(prior_questions), "source_pages": pages + previous_pages,
             "current_source_pages": pages, "previous_source_pages": previous_pages},
        )
        question = str(result.get("question", "")).strip()
        if not question or question in prior_questions:
            raise HTTPException(502, "새 질문을 만들지 못했습니다. 다시 시도해 주세요.")
    member_no = result.get("speaker_no")
    speaker = next((m for m in study["members"] if m["member_no"] == member_no), member)
    comment = str(result.get("comment") or "").strip()[:500]
    comment_member_no = result.get("comment_member_no")
    if comment_member_no not in {m["member_no"] for m in study["members"]} or comment_member_no == speaker["member_no"]:
        comment = ""
    valid_pages = {p["page_no"] for p in pages + previous_pages}
    page_no = result.get("page_no") if result.get("page_no") in valid_pages else None
    if pages and not session["initial_note"] and page_no is None:
        raise HTTPException(502, "교안 근거가 있는 질문을 만들지 못했습니다. 다시 시도해 주세요.")
    with connect() as db:
        current = session_data(db, session_id)
        if len(current["messages"]) != len(session["messages"]):
            raise HTTPException(409, "세션이 변경되었습니다. 다시 시도해 주세요.")
        if comment:
            db.execute("INSERT INTO messages(session_id,role,member_no,body) VALUES(?,?,?,?)",
                       (session_id, "assistant_comment", comment_member_no, comment))
        db.execute("INSERT INTO messages(session_id,role,member_no,body,page_no,pdf_version) VALUES(?,?,?,?,?,?)",
                   (session_id, "assistant", speaker["member_no"], question, page_no,
                    study["pdf_version"] if page_no is not None else None))
        db.execute("UPDATE sessions SET next_member=? WHERE id=?",
                   (speaker["member_no"] % len(study["members"]) + 1, session_id))
        db.execute("UPDATE members SET understanding=? WHERE study_id=? AND member_no=?",
                   (str(result.get("understanding") or speaker["understanding"])[:500],
                    session["study_id"], speaker["member_no"]))
        return session_data(db, session_id)


@app.post("/sessions/{session_id}/explain")
async def explain(session_id: int):
    with connect() as db:
        session = session_data(db, session_id)
        messages = session["messages"]
        if session["status"] != "active" or not messages or messages[-1]["role"] != "assistant":
            raise HTTPException(409, "설명을 요청할 질문이 없습니다.")
        question = messages[-1]
        study = study_data(db, session["study_id"])
        week = study["weeks"][session["week_no"] - 1]
        pages = source_pages(db, session["study_id"], week["scope"], question["body"],
                             session["week_no"], len(study["weeks"]))
        if week["include_previous_questions"] and question["page_no"] not in {p["page_no"] for p in pages}:
            older = [p for w in study["weeks"][:session["week_no"] - 1]
                     for p in source_pages(db, session["study_id"], w["scope"], question["body"],
                                           w["week_no"], len(study["weeks"]))]
            pages = (pages + [p for p in older if p["page_no"] == question["page_no"]])[:4]
    result = await generate_json(
        "교안 기반 설명을 요청받았습니다. 친구가 옆에서 도와주듯 자연스러운 존댓말로 짧은 힌트를 주세요. "
        "교안에 없는 사실이나 페이지 번호를 만들지 마세요. 교안이 없으면 일반적인 생각의 방향만 알려주세요. "
        "JSON 키는 explanation,page_no입니다.",
        {"goal": study["goal"], "week": week, "question": question["body"],
         "initial_note": session["initial_note"], "messages": messages[-12:], "source_pages": pages},
    )
    explanation = str(result.get("explanation", "")).strip()
    if not explanation:
        raise HTTPException(502, "설명이 비어 있습니다.")
    valid_pages = {p["page_no"] for p in pages}
    page_no = result.get("page_no") if result.get("page_no") in valid_pages else None
    with connect() as db:
        current = session_data(db, session_id)
        if current["status"] != "active" or len(current["messages"]) != len(messages):
            raise HTTPException(409, "세션이 변경되었습니다. 다시 시도해 주세요.")
        db.execute("INSERT INTO messages(session_id,role,member_no,body,page_no,pdf_version) VALUES(?,?,?,?,?,?)",
                   (session_id, "assistant_hint", question["member_no"], explanation, page_no,
                    study["pdf_version"] if page_no is not None else None))
        return session_data(db, session_id)


class Answer(BaseModel):
    text: str = Field(min_length=1, max_length=12000)
    needs_review: bool = False


@app.post("/sessions/{session_id}/answer")
async def answer(session_id: int, body: Answer):
    text = body.text.strip()
    with connect() as db:
        session = session_data(db, session_id)
        if session["status"] != "active":
            raise HTTPException(409, "종료된 대화입니다.")
        study = study_data(db, session["study_id"])
    # 일정·계획 변경 같은 운영 요청은 채팅에서 바로 반영하고 스터디원이 확인 메시지를 남긴다.
    command = await planner.parse(text, session["week_no"], len(study["weeks"]), study["weeks"])
    if command:
        with connect() as db:
            reply = await planner.apply(db, study_data(db, session["study_id"]), command, session["week_no"])
            speaker = (session["next_member"] - 1) % max(1, len(study["members"])) + 1
            db.execute("INSERT INTO messages(session_id,role,body) VALUES(?,?,?)", (session_id, "user", text))
            db.execute("INSERT INTO messages(session_id,role,member_no,body) VALUES(?,?,?,?)",
                       (session_id, "assistant_plan", speaker, reply or "알겠어요!"))
            response = session_data(db, session_id)
            response["plan_changed"] = True
            return response
    if not session["messages"] or session["messages"][-1]["role"] not in ("assistant", "assistant_hint"):
        # 질문이 없을 때 보낸 말은 대화로 남기고, 다음 질문이 이를 이어받는다.
        with connect() as db:
            db.execute("INSERT INTO messages(session_id,role,body) VALUES(?,?,?)", (session_id, "user", text))
            return session_data(db, session_id)
    with connect() as db:
        session = session_data(db, session_id)
        question = next(m for m in reversed(session["messages"]) if m["role"] == "assistant")
        study = study_data(db, session["study_id"])
        week = study["weeks"][session["week_no"] - 1]
        page_query = body.text.strip() if "?" in body.text or "？" in body.text else question["body"] + " " + body.text.strip()
        pages = source_pages(db, session["study_id"], week["scope"], page_query,
                             session["week_no"], len(study["weeks"]))
        if question["page_no"] is not None and question["page_no"] not in {p["page_no"] for p in pages}:
            cited = db.execute("SELECT page_no,body FROM pages WHERE study_id=? AND page_no=?",
                               (session["study_id"], question["page_no"])).fetchone()
            if cited and week["include_previous_questions"]:
                pages = [{"page_no": cited["page_no"], "text": cited["body"][:2500]}] + pages[:2]
        member = next(m for m in study["members"] if m["member_no"] == question["member_no"])
    result = await generate_json(
        "답변 검토: 스터디 동료로서 사용자의 답변이 직전 질문에 실제로 답했는지 먼저 확인하세요. "
        "교안 페이지가 있으면 그 내용과 맞는 부분, 다른 부분, 확인할 수 없는 부분을 구분하세요. "
        "교안이 없거나 근거가 부족하면 정답이라고 단정하지 마세요. 무관하거나 장난스러운 답변은 인용하지 말고 "
        "질문으로 돌아올 수 있게 친절하게 말하세요. 사용자가 역으로 질문했다면 그 질문에 교안 기준으로 짧게 답하고 대화를 이어가세요. "
        "다른 동료들도 대화를 듣고 있으므로 이번 답에서 새로 이해한 점을 understanding에 반영하세요. "
        "자연스러운 한국어 존댓말 한두 문장으로 반응하세요. JSON 키는 reaction,alignment,page_no,understanding입니다. "
        "alignment는 supported,partial,off_topic,uncertain,user_question 중 하나입니다. page_no는 제공된 교안 쪽수만 쓰세요.",
        {"question": question["body"], "answer": body.text.strip(), "member": member,
         "week": week, "source_pages": pages, "messages": session["messages"][-8:]},
    )
    reaction = str(result.get("reaction", "")).strip()
    if not reaction:
        raise HTTPException(502, "답변에 대한 반응을 만들지 못했습니다.")
    alignment = result.get("alignment")
    if alignment not in ("supported", "partial", "off_topic", "uncertain", "user_question") or (not pages and alignment != "user_question"):
        alignment = "uncertain"
    page_no = result.get("page_no") if result.get("page_no") in {p["page_no"] for p in pages} else None
    with connect() as db:
        current = session_data(db, session_id)
        if current["status"] != "active" or len(current["messages"]) != len(session["messages"]):
            raise HTTPException(409, "세션이 변경되었습니다. 다시 시도해 주세요.")
        db.execute("INSERT INTO messages(session_id,role,body) VALUES(?,?,?)",
                   (session_id, "user", body.text.strip()))
        db.execute("INSERT INTO messages(session_id,role,member_no,body,page_no,pdf_version) VALUES(?,?,?,?,?,?)",
                   (session_id, "assistant_reaction", question["member_no"], reaction, page_no,
                    study["pdf_version"] if page_no is not None else None))
        if result.get("understanding"):
            db.execute("UPDATE members SET understanding=? WHERE study_id=? AND member_no=?",
                       (str(result["understanding"])[:500], session["study_id"], question["member_no"]))
        if body.needs_review:
            pending = session["unanswered"] + [question["body"]]
            db.execute("UPDATE sessions SET unanswered=? WHERE id=?", (dumps(pending), session_id))
        response = session_data(db, session_id)
        response["answer_alignment"] = alignment
        return response


class Finish(BaseModel):
    revised_note: str = Field(default="", max_length=12000)


@app.post("/sessions/{session_id}/finish")
async def finish(session_id: int, body: Finish):
    with connect() as db:
        session = session_data(db, session_id)
        if session["status"] != "active":
            raise HTTPException(409, "이미 종료된 세션입니다.")
        study = study_data(db, session["study_id"])
        week = study["weeks"][session["week_no"] - 1]
        last_user_note = next((m["body"] for m in reversed(session["messages"]) if m["role"] == "user"), "")
        learned_source = body.revised_note.strip() or last_user_note or session["initial_note"] or study["goal"]
        pages = source_pages(db, session["study_id"], week["scope"], learned_source,
                             session["week_no"], len(study["weeks"]))
        pending = list(session["unanswered"])
        if session["messages"] and session["messages"][-1]["role"] in ("assistant", "assistant_hint"):
            pending.append(next(m["body"] for m in reversed(session["messages"]) if m["role"] == "assistant"))
    summary = await generate_json(
        "랩미팅 회의록을 한국어로 요약하세요. JSON 키는 summary, next_checks입니다. "
        "사용자 발언과 AI 질문을 구별하고, 근거 없는 사실을 확정하지 마세요. next_checks는 문자열 배열입니다.",
        {"initial_note": session["initial_note"], "revised_note": body.revised_note,
         "messages": session["messages"], "unanswered": pending, "source_pages": pages},
    )
    checks = summary.get("next_checks", [])
    if not isinstance(checks, list):
        checks = []
    checks = list(dict.fromkeys(str(x).strip()[:500] for x in pending + checks
                                    if str(x).strip()))[:20]
    minutes = {"summary": str(summary.get("summary", "")), "source_pages": [p["page_no"] for p in pages],
               "initial_note": session["initial_note"], "revised_note": body.revised_note,
               "messages": session["messages"], "next_checks": checks}
    with connect() as db:
        required(db, "SELECT id FROM sessions WHERE id=? AND status='active'", (session_id,))
        db.execute("UPDATE sessions SET revised_note=?,unanswered=?,minutes=?,status='finished' WHERE id=?",
                   (body.revised_note, dumps(checks), dumps(minutes), session_id))
        for question in checks:
            db.execute("INSERT INTO review_items(study_id,question,source_week) VALUES(?,?,?) "
                       "ON CONFLICT(study_id,question) DO UPDATE SET source_week=excluded.source_week,"
                       "status='open',resolved_at=NULL",
                       (session["study_id"], question, session["week_no"]))
        for member in study["members"]:
            learned = f"{member['understanding']} | {session['week_no']}주차 학습: {learned_source}"
            db.execute("UPDATE members SET understanding=? WHERE study_id=? AND member_no=?",
                       (learned[-500:], session["study_id"], member["member_no"]))
        db.execute("UPDATE weeks SET status='complete',progress_percent=100,remaining_scope='' WHERE study_id=? AND week_no=?",
                   (session["study_id"], session["week_no"]))
        if session["week_no"] < len(study["weeks"]):
            next_no = session["week_no"] + 1
            next_week = required(db, "SELECT review FROM weeks WHERE study_id=? AND week_no=?",
                                 (session["study_id"], next_no))
            review = list(dict.fromkeys(loads(next_week["review"]) + checks))
            db.execute("UPDATE weeks SET review=? WHERE study_id=? AND week_no=?",
                       (dumps(review), session["study_id"], next_no))
        return session_data(db, session_id)


@app.get("/studies/{study_id}/minutes")
def list_minutes(study_id: int):
    with connect() as db:
        required(db, "SELECT 1 FROM studies WHERE id=?", (study_id,))
        return [{"week_no": r["week_no"], "session_id": r["id"], "minutes": json.loads(r["minutes"])}
                for r in db.execute("SELECT * FROM sessions WHERE study_id=? AND status='finished' ORDER BY week_no,id", (study_id,))]


@app.get("/studies/{study_id}/reviews")
def list_reviews(study_id: int):
    with connect() as db:
        required(db, "SELECT 1 FROM studies WHERE id=?", (study_id,))
        return [dict(row) for row in db.execute(
            "SELECT * FROM review_items WHERE study_id=? ORDER BY status='open' DESC,source_week,id",
            (study_id,))]


class ReviewEdit(BaseModel):
    resolved: bool


@app.put("/studies/{study_id}/reviews/{review_id}")
def edit_review(study_id: int, review_id: int, body: ReviewEdit):
    with connect() as db:
        item = required(db, "SELECT * FROM review_items WHERE id=? AND study_id=?", (review_id, study_id))
        if body.resolved:
            db.execute("UPDATE review_items SET status='done',resolved_at=? WHERE id=?",
                       (datetime.now(timezone.utc).isoformat(), review_id))
        else:
            db.execute("UPDATE review_items SET status='open',resolved_at=NULL WHERE id=?", (review_id,))
        weeks = list(db.execute("SELECT week_no,review FROM weeks WHERE study_id=? AND status!='complete' ORDER BY week_no",
                                (study_id,)))
        for index, week in enumerate(weeks):
            reviews = [q for q in loads(week["review"]) if q != item["question"]]
            if not body.resolved and index == 0:
                reviews.append(item["question"])
            db.execute("UPDATE weeks SET review=? WHERE study_id=? AND week_no=?",
                       (dumps(reviews), study_id, week["week_no"]))
        return dict(required(db, "SELECT * FROM review_items WHERE id=?", (review_id,)))


@app.get("/studies/{study_id}/learning-report")
def learning_report(study_id: int):
    with connect() as db:
        study = study_data(db, study_id)
        sessions = [dict(row) for row in db.execute(
            "SELECT * FROM sessions WHERE study_id=? AND status='finished' ORDER BY week_no,id", (study_id,))]
        all_reviews = [dict(row) for row in db.execute(
            "SELECT source_week,status FROM review_items WHERE study_id=?", (study_id,))]
        report_weeks = []
        total_questions = total_answers = 0
        for week in study["weeks"]:
            finished = [s for s in sessions if s["week_no"] == week["week_no"]]
            question_count = answer_count = 0
            for session in finished:
                counts = db.execute(
                    "SELECT role,COUNT(*) AS count FROM messages WHERE session_id=? "
                    "AND role IN ('assistant','user') GROUP BY role", (session["id"],))
                for row in counts:
                    if row["role"] == "assistant":
                        question_count += row["count"]
                    else:
                        answer_count += row["count"]
            total_questions += question_count
            total_answers += answer_count
            latest = finished[-1] if finished else None
            minutes = json.loads(latest["minutes"]) if latest and latest["minutes"] else {}
            first_answer = db.execute(
                "SELECT body FROM messages WHERE session_id=? AND role='user' ORDER BY id LIMIT 1",
                (latest["id"],)).fetchone() if latest else None
            baseline = (latest["initial_note"] if latest else "") or (first_answer["body"] if first_answer else "")
            report_weeks.append({
                "week_no": week["week_no"], "title": week["title"], "status": week["status"],
                "initial_note": latest["initial_note"] if latest else "",
                "baseline_text": baseline,
                "baseline_label": "대화 전 내 생각" if latest and latest["initial_note"] else "처음 남긴 답변",
                "revised_note": latest["revised_note"] if latest else "",
                "summary": minutes.get("summary", ""),
                "question_count": question_count, "answer_count": answer_count,
                "source_pages": minutes.get("source_pages", []),
                "open_reviews": sum(r["status"] == "open" and r["source_week"] == week["week_no"]
                                    for r in all_reviews),
            })
        return {
            "title": study["title"], "goal": study["goal"],
            "total_weeks": len(study["weeks"]),
            "completed_weeks": sum(w["status"] == "complete" for w in study["weeks"]),
            "question_count": total_questions, "answer_count": total_answers,
            "open_reviews": sum(r["status"] == "open" for r in all_reviews),
            "resolved_reviews": sum(r["status"] == "done" for r in all_reviews),
            "weeks": report_weeks,
        }
