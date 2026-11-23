"""여러 라우터가 함께 쓰는 상수와 DB 조회 도우미."""
import io
import math
import re
from fastapi import HTTPException, UploadFile
from pypdf import PdfReader
from db import loads, obj


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
