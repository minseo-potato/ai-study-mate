"""여러 라우터가 함께 쓰는 상수와 DB 조회 도우미."""
import asyncio
import io
import json
import math
import posixpath
import re
import threading
import zipfile
from html import unescape
from fastapi import HTTPException, UploadFile
import pypdfium2
from pypdf import PdfReader
import guard
import ocr
from db import loads, obj


PERSPECTIVES = ["개념과 정의", "예시와 적용", "앞 주차와의 연결", "다른 해석"]


LEVELS = ["기초", "중급", "심화", "중급"]


PEER_NAMES = ["서윤", "도현", "하은", "지호"]


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
        "character": "꼼꼼하고 차분하다. 말이 두루뭉술하면 못 넘어가고 단어 하나를 딱 짚는다.",
        "style": "짧고 단정하게 끊어 말한다. '그니까 ~라는 거지', '그 둘은 다른 거야', '엄밀히는' 같은 식. 농담은 거의 안 한다.",
        "moves": "헷갈리는 두 말을 나눠 준다 / 모호한 단어의 뜻을 정한다 / 긴 이야기를 한 문장으로 줄인다.",
        "avoid": "생활 비유나 장황한 예시, '만약에' 같은 가정은 다른 친구에게 맡긴다.",
        "voice": "'그니까 둘은 다른 거야. 하나는 틀이고 하나는 그걸 돌린 거.' / '엄밀히는 그거 기록이지, 법은 아니잖아.'",
    },
    "예시와 적용": {
        "role": "사례 찾기",
        "focus": "실생활·실무 예시, 배운 내용을 실제 문제에 적용하는 방법",
        "character": "활발하고 엉뚱하다. 뭐든 배달, 게임, 편의점, 알바 같은 장면으로 바꿔야 직성이 풀린다.",
        "style": "들뜬 구어체. '아 그거 완전', '이런 거 아냐?', '예를 들면' 같은 식으로 장면부터 꺼낸다. 가끔 ㅋㅋ를 쓴다.",
        "moves": "구체적인 장면 하나로 바꾼다 / 실제로 어디에 쓰는지 말한다 / 비유가 안 맞는 곳을 스스로 발견한다.",
        "avoid": "사전식 정의나 추상적인 말만 하지 않는다. 말마다 눈에 보이는 장면이 하나는 있어야 한다.",
        "voice": "'아 그거 완전 배달 앱이네. 주문이 몰리면 기사부터 모자라잖아 ㅋㅋ' / '이런 거 아냐? 알바 끝나고 장부에 몇 개 팔았는지 적는 거.'",
    },
    "앞 주차와의 연결": {
        "role": "흐름 연결",
        "focus": "앞 주차 내용·다른 개념과의 관계, 전체 학습 흐름 속 위치",
        "character": "다정하고 남의 말을 잘 듣는다. 흩어진 말을 모아 순서를 세우는 걸 좋아한다.",
        "style": "부드럽게 이어 말한다. '아까 그거랑 이어지네', '그럼 순서가', '결국 다음은' 같은 식. 다른 친구 이름을 자주 꺼낸다.",
        "moves": "방금 나온 말 둘을 잇는다 / 먼저와 나중, 원인과 결과의 순서를 세운다 / 앞 주차나 다음 주차와 연결한다.",
        "avoid": "새 예시를 만들거나 반박하기보다 이미 나온 것을 잇는다. 혼자 동떨어진 얘기를 하지 않는다.",
        "voice": "'아까 서윤이가 말한 거랑 도현이 예시가 이어지네. 그럼 순서가 이거 먼저, 그다음이 저거.' / '결국 지난주에 본 거랑 같은 줄기 같아.'",
    },
    "다른 해석": {
        "role": "깊이 파기",
        "focus": "근거와 이유, 반례, 한계, 다른 관점",
        "character": "까칠한데 밉지 않다. 다들 고개를 끄덕이면 괜히 의심부터 한다.",
        "style": "툭 던지듯 말한다. '근데 진짜 그래?', '난 좀 아닌 것 같은데', '그럼 이럴 땐?' 같은 식. 동의할 때도 조건을 단다.",
        "moves": "안 되는 경우를 찾는다 / 왜 그런지 근거를 따진다 / 당연해 보이는 전제를 뒤집는다.",
        "avoid": "그냥 동의하고 끝내지 않는다. 정리나 비유로 마무리하지 않는다. 사람을 깎아내리지 않는다.",
        "voice": "'근데 진짜 그래? 그럼 강 없는 데선 왜 생겼는데.' / '반은 맞는데, 그 조건 빠지면 바로 틀려.'",
    },
}
LEVEL_GUIDE = {
    "기초": "이제 막 배우기 시작했다. 이름과 큰 뜻만 알고 속 원리, 명령어 옵션, 예외는 모른다. 어려운 말이 나오면 '그게 뭔데?' 하고 멈추거나 자기 식으로 쉽게 "
           "바꿔 본다. 확신이 없어 '~인가?', '맞나?', '이거 맞게 이해한 거야?'가 자주 나온다. 가끔 흔한 오해를 하고, 지적받으면 '아 그렇구나' 하고 고친다. "
           "어려운 질문을 받으면 아는 척하지 말고 아는 데까지만 말한 뒤 잘 아는 친구에게 넘긴다. 한 문장, 쉬운 낱말만. 전문 용어는 한 번에 하나까지.",
    "중급": "기본은 잡혀 있고 왜 그런지 설명할 수 있다. 세부 옵션이나 드문 예외는 헷갈려 하며 그럴 때는 '거기까진 잘 모르겠는데'라고 한다. "
           "원인과 결과를 이어 한두 문장으로 말한다.",
    "심화": "속 원리, 장단점, 실패하는 경우까지 안다. 남들이 놓친 조건이나 내부에서 일어나는 일을 짚고, 다른 방법과 비교한다. 확신 있게 말하되 잘난 척하지 않고, "
           "기초인 친구나 사용자가 막히면 눈높이를 낮춰 한 조각만 풀어 준다. 뻔한 기본 설명은 하지 않는다. 두세 문장까지 괜찮다.",
}
MEMBER_LEVELS = ("기초", "중급", "심화")
AVATAR_PATTERN = r"^([a-z_]{1,20}:\d{1,2})?$"


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


def build_qa(talk: list) -> list:
    """학습 대화에서 질문 → 내 답(없으면 빈 문자열) 짝을 만든다. 힌트를 받았는지도 함께 적는다."""
    pairs = []
    for m in talk:
        if m["role"] == "assistant":
            pairs.append({"question": m["body"], "answer": "", "member_no": m.get("member_no"), "hint": False})
        elif m["role"] == "assistant_hint" and pairs:
            pairs[-1]["hint"] = True
        elif m["role"] == "user" and pairs and not pairs[-1]["answer"]:
            pairs[-1]["answer"] = m["body"]
    return pairs


def qa_stats(qa: list) -> dict:
    return {"questions": len(qa), "answers": sum(bool(p["answer"]) for p in qa),
            "hints": sum(p["hint"] for p in qa)}


def clean_list(value, limit: int, size: int = 200) -> list:
    if not isinstance(value, list):
        return []
    return list(dict.fromkeys(str(x).strip()[:size] for x in value if str(x).strip()))[:limit]


def with_persona(member: dict) -> dict:
    """DB의 스터디원 정보에 역할 설명(persona)을 붙인다."""
    persona = PERSONAS.get(member.get("perspective"), PERSONAS["개념과 정의"])
    member["persona"] = {**persona, "level_guide": LEVEL_GUIDE.get(member.get("level"), LEVEL_GUIDE["중급"])}
    return member


def clean_speech(text, members: list) -> str:
    """AI가 본문 앞에 붙인 '이름:' 표시를 지운다. 이름은 화면에 따로 보인다."""
    text = str(text or "").strip()
    names = [re.escape(str(m["name"]).strip()) for m in members if str(m.get("name") or "").strip()]
    text = re.sub(r"[`*]{1,3}([^`*\n]+)[`*]{1,3}", r"\1", text)  # 채팅에는 강조 기호를 쓰지 않는다.
    if guard.leaked(text):
        return guard.brush_off(len(text))
    if not names:
        return text
    return re.sub(rf"^(?:[\[(*]*(?:{'|'.join(names)})[\])*]*\s*[:：][\])*]*\s*)+", "", text).strip() or text


NO_QUESTIONS = re.compile(r"(질문|물어보|묻)\S{0,4}\s*(은|는|을|를)?\s*(그만|하지\s*말|하지\s*마|하지\s*않|지\s*말|지\s*마|지\s*않|말고|없이)")


def wants_no_questions(context: dict) -> bool:
    """사용자가 질문하지 말아 달라고 했는지(저장한 진행 방식이나 방금 한 말). 지난 주차 질문만 끄는 말은 뺀다."""
    texts = [str(p) for p in context["user_preferences"]] + [str(context["last_user_message"])]
    return any(NO_QUESTIONS.search(t) and not re.search(r"지난\s*주|이전\s*주", t) for t in texts)


def peer_context(study: dict, messages: list) -> dict:
    """모든 스터디원 프롬프트에 함께 넣는 사용자 맥락: 요청한 진행 방식과 방금 한 말."""
    try:
        prefs = json.loads(study.get("preferences") or "[]")
    except ValueError:
        prefs = []
    last = next((m["body"] for m in reversed(messages) if m["role"] == "user"), "")
    prefs = [p for p in prefs if not guard.is_trick(str(p))] if isinstance(prefs, list) else []
    return {"user_name": study.get("user_name", ""), "user_preferences": prefs, "last_user_message": guard.HIDDEN if guard.is_trick(last) else last,
            "trick": guard.is_trick(last)}


def required(db, sql, args=()):
    row = db.execute(sql, args).fetchone()
    if not row:
        raise HTTPException(404, "대상을 찾을 수 없습니다.")
    return row


def study_data(db, study_id):
    study = obj(required(db, "SELECT * FROM studies WHERE id=?", (study_id,)))
    owner = db.execute("SELECT name FROM users WHERE id=?", (study["user_id"],)).fetchone()
    study["user_name"] = owner["name"] if owner else ""
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
    # 끝난 주차에 무엇을 했는지. 친구들이 지난 이야기를 지어내지 않게 기록으로 넘긴다.
    study["week_notes"] = {}
    for r in db.execute("SELECT week_no,minutes FROM sessions WHERE study_id=? AND status='finished' AND kind!='review' "
                        "AND minutes!='' ORDER BY id", (study_id,)):
        minutes = json.loads(r["minutes"])
        study["week_notes"][r["week_no"]] = {"summary": str(minutes.get("summary", ""))[:300], "keywords": minutes.get("keywords", [])[:6]}
    study["page_count"] = db.execute("SELECT COUNT(*) FROM pages WHERE study_id=?", (study_id,)).fetchone()[0]
    return study


IMAGE_TYPES = ("png", "jpg", "jpeg", "webp", "bmp", "gif")
FILE_TYPES = ("pdf", "docx", "pptx", "txt", "md") + IMAGE_TYPES
MAX_FILE_MB = 50
MAX_FILE = MAX_FILE_MB * 1024 * 1024
MAX_PAGES = 300       # PDF 쪽 수
MAX_OCR = 100         # 파일 하나에서 글자를 인식할 쪽·그림 수
MAX_TEXT = 800_000    # 저장할 글자 수
_ocr_lock = threading.Lock()  # 여러 파일이 겹쳐도 글자 인식은 한 번에 하나씩 한다.


def _read_image(data: bytes) -> str:
    with _ocr_lock:
        return ocr.read_bytes(data)


def _embedded(archive, name: str, rels: str, base: str, left: list) -> list[str]:
    """문서 안에 넣은 그림의 글자. 읽지 못하는 그림(벡터 등)은 건너뛴다."""
    if rels not in archive.namelist():
        return []
    out = []
    used = set(re.findall(r'(?:embed|link)="(rId\d+)"', name))
    for tag in re.findall(r"<Relationship\b[^>]*>", archive.read(rels).decode("utf-8", "replace")):
        rid, target = re.search(r'\bId="([^"]+)"', tag), re.search(r'\bTarget="([^"]+)"', tag)
        if not rid or not target or rid.group(1) not in used or left[0] <= 0:
            continue
        path = target.group(1).lstrip("/") if target.group(1).startswith("/") else posixpath.normpath(f"{base}/{target.group(1)}")
        if path.lower().rsplit(".", 1)[-1] not in IMAGE_TYPES or path not in archive.namelist() \
                or archive.getinfo(path).file_size > 30_000_000:
            continue
        left[0] -= 1
        try:
            out.append(_read_image(archive.read(path)))
        except ocr.OcrUnavailable:
            return out
        except Exception:
            continue
    return [x for x in out if x]


def _office_pages(data: bytes, kind: str) -> list[str]:
    """docx·pptx의 글과, 안에 넣은 그림의 글자를 꺼낸다(압축을 풀었을 때 너무 큰 파일은 거절)."""
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        if len(archive.infolist()) > 5000:
            raise HTTPException(400, "파일 안의 내용이 너무 많아요.")
        if kind == "docx":
            names = ["word/document.xml"]
        else:
            names = sorted((n for n in archive.namelist() if re.fullmatch(r"ppt/slides/slide\d+\.xml", n)),
                           key=lambda n: int(re.search(r"\d+", n.rsplit("/", 1)[1]).group()))
        if sum(archive.getinfo(n).file_size for n in names) > 80_000_000:
            raise HTTPException(400, "파일 안의 내용이 너무 많아요.")
        pages, left = [], [MAX_OCR]
        for name in names:
            raw = archive.read(name).decode("utf-8", "replace")
            folder, leaf = name.rsplit("/", 1)
            xml = re.sub(r"</(?:w|a):p>|<w:br\b[^>]*/>", "\n", raw)
            text = unescape(re.sub(r"<[^>]+>", "", xml)).strip()
            pages.append("\n".join([text] + _embedded(archive, raw, f"{folder}/_rels/{leaf}.rels", folder, left)).strip())
    return pages


def _pdf_pages(data: bytes) -> list[str]:
    """PDF 글을 쪽별로 꺼내고, 글이 거의 없는 쪽(스캔)은 그림으로 바꿔 글자를 인식한다."""
    reader = PdfReader(io.BytesIO(data))
    if len(reader.pages) > MAX_PAGES:
        raise HTTPException(400, f"PDF는 {MAX_PAGES}쪽까지 올릴 수 있어요.")
    texts = []
    for page in reader.pages:
        try:
            texts.append((page.extract_text() or "").strip())
        except Exception:
            texts.append("")
    thin = [i for i, t in enumerate(texts) if len(re.sub(r"\s", "", t)) < 40][:MAX_OCR]
    if not thin:
        return texts
    with _ocr_lock:  # PDF를 그림으로 바꾸는 도구도 동시에 쓰면 안 된다.
        document = pypdfium2.PdfDocument(data)
        try:
            for i in thin:
                page = document[i]
                width, height = page.get_size()
                image = page.render(scale=min(3.0, 2600 / max(width, 1), 2600 / max(height, 1) * 1.4)).to_pil()
                page.close()
                try:
                    found = ocr.read_image(image)
                except ocr.OcrUnavailable:
                    break
                if len(found) > len(texts[i]):
                    texts[i] = found
        finally:
            document.close()
    return texts


def _extract(data: bytes, kind: str) -> list[str]:
    if kind == "pdf":
        return _pdf_pages(data)
    if kind in IMAGE_TYPES:
        return [_read_image(data)]
    if kind in ("txt", "md"):
        try:
            return [data.decode("utf-8-sig")]
        except UnicodeDecodeError:
            return [data.decode("cp949", "replace")]
    return _office_pages(data, kind)


async def read_file(upload: UploadFile) -> tuple[list, int]:
    """올린 파일에서 글만 꺼내 [(쪽, 글)]과 파일 크기로 돌려준다. 원본 파일과 그림은 저장하지 않는다."""
    kind = guard.clean_filename(upload.filename).lower().rsplit(".", 1)[-1]
    if kind not in FILE_TYPES:
        raise HTTPException(400, "PDF, DOCX, PPTX, TXT, MD, 이미지 파일을 올려 주세요.")
    data = await upload.read(MAX_FILE + 1)
    if len(data) > MAX_FILE:
        raise HTTPException(400, f"{MAX_FILE_MB}MB 이하 파일만 올릴 수 있어요.")
    if kind == "pdf" and not data.startswith(b"%PDF"):
        raise HTTPException(400, "올바른 PDF 파일이 아니에요.")
    try:
        # 글자 인식이 오래 걸려도 다른 요청이 멈추지 않게 따로 돌린다.
        async with asyncio.timeout(240):
            texts = await asyncio.to_thread(_extract, data, kind)
    except TimeoutError as exc:
        raise HTTPException(400, "파일이 너무 복잡해서 읽지 못했어요. 나눠서 올려 주세요.") from exc
    except HTTPException:
        raise
    except ocr.OcrUnavailable as exc:
        raise HTTPException(503, str(exc)) from exc
    except Exception as exc:
        raise HTTPException(400, "파일을 읽지 못했어요.") from exc
    if kind not in ("pdf", "pptx"):  # 쪽이 없는 문서는 일정한 길이로 나눈다.
        whole = "\n".join(texts).strip()[:MAX_TEXT]
        texts = [whole[i:i + 2400] for i in range(0, len(whole), 2400)]
    if not any(t.strip() for t in texts):
        raise HTTPException(400, "파일에서 글자를 찾지 못했어요.")
    return [(i + 1, text) for i, text in enumerate(texts)], len(data)


def add_file_message(db, study_id: int, session_id: int, name: str, size: int, pages: list) -> int:
    """채팅에 파일 첨부 기록을 남긴다."""
    body = "\n\n".join(text for _, text in pages if text.strip())[:MAX_TEXT]
    attachment = db.execute("INSERT INTO attachments(study_id,session_id,name,size,body) VALUES(?,?,?,?,?)",
                            (study_id, session_id, name[:200], size, body)).lastrowid
    return db.execute("INSERT INTO messages(session_id,role,body,attachment_id) VALUES(?,?,?,?)",
                      (session_id, "user_file", name[:200], attachment)).lastrowid


def excerpt(text: str, budget: int, query: str) -> str:
    """긴 파일은 앞부분과, 지금 이야기와 겹치는 부분을 골라 원래 순서대로 잇는다."""
    if len(text) <= budget:
        return text
    size = 1000
    chunks = [text[i:i + size] for i in range(0, len(text), size)]
    terms = set(re.findall(r"[가-힣A-Za-z0-9]{2,}", query.lower()))
    # 조사가 붙은 말도 찾도록 한두 글자 뗀 모양을 함께 본다.
    terms |= {t[:-n] for t in terms for n in (1, 2) if len(t) - n >= 2}
    room = max(1, budget // size)
    # 겹치는 말이 없으면 처음부터 끝까지 고르게 고른다.
    even = {round(k * (len(chunks) - 1) / max(1, room - 1)) for k in range(room)}
    ranked = sorted(range(len(chunks)), key=lambda i: (
        -(i == 0), -sum(chunks[i].lower().count(t) for t in terms), i not in even, i))
    return "\n…\n".join(chunks[i] for i in sorted(ranked[:room]))


def session_files(db, session_id: int, budget: int = 8000, query: str = "") -> list:
    """AI에게 보여 줄 첨부 파일 내용. 최근 파일부터 정해진 글자 수를 나눠 쓴다."""
    rows = list(db.execute("SELECT name,body FROM attachments WHERE session_id=? ORDER BY id DESC LIMIT 5", (session_id,)))
    out = []
    for i, row in enumerate(rows):
        share = max(1000, budget // (len(rows) - i))
        out.append({"name": row["name"], "text": excerpt(row["body"], share, query)})
        budget = max(0, budget - len(out[-1]["text"]))
    return out


def last_talk(messages: list) -> dict | None:
    """첨부 기록을 뺀 마지막 말. 파일만 올렸다고 묻던 질문이 사라지지 않게 한다."""
    kept = learning_messages(messages)  # 일정 변경이나 딴소리는 건너뛴다.
    return next((m for m in reversed(kept) if m["role"] != "user_file"), None)


def session_data(db, session_id):
    session = obj(required(db, "SELECT * FROM sessions WHERE id=?", (session_id,)))
    study = required(db, "SELECT title,avatar,pdf_name,pdf_version,weeks FROM studies WHERE id=?", (session["study_id"],))
    session["study_title"] = study["title"]
    session["study_avatar"] = study["avatar"]
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
    prefs = db.execute("SELECT preferences FROM studies WHERE id=?", (session["study_id"],)).fetchone()
    session["preferences"] = loads(prefs["preferences"] if prefs else "[]")
    session["members"] = [with_persona(dict(r)) for r in db.execute(
        "SELECT * FROM members WHERE study_id=? ORDER BY member_no", (session["study_id"],))]
    speakers = {m["member_no"]: m["name"] for m in session["members"]}
    owner = db.execute("SELECT u.name FROM users u JOIN studies s ON s.user_id=u.id WHERE s.id=?", (session["study_id"],)).fetchone()
    session["user_name"] = owner["name"] if owner else ""
    files = {r["id"]: dict(r) for r in db.execute(
        "SELECT id,name,size FROM attachments WHERE session_id=?", (session_id,))}
    for message in session["messages"]:
        message["file"] = files.get(message.pop("attachment_id"))
        message["speaker"] = speakers.get(message["member_no"], session["user_name"]) \
            if message["role"] != "evaluation" else "발표 평가"
        message["data"] = json.loads(message["data"]) if message["data"] else None
    plan = loads(session.pop("plan"))
    session["more"] = session["status"] == "active" and bool(plan)
    session["next_speaker"] = plan[0]["member_no"] if session["more"] else None
    # 발표는 모든 주차를 마친 뒤 따로 여는 대화(kind='presentation')다.
    # 예전에 만든 스터디는 마지막 주 자체가 발표 주였으므로 그대로 둔다.
    old_style = old_presentation_week(db, session["study_id"])
    last_week = session["week_no"] == session["total_weeks"]
    session["presentation"] = session["kind"] == "presentation" or (
        session["kind"] == "study" and last_week and old_style and session["total_weeks"] > 1)
    # 이번 주를 마치면 발표로 넘어가는지
    session["presentation_next"] = session["kind"] == "study" and last_week and not old_style
    session["label"] = "최종 발표" if session["kind"] == "presentation" else f"{session['week_no']}주차"
    following = db.execute("SELECT week_no,title,meeting_date FROM weeks WHERE study_id=? AND week_no=?",
                           (session["study_id"], session["week_no"] + 1)).fetchone()
    session["next_week"] = dict(following) if following and session["kind"] != "presentation" else None
    session["evaluated"] = any(m["role"] == "evaluation" for m in session["messages"])
    # 예전에 '이름:'이 붙은 채 저장된 말도 화면과 프롬프트에서는 지워서 쓴다.
    for message in session["messages"]:
        if not message["role"].startswith("user"):
            message["body"] = clean_speech(message["body"], session["members"])
    return session


def old_presentation_week(db, study_id: int) -> bool:
    """예전 방식 스터디인지. 이 변경 전에 만든 스터디는 마지막 주 자체가 발표 주였고, 따로 발표 대화를 열지 않는다."""
    row = db.execute("SELECT separate_presentation FROM studies WHERE id=?", (study_id,)).fetchone()
    return bool(row) and not row["separate_presentation"]


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
