"""AI 친구 한 명 한 명을 따로 부른다. 각자 자기 기억과, 내가 한 말·남이 한 말이 구분된 대화만 본다."""
import random
from datetime import date
import guard
import ai
import scenes
from common import PEER_RULES, clean_speech, peer_context


def view(messages: list, member_no: int, study: dict) -> list:
    """한 친구의 눈으로 본 대화. 내가 한 말은 '나', 나머지는 말한 사람 이름으로 적는다."""
    names = {m["member_no"]: m["name"] for m in study["members"]}
    out = []
    for m in messages:
        if m["role"] == "evaluation":
            continue
        mine = m["role"].startswith("user")
        body = m["body"]
        if m["role"] == "user_file":
            body = f"(파일을 올림: {body})"
        elif mine and len(body) < 600 and guard.is_trick(body):
            body = guard.HIDDEN
        who = (study["user_name"] or "친구") if mine else "나" if m["member_no"] == member_no else names.get(m["member_no"], "다른 친구")
        out.append({"who": who, "body": body})
    return out


def study_info(study: dict, week_no: int | None = None) -> dict:
    """친구들이 확실히 알고 있어야 할 이 스터디의 정보."""
    weeks = study["weeks"]
    if week_no is None:
        week_no = next((w["week_no"] for w in weeks if w["status"] != "complete"), len(weeks))
    state = {"complete": "끝남", "in_progress": "진행 중"}
    listed = []
    for w in weeks:
        item = {"week_no": w["week_no"], "title": w["title"], "scope": w["scope"], "meeting_date": w["meeting_date"],
                "state": "지금" if w["week_no"] == week_no else state.get(w["status"], "아직 안 함")}
        if w["week_no"] == len(weeks) > 1:
            item["presentation"] = True
        if w["week_no"] in study["week_notes"] and w["week_no"] != week_no:
            item["what_we_did"] = study["week_notes"][w["week_no"]]
        listed.append(item)
    people = [{"name": m["name"], "interest": m["persona"]["role"], "level": m["level"]} for m in study["members"]]
    return {"room_name": study["title"], "topic": study["goal"], "today": date.today().isoformat(), "start_date": study["start_date"],
            "friends": people, "friend_count": len(people), "people_count": len(people) + 1, "user": study["user_name"],
            "total_weeks": len(weeks), "current_week": next(w for w in listed if w["week_no"] == week_no),
            "weeks": listed, "hours_per_week": study["hours_per_week"],
            "material": {"name": study["pdf_name"], "pages": study["page_count"]} if study["pdf_name"] else None}


# 단계마다 이번에 보일 모습. 매번 같지 않게 하나를 뽑는다.
LEVEL_MODES = {
    "기초": (
        "아는 데까지만 말하고 '그다음은 모르겠어'라고 솔직히 말한다",
        "들은 말을 쉬운 낱말로 바꿔 보고 '이 뜻 맞아?' 하고 확인한다(묻지 말라는 차례면 '맞나 모르겠네'로 끝낸다)",
        "흔히 하는 오해를 '나는 ~인 줄 알았는데 아닌가' 하고 털어놓는다(사실처럼 단정하지 않는다)",
        "어려운 낱말 하나를 짚어 거기서 막혔다고 말한다",
    ),
    "중급": ("이유 하나를 들어 설명한다", "기본은 설명하되 세부는 '거기까진 헷갈려'라고 한다", "배운 것을 지금 이야기에 적용해 본다"),
    "심화": ("안에서 실제로 일어나는 일을 짚는다", "성립하지 않는 조건이나 실패하는 경우를 짚는다", "다른 방법과 견주어 장단점을 말한다"),
}
ROLE_CHECK = {
    "개념과 정의": "낱말의 뜻이나 두 말의 차이를 짚었는가? 비유나 가정은 쓰지 않았는가?",
    "예시와 적용": "배달·게임·편의점처럼 눈에 보이는 생활 장면이 들어갔는가? 기술 용어만 늘어놓지 않았는가?",
    "앞 주차와의 연결": "앞에 나온 말 둘 이상이나 앞뒤 순서를 이었는가? 새 예시를 만들지 않았는가?",
    "다른 해석": "조건, 반례, 의심 가운데 하나를 걸었는가? 그냥 동의하고 끝내지 않았는가?",
}


def reminder(member: dict, rng=random) -> str:
    """길고 많은 규칙에 묻히지 않도록, 이 친구의 단계와 성격을 마지막에 한 번 더 짚는다."""
    level = member["level"] if member["level"] in LEVEL_MODES else "중급"
    limit = {"기초": "한 문장, 전문 용어는 많아야 하나. 원리·옵션·예외를 막힘없이 설명하면 안 된다. 나를 콕 집어 어려운 걸 물어도 다 알지 못한다.",
             "중급": "한두 문장. 드문 예외까지 다 아는 것처럼 말하지 않는다.",
             "심화": "한두 문장, 꼭 필요하면 세 문장. 기본 정의를 되풀이하지 않는다."}[level]
    return (f"\n[마지막 확인]\n당신의 단계는 {level}: {limit} 이번에는 {rng.choice(LEVEL_MODES[level])}.\n"
            f"성격: {ROLE_CHECK.get(member['perspective'], '')} "
            "일정·인원·주제 같은 사실 질문이나 엉뚱한 말을 받아넘길 때, 누가 누구인지 확인하는 말에는 이 확인을 적용하지 말고 짧게 답하세요. JSON만 출력하세요.")


async def speak(study: dict, member: dict, messages: list, task: str, extra: dict, window: int = 18) -> dict:
    """member 한 명의 입장에서 한마디를 만든다. 다른 친구의 기억이나 설정은 보여 주지 않는다."""
    own = [m["body"] for m in messages if not m["role"].startswith("user") and m["member_no"] == member["member_no"]]
    payload = {**peer_context(study, messages), "member": member, "my_memory": member["understanding"], "my_lines": own[-8:],
               "friends": [{"name": m["name"], "interest": m["persona"]["role"], "level": m["level"]} for m in study["members"]
                           if m["member_no"] != member["member_no"]],
               "study_info": study_info(study, (extra.get("week") or {}).get("week_no")),
               "room_people": [m["name"] for m in study["members"]] + [study["user_name"]],
               "absent_names": scenes.absent_names(next((m["body"] for m in reversed(messages) if m["role"] == "user"), ""),
                                                   study["members"], study["user_name"]),
               "study_goal": study["goal"], "messages": view(messages[-window:], member["member_no"], study), **extra}
    return await ai.generate_json(PEER_RULES + task + reminder(member), payload)


def line(result: dict, members: list, *keys: str, limit: int = 900) -> str:
    """응답에서 말을 꺼내 다듬는다. 여러 이름의 키를 차례로 찾는다."""
    return clean_speech(next((result[k] for k in keys if result.get(k)), ""), members)[:limit]
