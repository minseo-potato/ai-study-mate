"""AI 스터디메이트 local demo API. Start with: uvicorn main:app --reload"""
import io
import json
import math
import os
import re
from datetime import date, timedelta

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from pydantic import BaseModel, Field
from pypdf import PdfReader
from fastapi.middleware.cors import CORSMiddleware

from ai import generate_json
from db import connect, dumps, loads, obj

app = FastAPI(title="AI 스터디메이트")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])
PERSPECTIVES = ["개념과 정의", "예시와 적용", "앞 주차와의 연결", "다른 해석"]
LEVELS = ["기초", "중급", "심화", "중급"]


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
    return {"ok": True, "demo_mode": os.getenv("DEMO_MODE") == "1"}


@app.get("/studies")
def list_studies():
    with connect() as db:
        return [dict(r) for r in db.execute("SELECT * FROM studies ORDER BY id DESC")]


@app.post("/studies")
async def create_study(
    title: str = Form(...), goal: str = Form(...), start_date: date = Form(...),
    weeks: int = Form(...), hours_per_week: float = Form(...),
    member_count: int = Form(3), rules: str = Form("매주 정해진 범위를 공부하고 랩미팅에서 발표한다."),
    pdf: UploadFile = File(...),
):
    if not 1 <= weeks <= 26 or not 0.5 <= hours_per_week <= 80 or not 1 <= member_count <= 4:
        raise HTTPException(400, "기간, 시간 또는 AI 스터디원 수가 범위를 벗어났습니다.")
    if not title.strip() or not goal.strip() or not (pdf.filename or "").lower().endswith(".pdf"):
        raise HTTPException(400, "주제, 목표와 PDF 교안이 필요합니다.")
    data = await pdf.read(10_000_001)
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
    page_count = len(pages)
    with connect() as db:
        cur = db.execute(
            "INSERT INTO studies(title,goal,start_date,weeks,hours_per_week,member_count,rules,pdf_name) VALUES(?,?,?,?,?,?,?,?)",
            (title.strip(), goal.strip(), start_date.isoformat(), weeks, hours_per_week, member_count, rules.strip(), pdf.filename),
        )
        study_id = cur.lastrowid
        db.executemany("INSERT INTO pages VALUES(?,?,?)", [(study_id, n, body) for n, body in pages])
        for number in range(1, weeks + 1):
            first = math.ceil((number - 1) * page_count / weeks) + 1
            last = math.ceil(number * page_count / weeks)
            scope = f"{first}~{last}쪽" if first <= last else "이전 범위 복습"
            meeting = start_date + timedelta(days=number * 7 - 1)
            db.execute("INSERT INTO weeks(study_id,week_no,title,scope,meeting_date) VALUES(?,?,?,?,?)",
                       (study_id, number, f"{number}주차", scope, meeting.isoformat()))
        for number in range(1, member_count + 1):
            db.execute("INSERT INTO members(study_id,member_no,name,perspective,level) VALUES(?,?,?,?,?)",
                       (study_id, number, f"스터디원 {number}", PERSPECTIVES[(number-1) % 4], LEVELS[(number-1) % 4]))
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


@app.put("/studies/{study_id}/weeks/{week_no}")
def edit_week(study_id: int, week_no: int, body: WeekEdit):
    if body.status not in ("planned", "in_progress", "complete"):
        raise HTTPException(400, "잘못된 주차 상태입니다.")
    with connect() as db:
        required(db, "SELECT 1 FROM weeks WHERE study_id=? AND week_no=?", (study_id, week_no))
        db.execute("UPDATE weeks SET title=?,scope=?,meeting_date=?,status=? WHERE study_id=? AND week_no=?",
                   (body.title, body.scope, body.meeting_date.isoformat(), body.status, study_id, week_no))
        return study_data(db, study_id)


@app.post("/studies/{study_id}/plan-draft")
async def plan_draft(study_id: int):
    with connect() as db:
        study = study_data(db, study_id)
        samples = [dict(r) for r in db.execute(
            "SELECT page_no,substr(body,1,1000) AS body FROM pages WHERE study_id=? ORDER BY page_no LIMIT 20", (study_id,))]
    result = await generate_json(
        "한국어 주간 학습 계획을 제안하세요. weeks 배열에 week_no,title,scope를 넣으세요. 주차 수를 정확히 맞추고 실제 교안 페이지 범위를 사용하세요.",
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
    text: str = Field(min_length=10, max_length=12000)


@app.post("/studies/{study_id}/weeks/{week_no}/sessions")
def start_session(study_id: int, week_no: int, body: Note):
    with connect() as db:
        required(db, "SELECT 1 FROM weeks WHERE study_id=? AND week_no=?", (study_id, week_no))
        active = db.execute("SELECT id FROM sessions WHERE study_id=? AND week_no=? AND status='active'", (study_id, week_no)).fetchone()
        if active:
            raise HTTPException(409, f"진행 중인 세션이 있습니다: {active['id']}")
        cur = db.execute("INSERT INTO sessions(study_id,week_no,initial_note) VALUES(?,?,?)",
                         (study_id, week_no, body.text.strip()))
        db.execute("UPDATE weeks SET status='in_progress' WHERE study_id=? AND week_no=?", (study_id, week_no))
        return {"session_id": cur.lastrowid}


def session_data(db, session_id):
    session = obj(required(db, "SELECT * FROM sessions WHERE id=?", (session_id,)))
    session["unanswered"] = loads(session["unanswered"])
    session["messages"] = [dict(r) for r in db.execute(
        "SELECT * FROM messages WHERE session_id=? ORDER BY id", (session_id,))]
    return session


@app.get("/sessions/{session_id}")
def get_session(session_id: int):
    with connect() as db:
        return session_data(db, session_id)


def source_pages(db, study_id, scope, note):
    all_pages = [dict(r) for r in db.execute("SELECT page_no,body FROM pages WHERE study_id=?", (study_id,))]
    match = re.search(r"(\d+)\s*[~\-]\s*(\d+)\s*쪽", scope)
    if match:
        a, b = map(int, match.groups())
        all_pages = [p for p in all_pages if a <= p["page_no"] <= b] or all_pages
    terms = set(re.findall(r"[가-힣A-Za-z0-9]{3,}", note.lower()))
    all_pages.sort(key=lambda p: sum(p["body"].lower().count(t) for t in terms), reverse=True)
    return [{"page_no": p["page_no"], "text": p["body"][:2500]} for p in all_pages[:3]]


@app.post("/sessions/{session_id}/question")
async def next_question(session_id: int):
    with connect() as db:
        session = session_data(db, session_id)
        if session["status"] != "active":
            raise HTTPException(409, "종료된 세션입니다.")
        if session["messages"] and session["messages"][-1]["role"] == "assistant":
            raise HTTPException(409, "먼저 현재 질문에 답해 주세요.")
        study = study_data(db, session["study_id"])
        member = study["members"][(session["next_member"] - 1) % len(study["members"])]
        week = study["weeks"][session["week_no"] - 1]
        pages = source_pages(db, session["study_id"], week["scope"], session["initial_note"])
    result = await generate_json(
        "당신은 채점자가 아닌 같은 교안을 공부하는 동료입니다. 사용자의 발표와 이전 대화를 바탕으로 한국어 질문 하나만 하세요. "
        "기존 질문을 반복하지 마세요. 바로 정답을 알려주지 마세요. 교안 근거가 있는 경우 page_no에 제공된 쪽수 하나를 쓰세요. "
        "JSON 키는 question,page_no,understanding입니다. understanding은 이 동료가 이번 대화에서 이해한 내용을 짧게 적으세요.",
        {"study_goal": study["goal"], "week": week, "member": member,
         "initial_note": session["initial_note"], "messages": session["messages"][-12:], "source_pages": pages},
    )
    question = str(result.get("question", "")).strip()
    if not question:
        raise HTTPException(502, "질문이 비어 있습니다.")
    valid_pages = {p["page_no"] for p in pages}
    page_no = result.get("page_no") if result.get("page_no") in valid_pages else None
    with connect() as db:
        current = session_data(db, session_id)
        if len(current["messages"]) != len(session["messages"]):
            raise HTTPException(409, "세션이 변경되었습니다. 다시 시도해 주세요.")
        db.execute("INSERT INTO messages(session_id,role,member_no,body,page_no) VALUES(?,?,?,?,?)",
                   (session_id, "assistant", member["member_no"], question, page_no))
        db.execute("UPDATE sessions SET next_member=? WHERE id=?",
                   (session["next_member"] % len(study["members"]) + 1, session_id))
        db.execute("UPDATE members SET understanding=? WHERE study_id=? AND member_no=?",
                   (str(result.get("understanding", ""))[:500], session["study_id"], member["member_no"]))
        return session_data(db, session_id)


class Answer(BaseModel):
    text: str = Field(min_length=1, max_length=12000)
    needs_review: bool = False


@app.post("/sessions/{session_id}/answer")
def answer(session_id: int, body: Answer):
    with connect() as db:
        session = session_data(db, session_id)
        if session["status"] != "active" or not session["messages"] or session["messages"][-1]["role"] != "assistant":
            raise HTTPException(409, "답할 질문이 없습니다.")
        db.execute("INSERT INTO messages(session_id,role,body) VALUES(?,?,?)",
                   (session_id, "user", body.text.strip()))
        if body.needs_review:
            pending = session["unanswered"] + [session["messages"][-1]["body"]]
            db.execute("UPDATE sessions SET unanswered=? WHERE id=?", (dumps(pending), session_id))
        return session_data(db, session_id)


class Finish(BaseModel):
    revised_note: str = Field(min_length=10, max_length=12000)


@app.post("/sessions/{session_id}/finish")
async def finish(session_id: int, body: Finish):
    with connect() as db:
        session = session_data(db, session_id)
        if session["status"] != "active":
            raise HTTPException(409, "이미 종료된 세션입니다.")
        study = study_data(db, session["study_id"])
        week = study["weeks"][session["week_no"] - 1]
        pages = source_pages(db, session["study_id"], week["scope"], body.revised_note)
    summary = await generate_json(
        "랩미팅 회의록을 한국어로 요약하세요. JSON 키는 summary, next_checks입니다. "
        "사용자 발언과 AI 질문을 구별하고, 근거 없는 사실을 확정하지 마세요. next_checks는 문자열 배열입니다.",
        {"initial_note": session["initial_note"], "revised_note": body.revised_note,
         "messages": session["messages"], "unanswered": session["unanswered"], "source_pages": pages},
    )
    checks = summary.get("next_checks", [])
    if not isinstance(checks, list):
        checks = []
    checks = list(dict.fromkeys(session["unanswered"] + [str(x) for x in checks]))[:20]
    minutes = {"summary": str(summary.get("summary", "")), "source_pages": [p["page_no"] for p in pages],
               "initial_note": session["initial_note"], "revised_note": body.revised_note,
               "messages": session["messages"], "next_checks": checks}
    with connect() as db:
        required(db, "SELECT id FROM sessions WHERE id=? AND status='active'", (session_id,))
        db.execute("UPDATE sessions SET revised_note=?,unanswered=?,minutes=?,status='finished' WHERE id=?",
                   (body.revised_note, dumps(checks), dumps(minutes), session_id))
        db.execute("UPDATE weeks SET status='complete' WHERE study_id=? AND week_no=?",
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
