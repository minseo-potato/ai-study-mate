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


# 스터디원마다 맡은 역할. AI에게 그대로 넘겨 말투와 질문 방향을 정한다.
PERSONAS = {
    "개념과 정의": {
        "role": "개념 정리",
        "focus": "용어의 정확한 뜻, 핵심 원리, 비슷한 개념 사이의 차이",
        "style": "차분하고 꼼꼼한 말투. 모호한 표현을 짚고 '정확히는 어떤 뜻일까요?'처럼 정의를 확인한다.",
    },
    "예시와 적용": {
        "role": "사례 찾기",
        "focus": "실생활·실무 예시, 배운 내용을 실제 문제에 적용하는 방법",
        "style": "밝고 구체적인 말투. '예를 들어 ~한 상황이라면?'처럼 장면을 떠올리게 한다.",
    },
    "앞 주차와의 연결": {
        "role": "흐름 연결",
        "focus": "앞 주차 내용·다른 개념과의 관계, 전체 학습 흐름 속 위치",
        "style": "큰 그림을 보는 말투. '앞에서 본 ~와 이어 보면'처럼 내용을 연결한다.",
    },
    "다른 해석": {
        "role": "깊이 파기",
        "focus": "근거와 이유, 반례, 한계, 다른 관점",
        "style": "호기심 많고 살짝 도전적인 말투. '그런데 만약 ~라면 어떻게 될까요?'처럼 되묻는다.",
    },
}
LEVEL_GUIDE = {
    "기초": "쉬운 말로 한 번에 하나씩 묻고, 어려운 용어는 풀어서 말한다.",
    "중급": "핵심 원리와 '왜 그런지'를 묻는다.",
    "심화": "응용, 비교, 한계까지 깊게 묻고 더 정밀한 설명을 요구한다.",
}
MEMBER_LEVELS = ("기초", "중급", "심화")


def learning_messages(messages: list) -> list:
    """일정·계획 변경 대화(사용자 요청과 assistant_plan 확인)를 뺀, 학습에 관한 대화만 돌려준다."""
    out = []
    for i, m in enumerate(messages):
        if m["role"] == "assistant_plan":
            continue
        if m["role"] == "user" and i + 1 < len(messages) and messages[i + 1]["role"] == "assistant_plan":
            continue
        out.append(m)
    return out


def with_persona(member: dict) -> dict:
    """DB의 스터디원 정보에 역할 설명(persona)을 붙인다."""
    persona = PERSONAS.get(member.get("perspective"), PERSONAS["개념과 정의"])
    member["persona"] = {**persona, "level_guide": LEVEL_GUIDE.get(member.get("level"), LEVEL_GUIDE["중급"])}
    return member


# 모든 스터디원 프롬프트에 붙는 공통 규칙
PEER_RULES = (
    "당신은 사용자와 함께 공부하는 AI 스터디원들의 발언을 만듭니다. members의 각 동료는 name, level, persona"
    "(role, focus, style, level_guide)를 가집니다. 말하는 동료는 자기 persona의 focus와 style, level_guide를 지키세요. "
    "모든 발언은 study_goal(또는 goal)과 이번 주차 week의 title·scope 주제 안에서만 하고, 주제와 무관한 잡담이나 "
    "교안·대화에 없는 사실을 지어내지 마세요. 실제 친구처럼 짧고 자연스러운 한국어 존댓말을 쓰고, "
    "선생님이나 시험 문제 같은 말투, 매번 같은 칭찬, 이모지 남발을 피하세요. "
)


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
    study["members"] = [with_persona(dict(r)) for r in db.execute(
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
    session["members"] = [with_persona(dict(r)) for r in db.execute(
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
