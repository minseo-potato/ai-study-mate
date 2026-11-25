"""스터디 대화의 다음 장면을 확률로 고른다. 실제 스터디처럼 말하기와 묻기를 섞되, 친구들끼리만 떠들지 않게 한다."""
import random
import re

# (기본 확률, 사용자에게 묻는지, 최대 말 수, AI에게 줄 설명)
SCENES = {
    "ask_user": (22, True, 2, "한 명이 이번 주에 자기가 공부한 것 한 조각을 말하고, 사용자는 그 부분을 어떻게 봤는지 가볍게 물어본다. "
                              "필요하면 그 앞에 다른 동료가 한마디 보탠다."),
    "dig_user": (24, True, 1, "한 명이 사용자가 방금 한 말에서 궁금한 부분 하나를 콕 집어 물어본다. 자기는 어떻게 생각했는지도 짧게 붙인다."),
    "share": (24, False, 2, "질문 없이, 한두 명이 자기가 공부한 것이나 떠올린 예를 나눈다. 사용자가 한 말과 이어지게 한다. 물음표를 쓰지 않는다."),
    "peer_ask": (14, False, 2, "동료 A가 동료 B가 앞에서 한 말(없으면 B가 공부한 부분) 중 궁금한 것을 B에게 묻고, 이어서 B가 답한다. "
                               "정확히 두 줄이고 두 줄의 member_no는 달라야 한다. 사용자에게는 묻지 않는다."),
    "peer_then_user": (16, True, 3, "동료 A가 동료 B가 한 말 중 궁금한 것을 B에게 묻고, B가 답한 뒤, 한 명이 사용자 생각은 어떤지 짧게 물어 대화에 끌어들인다. "
                                    "앞의 두 줄은 서로 다른 사람이고 정확히 세 줄이다."),
}
MAX_QUIET = 3  # 사용자에게 묻지 않고 이어 갈 수 있는 사용자 차례 수


def asks_user(name: str) -> bool:
    return SCENES[name][1]


def choose(talk: list, member_count: int, no_questions: bool = False, rng=random) -> str:
    """지금까지의 학습 대화를 보고 다음 장면을 고른다. talk는 role과 body를 가진 말의 목록이다."""
    if no_questions:
        return "share"
    users = [i for i, m in enumerate(talk) if m["role"] == "user"]
    asks = [i for i, m in enumerate(talk) if m["role"] == "assistant"]
    if not asks or not users:
        return "ask_user"
    weights = {name: float(s[0]) for name, s in SCENES.items()}
    if member_count < 2:
        weights["peer_ask"] = weights["peer_then_user"] = 0
    said = talk[users[-1]]["body"].strip()
    if len(said) < 8:
        weights["dig_user"] *= 0.2  # 짧은 대답은 캐묻지 않는다.
    if re.search(r"[?？]\s*$", said):
        weights["share"] *= 1.6     # 사용자가 물었으면 나누는 쪽으로 기운다.
        weights["peer_ask"] *= 0.5
    # 마지막 질문 뒤로 사용자가 몇 번 말했는지. 묻지 않는 장면이 이어지면 사용자에게 돌아온다.
    quiet = sum(i > asks[-1] for i in users)
    if quiet >= MAX_QUIET or (users[-1] < len(talk) - 2 and talk[-1]["role"] == "assistant_comment"):
        # 조용했거나, 친구들이 말한 뒤 사용자가 '이야기 이어가기'를 눌렀다.
        for name in weights:
            if not asks_user(name):
                weights[name] = 0
    # 직전 차례가 질문이었으면 이번엔 덜 묻고, 친구들끼리 주고받았으면 이번엔 덜 한다.
    previous = talk[users[-2] + 1:users[-1]] if len(users) > 1 else talk[:users[-1]]
    if any(m["role"] == "assistant" for m in previous):
        for name in ("ask_user", "dig_user"):
            weights[name] *= 0.75
    if sum(m["role"] in ("assistant_comment", "assistant") for m in previous) >= 2:
        weights["peer_ask"] *= 0.3
        weights["peer_then_user"] *= 0.4
    names = list(weights)
    return rng.choices(names, [weights[n] for n in names])[0]


# 사용자가 말한 직후의 장면: (기본 확률, 특정 친구를 불렀을 때 확률, 사용자에게 묻는지, 최소 말 수, 최대 말 수, 설명)
TURNS = {
    "quick": (26, 42, False, 1, 1, "한 명만 짧게 받아 준다. 질문하지 않는다."),
    "quick_ask": (16, 18, True, 1, 1, "한 명이 받아 주면서 사용자에게 궁금한 것 하나를 되묻는다."),
    "two": (16, 10, False, 2, 2, "한 명이 받고, 다른 한 명이 새로운 생각이나 다른 의견을 보탠다. 질문하지 않는다."),
    "share_ask": (14, 6, True, 2, 2, "한 명이 받고, 다른 한 명이 자기가 공부한 것과 이어서 사용자에게 가볍게 묻는다."),
    "chat": (16, 16, False, 2, 3, "한 명이 받으면서 다른 동료가 앞에서 한 말이나 공부한 것을 그 동료 이름을 불러 묻고, 불린 동료가 바로 답한다. "
                                 "할 말이 있으면 다시 한 번 받아친다. 사용자에게는 묻지 않는다."),
    "chat_user": (12, 8, True, 3, 4, "한 명이 받으면서 다른 동료를 이름으로 불러 묻고, 불린 동료가 답한 뒤, 한 명이 사용자 생각을 짧게 묻는다."),
    "everyone": (0, 0, False, 2, 4, "사용자가 모두에게 물었다. 동료들이 한 명씩 돌아가며 서로 다른 생각을 짧게 답한다. 앞사람 말을 되풀이하지 않는다."),
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


def choose_turn(talk: list, text: str, members: list, no_questions: bool = False, presenting: bool = False, rng=random) -> dict:
    """사용자의 말에 몇 명이 어떻게 반응할지 고른다. talk는 이번 말을 뺀 지금까지의 대화다."""
    called, mentioned = names_in(text, members)
    count = len(members)
    if not called and (absent_names(text, members) or FACT.search(text)):
        presenting = True  # 없는 사람을 부르거나 일정·인원을 물으면 한 명만 짧게 답한다.
    if count > 1 and not called and not presenting and EVERYONE.search(text):
        shape = "everyone"
    else:
        weights = {k: float(v[1] if called else v[0]) for k, v in TURNS.items()}
        if presenting:
            weights = {k: v if k == "quick" else 0 for k, v in weights.items()}
        if count < 2:
            for k in ("two", "share_ask", "chat", "chat_user"):
                weights[k] = 0
        if len(called) > 1:  # 여러 명을 불렀으면 한 명만 답하지 않는다.
            weights["quick"] = weights["quick_ask"] = 0
        if mentioned and count > 1:  # 다른 친구 말을 꺼냈으면 그 친구도 끼어들기 쉽다.
            weights["two"] *= 1.5
            weights["chat"] *= 2
        if re.search(r"[?？]\s*$", text):
            weights["quick_ask"] *= 0.5
        if no_questions:
            weights = {k: v if k in ("quick", "two") else 0 for k, v in weights.items()}
            if not any(weights.values()):
                weights["two" if count > 1 else "quick"] = 1
        else:
            # 질문 없는 차례가 이어지면 사용자에게 돌아오고, 바로 앞에서 물었으면 조금 덜 묻는다.
            asks = [i for i, m in enumerate(talk) if m["role"] == "assistant"]
            quiet = sum(m["role"] == "user" for m in talk[asks[-1] + 1:]) if asks else MAX_QUIET
            for k, v in TURNS.items():
                if quiet >= MAX_QUIET - 1 and not called and not presenting and not v[2]:
                    weights[k] = 0
                elif quiet == 0 and v[2]:
                    weights[k] *= 0.75
        # 직전에 여럿이 떠들었으면 이번엔 짧게 간다.
        recent = 0
        for m in reversed(talk):
            if m["role"] == "user":
                break
            recent += m["role"].startswith("assistant")
        if recent >= 3:
            for k in ("two", "chat", "chat_user"):
                weights[k] *= 0.4
        names = list(weights)
        shape = rng.choices(names, [weights[k] for k in names])[0]
    _, _, asks_back, low, high, guide = TURNS[shape]
    if shape == "everyone":
        low = high = min(4, count)
    if len(called) > high:
        high = min(4, len(called))
    return {"shape": shape, "asks": asks_back, "min_lines": max(low, min(len(called), 4)), "max_lines": high, "guide": guide,
            "called": called, "mentioned": mentioned,
            "similar": next((x["similar"] for x in absent_names(text, members) if x["similar"]), None)}


# 말하는 종류마다 그 친구에게 주는 할 일. {to}에는 상대 친구 이름이 들어간다.
TASKS = {
    "react": "사용자의 방금 말을 받아 주세요. 물었으면 바로 답하고, 생각을 말했으면 자기 생각이나 예, 다르게 보는 점 하나를 말하세요. 질문하지 마세요.",
    "react_ask": "사용자의 방금 말을 짧게 받고, 그 말에서 궁금한 것 하나를 사용자에게 되물으세요.",
    "react_ask_peer": "사용자의 방금 말을 짧게 받고, {to}에게 이름을 불러 물으세요. {to}가 앞에서 실제로 한 말이나 관심사에서 궁금한 것 하나만.",
    "each": "사용자가 모두에게 물었습니다. 자기 생각을 짧게 답하세요. 다른 친구가 이미 말한 것과 다른 이야기를 하고 질문하지 마세요.",
    "add": "바로 앞 말에 이어, 아직 안 나온 생각이나 다른 의견을 하나 보태세요. 누구 말에 대한 것인지 드러나게. 질문하지 마세요.",
    "share": "이번 주 범위에서 자기가 공부한 것이나 떠올린 예 하나를 나누세요. 지금 이야기와 이어지게. 질문하지 마세요.",
    "share_ask": "이번 주 범위에서 자기가 공부한 것 한 조각을 말하고, 사용자는 어떻게 봤는지 가볍게 하나 물으세요.",
    "dig": "사용자가 방금 한 말에서 궁금한 부분 하나를 콕 집어 사용자에게 물으세요. 자기 생각도 짧게 붙이세요.",
    "ask_peer": "{to}에게 이름을 불러 물으세요. {to}가 앞에서 실제로 한 말 중 궁금한 것 하나, 없으면 {to}는 이번 주에 뭘 봤는지.",
    "answer_peer": "{to}가 당신을 불러 물었습니다. 물은 것에 바로 답하세요. 되묻지 마세요.",
    "ask_user": "지금까지 친구들이 나눈 이야기를 사용자에게 넘기세요. 사용자는 어떻게 생각하는지 짧게 하나만 물으세요.",
}
ASKING = {"react_ask", "share_ask", "dig", "ask_user"}
MAX_LINES = 5  # 사용자가 한 번 말한 뒤 친구들이 이어 말할 수 있는 최대 줄 수


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
    """사용자의 말 뒤에 누가 무엇을 할지 차례를 짠다. asker는 직전에 물었던 친구다."""
    called = turn["called"]
    first = list(called)
    match = fit(text, members)
    best = max(match.values(), default=0)
    # 내용에 딱 맞는 역할이 있으면 대개 그 친구가, 아니면 방금 물었던 친구가 받는다.
    if not first and best >= 2 and rng.random() < 0.8:
        first = [rng.choice([n for n, v in match.items() if v == best])]
    if not first and not turn.get("similar") and asker and rng.random() < 0.6:
        first = [asker]
    if turn.get("similar") and not called:  # 잘못 불린 것 같은 친구가 나서서 확인한다.
        first = [m["member_no"] for m in members if m["name"] == turn["similar"]]
    order = speakers(talk, members, first, rng, text)
    if turn["mentioned"] and len(order) > 1:  # 말 속에 나온 친구에게 이야기가 가게 한다.
        target = next((n for n in turn["mentioned"] if n != order[0]), None)
        if target:
            order = [order[0], target] + [n for n in order[1:] if n != target]
    shape = turn["shape"]
    if shape == "everyone":
        return [step("each", n) for n in order[:4]]
    if len(called) > 1:
        return [step("react" if i == 0 else "each", n) for i, n in enumerate(called[:4])]
    a, b = order[0], order[1] if len(order) > 1 else None
    if shape == "quick" or (b is None and shape != "quick_ask"):
        return [step("react", a)]
    if shape == "quick_ask":
        return [step("react_ask", a)]
    if shape == "two":
        return [step("react", a), step("add", b, a)]
    if shape == "share_ask":
        return [step("react", a), step("share_ask", b)]
    # 친구끼리 물을 때는 덜 아는 쪽이 묻고 더 아는 쪽이 답하는 일이 많다.
    rank = {m["member_no"]: LEVEL_RANK.get(m.get("level"), 1) for m in members}
    if not called and not turn["mentioned"]:
        if rank[a] > rank[b] and best < 2 and rng.random() < 0.7:
            a, b = b, a
        elif rank[a] == rank[b] and len(order) > 2 and rank[order[2]] > rank[b] and rng.random() < 0.5:
            order[1], order[2] = order[2], order[1]
            b = order[1]
    steps = [step("react_ask_peer", a, b), step("answer_peer", b, a)]
    if shape == "chat_user":
        return steps + [step("ask_user", next((n for n in order if n not in (a, b)), a))]
    return steps + ([step("add", a, b)] if rng.random() < 0.3 else [])


def scene_steps(scene: str, talk: list, members: list, starter: int, rng=random) -> list[dict]:
    """사용자의 말 없이 이야기를 이어 갈 때의 차례."""
    order = speakers(talk, members, [starter], rng)
    a, b = order[0], order[1] if len(order) > 1 else None
    if scene == "dig_user":
        return [step("dig", a)]
    if scene == "share":
        return [step("share", a)] + ([step("add", b, a)] if b and rng.random() < 0.4 else [])
    if scene in ("peer_ask", "peer_then_user") and b:
        steps = [step("ask_peer", a, b), step("answer_peer", b, a)]
        return steps + ([step("ask_user", order[2] if len(order) > 2 else a)] if scene == "peer_then_user" else [])
    return [step("share_ask", a)]


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
