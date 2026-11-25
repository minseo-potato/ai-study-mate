"""다음에 누가 무엇을 말할지 정한다. 장면 하나를 확률로 고르고(choose_turn), 말할 사람의 차례를 짠다(turn_steps)."""
import random
import re

MAX_QUIET = 3  # 사용자에게 묻지 않고 이어 갈 수 있는 사용자 차례 수
MAX_LINES = 4  # 사용자가 한 번 말한 뒤 친구들이 이어 말할 수 있는 최대 줄 수

# 장면: (보통 확률, 특정 친구를 불렀을 때, 사용자가 말하지 않았을 때, 사용자에게 묻는지)
TURNS = {
    "quick": (28, 44, 14, False),     # 한 명이 짧게
    "quick_ask": (16, 18, 22, True),  # 한 명이 받고 되묻기
    "two": (18, 12, 14, False),       # 한 명이 받고 다른 한 명이 보태기
    "share_ask": (14, 6, 24, True),   # 한 명이 받고 다른 한 명이 공부한 것과 이어 묻기
    "chat": (24, 20, 26, False),      # 친구끼리 묻고 답하기(가끔 사용자에게 넘김)
    "everyone": (0, 0, 0, False),     # 모두에게 물었을 때 한 명씩
}
EVERYONE = re.compile(r"(다들|너희|니들|얘들아|애들아|모두|각자|돌아가면서|한\s*명씩|셋\s*다|넷\s*다)")


FACT = re.compile(r"(몇\s*명|몇\s*주|몇\s*주차|총\s*몇|언제(야|지|까지|였|더라|예요)|며칠|주제가?\s*뭐|방\s*이름|누구\s*누구|이번\s*주\s*(뭐|범위)|다음\s*주(에|는)?\s*뭐)")


def names_in(text: str, members: list) -> tuple[list, list]:
    """사용자가 부른 친구와 말 속에 언급만 한 친구의 번호. '서윤아 도현이 말 맞아?'면 서윤을 부르고 도현을 언급한 것이다."""
    called, mentioned = [], []
    for m in members:
        name = re.escape(str(m["name"]).strip())
        if not name or not re.search(name, text):
            continue
        # 부르는 말(서윤아, 지호야, @서윤), 그 친구의 생각을 묻는 말(서윤이는, 서윤은, 서윤한테), 말 첫머리의 이름
        call = (rf"@{name}|{name}(?:아|야|이여|님|씨)(?![가-힣])|{name}이?(?:는|은|도)(?![가-힣])|{name}(?:이)?(?:한테|에게)(?![가-힣])"
                rf"|^\s*{name}(?=[\s,.!?~:]|$)")
        (called if re.search(call, text) else mentioned).append(m["member_no"])
    return called, mentioned


_NOT_NAMES = {"있잖", "맞잖", "그렇잖", "근데", "진짜", "그거", "이거", "저거", "뭐", "이게", "그게", "얘들", "애들", "친구들", "너희들", "자기", "여러분",
              "같", "좋", "많", "알", "괜찮", "싫", "몰", "나", "아니", "그래", "이건", "그건", "누구", "무엇", "언제", "어디", "교수님", "선생님", "선배"}


def absent_names(text: str, members: list, user_name: str = "") -> list[dict]:
    """사용자가 방에 없는 사람을 부른 것 같으면 그 이름과, 잘못 부른 것일 수 있는 친구 이름을 돌려준다."""
    names = [str(m["name"]).strip() for m in members]
    known = {*names, *(n + "이" for n in names), user_name, user_name + "이"}
    found = {}
    # 말 첫머리나 쉼표 뒤에서 부르는 말(도윤아, 민지야), @도윤
    for pattern in (r"(?:^|[,.!?~\n]\s*)([가-힣]{2,3}?)(?:아|야)(?=[\s,!?~]|$)", r"@([가-힣A-Za-z]{2,10})"):
        for name in re.findall(pattern, text):
            found[name] = True
    # 친구 이름과 한 글자만 다른 이름에 조사가 붙은 말(도윤이는, 도윤이가)
    for name in re.findall(r"(?<![가-힣])([가-힣]{2,3}?)(?:이는|이가|이도|이랑|이한테|이 |한테|은 |는 )", text):
        if any(len(name) == len(n) >= 2 and name[0] == n[0] and sum(a != b for a, b in zip(name, n)) == 1 for n in names):
            found[name] = True
    out = []
    for name in found:
        if name in known or name in _NOT_NAMES:
            continue
        near = [n for n in names if len(n) == len(name) and sum(a != b for a, b in zip(n, name)) == 1]
        similar = next(iter(sorted(near, key=lambda n: n[0] != name[0])), None)
        out.append({"name": name, "similar": similar})
    return out[:3]


# 방금 나온 말을 가리키는 짧은 되물음과, 이름 없이 '너'라고 부르는 말.
_BACK = re.compile(r"^(아니\s*)?(그게|그건|이게|이건|방금\s*(그|한)\S*|그\s*말은?|무슨|뭔|왜|어째서|진짜|정말|어떻게|예를\s*들면|예시|다시|더\s*(자세히|쉽게))[^.]{0,24}$|"
                   r"(무슨|뭔)\s*(말|뜻|소리|얘기)|뜻이야|못\s*알아|이해가?\s*안|다시\s*(말해|설명)")
_YOU = re.compile(r"(?<![가-힣])(넌|너는|너도|네가|니가|너가|너\s|네\s*말|니\s*말)")
_SCOLD = re.compile(r"(말한\s*적\s*(이|은)?\s*없|아니잖|틀렸|잘못\s*(말|알)|네가\s*한\s*말|니가\s*한\s*말|헛소리|엉뚱|왜\s*그렇게\s*말)")


def addressed_back(text: str, talk: list, members: list) -> int | None:
    """이름 없이 방금 말한 친구에게 하는 말이면 그 친구의 번호."""
    if EVERYONE.search(text) or FACT.search(text):
        return None
    last = next((m for m in reversed(talk) if m["role"] != "user_file"), None)
    if not last or not last["role"].startswith("assistant") or last["role"] == "assistant_plan":
        return None
    if last.get("member_no") not in {m["member_no"] for m in members}:
        return None
    short = len(text.strip()) <= 30
    return last["member_no"] if (short and _BACK.search(text.strip())) or _YOU.search(text) or _SCOLD.search(text) else None


def choose_turn(talk: list, text: str | None, members: list, no_questions: bool = False, presenting: bool = False, rng=random) -> dict:
    """장면을 고른다. talk는 이번 말을 뺀 대화, text는 사용자의 말(None이면 사용자가 말하지 않은 사이 이어 가기)."""
    said = text or ""
    called, mentioned = names_in(said, members)
    absent = absent_names(said, members) if said and not called else []
    back = addressed_back(said, talk, members) if said and not called and not absent else None
    if back:  # 방금 말한 친구에게 이어서 한 말이면 그 친구가 직접 받는다.
        called = [back]
        mentioned = [n for n in mentioned if n != back]
    # 한 명만 짧게 답할 때: 발표 중, 지적, 없는 사람, 일정·인원 질문
    single = presenting or bool(_SCOLD.search(said)) or (not called and (bool(absent) or bool(FACT.search(said))))
    count = len(members)
    if single:
        shape = "quick"
    elif text is None and no_questions:
        shape = "quick"
    elif count > 1 and not called and EVERYONE.search(said):
        shape = "everyone"
    else:
        weights = {k: float(v[2] if text is None else v[1] if called else v[0]) for k, v in TURNS.items()}
        asks = [i for i, m in enumerate(talk) if m["role"] == "assistant"]
        quiet = sum(m["role"] == "user" for m in talk[asks[-1] + 1:]) if asks else MAX_QUIET
        if text is None and not asks:
            weights = {k: v if k == "share_ask" else 0 for k, v in weights.items()}  # 첫 이야기
        if count < 2:
            weights["two"] = weights["chat"] = 0
        if mentioned:
            weights["chat"] *= 2
        for k, v in TURNS.items():
            if no_questions and (v[3] or k == "chat"):
                weights[k] = 0
            elif quiet >= MAX_QUIET - 1 and not called and not no_questions and not v[3]:
                weights[k] = 0  # 묻지 않는 차례가 이어졌으면 사용자에게 돌아온다.
            elif quiet == 0 and v[3] and text is not None:
                weights[k] *= 0.75
        recent = next((i for i, m in enumerate(reversed(talk)) if m["role"] == "user"), len(talk))
        if recent >= 3:  # 직전에 여럿이 말했으면 짧게 간다.
            weights["two"] *= 0.4
            weights["chat"] *= 0.4
        if not any(weights.values()):
            weights["quick"] = 1
        shape = rng.choices(list(weights), list(weights.values()))[0]
    return {"shape": shape, "asks": TURNS[shape][3], "called": called, "mentioned": mentioned, "start": text is None,
            "similar": next((x["similar"] for x in absent if x["similar"]), None)}


# 말하는 종류마다 그 친구에게 주는 할 일.
TASKS = {
    "react": "상대의 방금 말을 받아 준다. 물었으면 바로 답하고, 생각을 말했으면 내 생각이나 다르게 보는 점 하나를 말한다. 되묻지 않는다.",
    "react_ask": "상대의 방금 말이나 지금 이야기를 짧게 받고, 궁금한 것 하나를 상대에게 묻는다.",
    "each": "모두에게 물었다. 다른 친구와 다른 내 생각을 짧게 답한다. 되묻지 않는다.",
    "add": "바로 앞 말에 아직 안 나온 생각이나 다른 의견 하나를 보탠다. 누구 말에 대한 것인지 드러낸다. 묻지 않는다.",
    "share": "이번 주 범위에서 내가 공부한 것 하나를 지금 이야기와 이어 나눈다. 묻지 않는다.",
    "share_ask": "이번 주 범위에서 내가 공부한 것 하나를 말하고, 상대는 어떻게 봤는지 가볍게 묻는다.",
    "ask_peer": "방금 나온 말을 짧게 받고, '말을 걸 친구'의 이름을 불러 그 친구가 앞에서 한 말 중 궁금한 것 하나를 묻는다.",
    "answer_peer": "'말을 걸 친구'가 나를 불러 물었다. '나에게 물은 말'에서 나에게 물은 것에만 바로 답한다. 되묻지 않는다.",
}
ASKING = {"react_ask", "share_ask"}


def step(kind: str, member_no: int, to: int | None = None) -> dict:
    return {"kind": kind, "member_no": member_no, "to": to}


# 사용자의 말에 어떤 역할이 나서면 어울리는지.
ROLE_CUES = {
    "개념과 정의": r"(뜻|정의|개념|용어|차이|뭐야|뭔데|무슨\s*말|헷갈|구분|이란|란\s*게|정리)",
    "예시와 적용": r"(예시|예를|사례|비유|어디에\s*(써|쓰)|언제\s*(써|쓰)|실제|실무|써\s*먹|활용|적용|쉽게|상황)",
    "앞 주차와의 연결": r"(지난|앞에서|앞\s*주|저번|이어|연결|관계|순서|흐름|과정|다음에|전체|먼저)",
    "다른 해석": r"(왜|이유|근거|진짜|정말|반대|단점|한계|문제|예외|만약|아닌\s*것|틀린|맞아\?|맞나)",
}
LEVEL_RANK = {"기초": 0, "중급": 1, "심화": 2}


def fit(text: str, members: list) -> dict:
    """사용자의 말과 역할이 어울리는 정도. 깊은 질문이면 잘 아는 친구에게 점수를 더 준다."""
    out = {}
    deep = bool(re.search(r"(왜|원리|내부|한계|단점|비교|차이|예외|어떻게\s*(동작|작동|돌아))", text))
    for m in members:
        cue = ROLE_CUES.get(m.get("perspective"), "")
        score = min(2, len(re.findall(cue, text))) * 2.0 if cue else 0.0
        if deep and score:
            score += LEVEL_RANK.get(m.get("level"), 1) * 0.5
        out[m["member_no"]] = score
    return out


def speakers(talk: list, members: list, first: list, rng=random, text: str = "") -> list:
    """말할 순서. 먼저 말해야 할 친구를 앞에 두고, 나머지는 말의 내용에 어울리는 역할과 오래 조용했던 친구부터 둔다."""
    last = {m["member_no"]: i for i, m in enumerate(talk) if m["role"].startswith("assistant")}
    rest = [m["member_no"] for m in members if m["member_no"] not in first]
    match = fit(text, members)
    recent = sorted(rest, key=lambda n: last.get(n, -1))
    rest.sort(key=lambda n: recent.index(n) + rng.random() * 1.5 - match[n])
    return list(dict.fromkeys(first)) + rest


def turn_steps(turn: dict, talk: list, members: list, asker: int | None = None, rng=random, text: str = "") -> list[dict]:
    """장면에 맞춰 누가 무엇을 할지 차례를 짠다. asker는 직전에 물었던(또는 먼저 말할) 친구다."""
    called, shape = turn["called"], turn["shape"]
    match = fit(text, members)
    best = max(match.values(), default=0)
    first = list(called)
    if not first and turn.get("similar"):  # 잘못 불린 것 같은 친구가 나서서 확인한다.
        first = [m["member_no"] for m in members if m["name"] == turn["similar"]]
    elif not first and best >= 2 and rng.random() < 0.8:  # 내용에 맞는 역할이 대개 먼저 나선다.
        first = [rng.choice([n for n, v in match.items() if v == best])]
    elif not first and asker and (turn.get("start") or rng.random() < 0.6):
        first = [asker]
    order = speakers(talk, members, first, rng, text)
    target = next((n for n in turn["mentioned"] if n != order[0]), None)
    if target:  # 말 속에 나온 친구에게 이야기가 가게 한다.
        order = [order[0], target] + [n for n in order[1:] if n != target]
    a, b = order[0], order[1] if len(order) > 1 else None
    opening = "share" if turn.get("start") else "react"
    if shape == "everyone":
        return [step("each", n) for n in order[:4]]
    if len(called) > 1:
        return [step("react" if i == 0 else "each", n) for i, n in enumerate(called[:4])]
    if shape == "quick_ask":
        return [step("react_ask", a)]
    if shape == "share_ask":
        return [step("share_ask", a)] if turn.get("start") or b is None else [step("react", a), step("share_ask", b)]
    if shape == "quick" or b is None:
        return [step(opening, a)]
    if shape == "two":
        return [step(opening, a), step("add", b, a)]
    # 친구끼리 물을 때는 덜 아는 쪽이 묻고 더 아는 쪽이 답하는 일이 많다.
    rank = {m["member_no"]: LEVEL_RANK.get(m.get("level"), 1) for m in members}
    if not called and not turn["mentioned"] and best < 2 and rank[a] > rank[b] and rng.random() < 0.7:
        a, b = b, a
    steps = [step("ask_peer", a, b), step("answer_peer", b, a)]
    if rng.random() < 0.35:  # 친구끼리 주고받은 뒤 사용자에게 넘긴다.
        steps.append(step("react_ask", next((n for n in order if n not in (a, b)), a)))
    return steps


def follow(steps: list, kind: str, text: str, speaker: int, members: list, spoken: int) -> list:
    """방금 한 말에서 다른 친구를 불러 물었으면, 불린 친구가 바로 다음에 답하게 한다."""
    if kind in ASKING or not re.search(r"[?？]", text):
        return steps
    others = [m for m in members if m["member_no"] != speaker]
    called, mentioned = names_in(text, others)
    target = next(iter(called or mentioned), None)
    planned = steps[0] if steps and steps[0]["kind"] == "answer_peer" else None
    if planned:
        return [{**planned, "member_no": target, "to": speaker}] + steps[1:] if target else steps
    return [step("answer_peer", target, speaker)] + steps if target and spoken < MAX_LINES else steps
