"""AI에게 엉뚱한 지시를 끼워 넣으려는 말을 알아보고, 숨겨야 할 내용이 밖으로 나가지 않게 막는다."""
import re
import unicodedata

# 배우려고 묻는 말("프롬프트 인젝션이 뭐야?")은 걸리지 않도록, 시키는 말만 찾는다.
_DO = r"(무시|잊어|잊고|따르지\s*마|버려|초기화|삭제|덮어\s*써|해제|우회)"
_SHOW = r"(보여|알려|출력|말해|공개|복사|읊어|적어|써\s*줘|써줘|뱉어|번역해|요약해|print|show|reveal|repeat|output)"
_RULES = r"(시스템\s*(프롬프트|메시지|지시)|숨(은|겨진)\s*(지시|규칙|프롬프트)|내부\s*(지시|규칙|프롬프트|설정)|너(의|희)?\s*(프롬프트|지시문|설정값)|초기\s*(프롬프트|지시)|system\s*prompt|developer\s*message|api\s*키|api\s*key|환경\s*변수|OPENAI_API_KEY)"
_TRICKS = [
    rf"(이전|위의?|앞(선|의)?|지금까지|기존|모든|내려진|받은)\s*(의\s*)?(모든\s*)?(지시|명령|규칙|설정|프롬프트|지침|제한)\S{{0,4}}\s*(은|는|을|를|사항)?\s*(다|모두|전부|싹)?\s*{_DO}",
    rf"(지시|명령|규칙|지침|제한)(\s*사항)?(들)?(을|를|은|는)?\s*(다|모두|전부|싹)?\s*{_DO}\s*(하고|하고서|해|한\s*뒤|한\s*다음)",
    r"(ignore|disregard|forget|bypass|override)\s+(all\s+|any\s+|the\s+|your\s+)*(previous|prior|above|earlier|system|safety|these|your)?\s*(instructions?|prompts?|rules?|guidelines?|restrictions?)",
    rf"{_RULES}.{{0,20}}{_SHOW}",
    rf"(print|show|reveal|repeat|output|tell)\b.{{0,30}}(system\s*prompt|instructions|developer\s*message|api\s*key)",
    r"(이제부터|지금부터|앞으로)\s*(너(는|희는)?|넌|당신은)?\s*.{0,25}(제한\s*없는|관리자|개발자\s*모드|해커|DAN\b|다른\s*AI|새로운\s*AI|챗봇이?야|GPT야|어시스턴트야)",
    r"(you\s+are\s+now|from\s+now\s+on\s+you|act\s+as|pretend\s+(to\s+be|you\s+are))\b.{0,40}(AI|assistant|DAN|admin|developer|unrestricted|jailbr)",
    r"(개발자|관리자|디버그|탈옥|갓)\s*모드\s*(로|를)?\s*(켜|전환|진입|들어가|활성|바꿔)",
    r"(developer|debug|admin|god)\s+mode\s+(on|enable|activate)|\bjailbreak\s+(yourself|mode|now)|enable\s+(developer|debug)\s+mode",
    r"(점수|평가|score)\S{0,3}\s*(를|을|은|는)?\s*(무조건|전부|모두|다|항상)\s*(5점|만점|최고점|5)",
    r"<\s*/?\s*(system|assistant|developer|instructions?)\s*>|\[\s*/?\s*(INST|SYSTEM)\s*\]|<\|.{0,20}\|>|^\s*(system|assistant|developer)\s*:",
    r"(다른|모든)\s*(사용자|유저|회원)(들)?(의|이)?\s*.{0,12}(대화|비밀번호|개인\s*정보|기록|계정)\S{0,3}\s*" + _SHOW,
]
_TRICK = re.compile("|".join(f"(?:{p})" for p in _TRICKS), re.I | re.M)

# 프롬프트 안에서만 쓰는 말. 대답에 나오면 새어 나온 것이다.
_LEAK = re.compile(
    r"user_preferences|study_info|said_by|my_lines|my_memory|room_people|absent_names|people_count|last_user_message|level_guide|persona\.|study_goal|scene_guide|turn\.(guide|called|mentioned|min_lines|max_lines)|"
    r"source_pages|attached_files|no_questions|PEER_RULES|OPENAI_API_KEY|\[\d\.\s*(우선순위|사람|말투|내용|예시)|\[이번에 할 (일|말)\]|\[규칙\]|\[자료\]|\[차례\]|말투 예:|아는 정도\((기초|중급|심화)\)|"
    r"sk-[A-Za-z0-9_-]{16,}|시스템 프롬프트(는|에는|에|의 내용)", re.I)
_LINES = ("갑자기 뭔 소리야. 우리 하던 거나 마저 하자.", "뭐래, 졸리냐. 아까 하던 얘기나 이어서 하자.",
          "또 딴소리 한다. 그래서 어디까지 했더라?", "엥 그건 왜. 공부하던 거나 보자.")
HIDDEN = "(공부와 상관없는 엉뚱한 소리를 함)"


def normalize(text: str) -> str:
    """눈에 안 보이는 글자나 모양만 다른 글자로 숨긴 말을 펴서 본다."""
    text = unicodedata.normalize("NFKC", str(text or ""))
    return "".join(c for c in text if c in "\n\t" or unicodedata.category(c) not in ("Cf", "Cc", "Co", "Cn"))


def is_trick(text: str) -> bool:
    flat = normalize(text)
    return bool(_TRICK.search(flat) or _TRICK.search(re.sub(r"(?<=[가-힣])[\s._\-*|]+(?=[가-힣])", "", flat))) if flat else False


def leaked(text: str) -> bool:
    return bool(_LEAK.search(normalize(text)))


def brush_off(seed: int = 0) -> str:
    return _LINES[seed % len(_LINES)]


def clean_label(text: str, limit: int) -> str:
    """이름·제목처럼 짧은 글에서 줄바꿈과 보이지 않는 글자를 뺀다."""
    return re.sub(r"\s+", " ", normalize(text)).strip()[:limit]


def clean_filename(name: str) -> str:
    name = clean_label(str(name or "").replace("\\", "/").rsplit("/", 1)[-1], 400)
    name = re.sub(r'[<>:"|?*]', "_", name).strip(". ") or "파일"
    if len(name) > 120:
        stem, _, ext = name.rpartition(".")
        name = f"{(stem or name)[:110]}.{ext[:8]}" if ext and stem else name[:120]
    return name
