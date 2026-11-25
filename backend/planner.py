"""채팅 메시지로 들어온 스터디 운영 요청을 해석하고 적용한다.

일정·주제·기간 같은 계획 변경뿐 아니라, 난이도·말투·질문 방식처럼 대화를 어떻게 이어 갈지에 대한 요청도
여기서 알아듣고 바로 반영한다. 반영한 진행 방식은 studies.preferences에 남아 모든 프롬프트에 함께 들어간다.
"""
import json
import re
from datetime import date, timedelta

import guard
from ai import demo_mode, generate_json

KEYWORDS = ("미루", "연기", "늦추", "당기", "앞당", "바꾸", "바꿔", "변경", "일정", "계획",
            "주당", "시간", "주 더", "주 추가", "주 늘", "다시 짜", "재조정",
            "쉽게", "쉬운", "어려", "어렵게", "깊게", "난이도", "수준", "기초", "중급", "심화",
            "위주", "짧게", "간단히", "자세히", "자세하게", "천천히", "하나씩", "반말", "존댓말", "편하게",
            "정답", "퀴즈", "문제", "지난 주", "지난주", "이전 주", "그만", "원래대로", "초기화", "이름")
INTENTS = {"reschedule", "set_date", "change_week", "hours", "add_weeks", "replan",
           "previous_questions", "member_level", "all_levels", "style", "style_reset", "rename_room"}
LEVELS = ["기초", "중급", "심화"]
# 요청에 쓰이는 말끝. 답변 속 단어("예시를 들면")를 요청으로 오해하지 않도록 함께 확인한다.
REQUEST = r"(해\s*줘|해\s*주세요|해\s*줄래|해\s*줄\s*수|하자|해요|해라|주면|줘요|줘|말해|물어\s*봐|물어\s*줘|부탁|좋겠|싶어|바꿔|해봐|해\s*봐)"
# 사용자가 말로 정할 수 있는 진행 방식. (찾을 말, 저장할 문장, 함께 둘 수 없는 반대 문장)
STYLES = [
    (r"(예시|사례|예를).{0,8}(위주|많이|들어|중심)", "예시를 많이 들어 가며 이야기하기", None),
    (r"(짧게|간단히|간단하게|짧은)", "짧고 간단하게 말하기", "자세하게 설명하기"),
    (r"(자세히|자세하게|길게|구체적으로)", "자세하게 설명하기", "짧고 간단하게 말하기"),
    (r"(천천히|하나씩|한\s*번에\s*하나)", "한 번에 하나씩 천천히 묻기", None),
    (r"(반말|편하게\s*말)", "편한 반말로 말하기", "존댓말로 말하기"),
    (r"존댓말", "존댓말로 말하기", "편한 반말로 말하기"),
    (r"(정답|답).{0,6}(먼저|알려|가르쳐)", "모르는 부분은 답을 먼저 알려 주고 확인하기", None),
    (r"(퀴즈|문제).{0,6}(내|형식|처럼)", "짧은 퀴즈 형식으로 묻기", None),
    (r"(질문|물어보|묻)\S{0,4}\s*(그만|하지\s*말|하지\s*마|지\s*말|지\s*마|말고|없이)", "질문하지 말고 설명과 생각을 나누기", None),
    (r"(칭찬|격려).{0,6}(많이|해)", "잘한 점을 자주 짚어 주기", None),
    (r"(교안|PDF|pdf).{0,8}(위주|중심|기준)", "교안 내용을 기준으로 이야기하기", None),
]


def _days(text: str) -> int:
    if m := re.search(r"(\d+)\s*일(?!\s*로)", text):
        return int(m.group(1))
    if m := re.search(r"(\d+)\s*주", text):
        return 7 * int(m.group(1))
    for word, n in (("이틀", 2), ("사흘", 3), ("나흘", 4), ("하루", 1)):
        if word in text:
            return n
    return 7


def _target_week(text: str, week_no: int, total: int) -> int:
    if m := re.search(r"(\d+)\s*주차", text):
        return int(m.group(1))
    if "다음 주" in text or "다음주" in text:
        return min(week_no + 1, total)
    return week_no


def _level_request(t: str) -> tuple[str | None, int]:
    """'심화로', '쉽게' 같은 말에서 (정확한 단계, 오르내림)을 뽑는다."""
    exact = next((lv for lv in LEVELS if lv in t), None)
    if re.search(r"(쉽게|쉬운|쉽고|낮춰|내려|어려워|어렵다|버거)", t):
        return exact, -1
    if re.search(r"(어렵게|깊게|높여|올려|도전|너무\s*쉬|쉬워)", t):
        return exact, 1
    return exact, 0


def parse_rules(text: str, week_no: int, total: int, members: list | None = None) -> dict | None:
    """키 없이도 동작하는 규칙 기반 해석. 해당 없으면 None."""
    t = text.strip()
    if m := re.search(r"(\d{1,2})\s*월\s*(\d{1,2})\s*일\s*(?:로|으로|에)", t):
        if re.search(r"(미루|옮기|바꾸|바꿔|변경|하자|해\s*줘|잡)", t):
            return {"intent": "set_date", "week_no": _target_week(t, week_no, total),
                    "month": int(m.group(1)), "day": int(m.group(2))}
    if re.search(r"(미루|연기|늦추|밀어|밀자)", t):
        return {"intent": "reschedule", "week_no": _target_week(t, week_no, total), "days": _days(t)}
    if re.search(r"(앞당|당기|당겨)", t):
        return {"intent": "reschedule", "week_no": _target_week(t, week_no, total), "days": -_days(t)}
    if m := re.search(r"(\d+)\s*주\s*(?:더|추가|늘)", t):
        return {"intent": "add_weeks", "add_weeks": int(m.group(1))}
    if m := re.search(r"주당\s*(\d+(?:\.\d+)?)\s*시간", t):
        return {"intent": "hours", "hours": float(m.group(1))}
    if re.search(r"(계획|일정).{0,8}(다시|새로|재조정)|다시\s*짜|재조정", t):
        return {"intent": "replan"}
    if m := re.search(r"(?:채팅방|방|스터디)\s*이름.{0,6}?['\"“]?([^'\"”]{1,40}?)['\"”]?\s*(?:으로|로)\s*(?:바꿔|변경|하자|해)", t):
        return {"intent": "rename_room", "title": m.group(1).strip()}
    if re.search(r"(지난|이전|앞)\s*(주|주차|내용).{0,12}(그만|빼|말고|안\s*물|묻지\s*마|제외)", t):
        return {"intent": "previous_questions", "on": False}
    if re.search(r"(지난|이전|앞)\s*(주|주차|내용).{0,12}(다시|같이|도)\s*(물어|질문|복습|확인)", t):
        return {"intent": "previous_questions", "on": True}
    exact, direction = _level_request(t)
    if exact or direction:
        for member in members or []:
            if member.get("name") and member["name"] in t:
                return {"intent": "member_level", "member_no": member["member_no"],
                        "level": exact, "direction": direction}
        if re.search(r"(난이도|수준|다들|모두|전부|질문|설명|너무)", t) and (direction or re.search(REQUEST, t)):
            return {"intent": "all_levels", "level": exact, "direction": direction}
    if re.search(r"(원래대로|초기화|기본으로).{0,6}(해|돌려|하자|말)", t):
        return {"intent": "style_reset"}
    if re.search(REQUEST, t):
        for pattern, label, _ in STYLES:
            if re.search(pattern, t):
                return {"intent": "style", "preference": label}
    m = re.search(r"(?:(\d+)\s*주차|다음\s*주|이번\s*주)\s*(?:는|에는|엔|은|에)?\s*(.+?)\s*(?:으로|로)\s*"
                  r"(?:바꾸|바꿔|변경|하자|해\s*줘|공부하)", t)
    if m and len(m.group(2)) >= 2:
        return {"intent": "change_week", "week_no": _target_week(t, week_no, total),
                "title": m.group(2).strip(), "scope": m.group(2).strip()}
    return None


async def parse(text: str, week_no: int, total: int, weeks: list, members: list | None = None) -> dict | None:
    if not any(k in text for k in KEYWORDS) and not re.search(r"\d+\s*월\s*\d+\s*일", text):
        return None
    if demo_mode():
        return parse_rules(text, week_no, total, members)
    try:
        result = await generate_json(
            "스터디 운영 요청 판별: 사용자의 채팅 메시지가 학습 내용에 대한 답변·질문인지, 스터디 진행을 바꾸려는 요청인지 판단하세요. "
            "학습 내용에 대한 말이면 intent를 none으로 두세요. 애매하면 none입니다. "
            "JSON 키는 intent,week_no,days,month,day,title,scope,hours,add_weeks,on,member_no,level,direction,preference입니다. "
            "intent는 다음 중 하나입니다. reschedule(모임 날짜를 days만큼 이동, 음수는 앞당김), set_date(특정 날짜로 지정), "
            "change_week(해당 주차의 title·scope 변경), hours(주당 학습 시간), add_weeks(기간 연장), replan(남은 계획 재조정), "
            "previous_questions(지난 주차 내용도 질문할지 on=true/false), "
            "member_level(특정 스터디원 member_no의 난이도: level=기초/중급/심화 또는 direction=-1 쉽게/+1 어렵게), "
            "all_levels(모든 스터디원 난이도를 level 또는 direction으로), "
            "style(앞으로의 대화 방식 요청을 preference에 짧은 한 문장으로, 예: '예시를 많이 들어 가며 이야기하기'), "
            "style_reset(요청했던 대화 방식을 모두 지우기), rename_room(채팅방 이름을 title로). "
            "'다음 주'는 current_week+1, 언급이 없으면 current_week입니다. '너무 어려워요'처럼 난이도 불만도 all_levels(direction=-1)로 보세요.",
            {"message": text, "current_week": week_no, "total_weeks": total,
             "members": [{"member_no": m["member_no"], "name": m["name"], "level": m["level"]} for m in members or []],
             "weeks": [{"week_no": w["week_no"], "title": w["title"], "meeting_date": w["meeting_date"]} for w in weeks]})
    except Exception:
        return parse_rules(text, week_no, total, members)
    if result.get("intent") not in INTENTS:
        return None
    return result


def load_preferences(raw) -> list:
    try:
        value = json.loads(raw or "[]")
    except ValueError:
        return []
    return [str(x) for x in value if str(x).strip()] if isinstance(value, list) else []


def _shift(level: str, direction: int) -> str:
    i = LEVELS.index(level) if level in LEVELS else 1
    return LEVELS[max(0, min(len(LEVELS) - 1, i + direction))]


def _fmt(d: str) -> str:
    y, m, dd = d.split("-")
    return f"{int(m)}월 {int(dd)}일"


async def apply(db, study: dict, cmd: dict, current_week: int) -> str:
    """요청을 DB에 반영하고 스터디원이 채팅방에 남길 확인 메시지를 돌려준다."""
    sid = study["id"]
    weeks = study["weeks"]
    total = len(weeks)
    intent = cmd["intent"]
    polite = "존댓말로 말하기" in load_preferences(study.get("preferences"))

    def say(casual: str, formal: str) -> str:
        return formal if polite else casual
    target = int(cmd.get("week_no") or current_week)
    target = max(1, min(total, target))

    if intent in ("reschedule", "set_date"):
        week = weeks[target - 1]
        old = date.fromisoformat(week["meeting_date"])
        if intent == "set_date":
            new = date(old.year, int(cmd["month"]), int(cmd["day"]))
            if new < old - timedelta(days=180):
                new = new.replace(year=new.year + 1)
            delta = (new - old).days
        else:
            delta = int(cmd.get("days") or 7)
        if delta == 0:
            return say(f"{target}주차 모임 이미 {_fmt(week['meeting_date'])}이야.", f"{target}주차 모임은 이미 {_fmt(week['meeting_date'])}이에요.")
        moved = [w for w in weeks if w["week_no"] >= target and w["status"] != "complete"]
        for w in moved:
            d = date.fromisoformat(w["meeting_date"]) + timedelta(days=delta)
            db.execute("UPDATE weeks SET meeting_date=? WHERE study_id=? AND week_no=?", (d.isoformat(), sid, w["week_no"]))
        new_date = (old + timedelta(days=delta)).isoformat()
        verb = "미뤘어" if delta > 0 else "앞당겼어"
        tail = f" 뒤 일정도 {abs(delta)}일씩 같이 옮겼어" if len(moved) > 1 else ""
        return say(f"오케이, {target}주차 모임 {_fmt(new_date)}로 {verb}." + (tail + "." if tail else ""),
                   f"좋아요! {target}주차 모임을 {_fmt(new_date)}로 {verb}요." + (tail + "요." if tail else ""))

    if intent == "change_week":
        title = str(cmd.get("title") or "").strip()[:120]
        scope = str(cmd.get("scope") or title).strip()[:500]
        if not title:
            return say("어떤 내용으로 바꿀지 한 번만 더 말해 줘.", "어떤 내용으로 바꿀지 한 번만 더 알려 주세요.")
        db.execute("UPDATE weeks SET title=?,scope=? WHERE study_id=? AND week_no=?", (title, scope, sid, target))
        return say(f"알겠어, {target}주차는 '{title}'(으)로 바꿔 둘게.", f"알겠어요. {target}주차는 '{title}'(으)로 바꿔 둘게요.")

    if intent == "hours":
        hours = float(cmd.get("hours") or 0)
        if not 0.5 <= hours <= 80:
            return say("주당 시간은 0.5~80시간 사이로 정해 줘.", "주당 시간은 0.5~80시간 사이로 정해 주세요.")
        db.execute("UPDATE studies SET hours_per_week=? WHERE id=?", (hours, sid))
        return say(f"좋아, 이제 주당 {hours:g}시간 기준으로 하자.", f"좋아요, 앞으로 주당 {hours:g}시간 기준으로 진행할게요.")

    if intent == "add_weeks":
        add = int(cmd.get("add_weeks") or 1)
        if not 1 <= add or total + add > 26:
            return say("스터디는 26주까지만 늘릴 수 있어.", "스터디 기간은 최대 26주까지만 늘릴 수 있어요.")
        last = date.fromisoformat(weeks[-1]["meeting_date"])
        for i in range(1, add + 1):
            db.execute("INSERT INTO weeks(study_id,week_no,title,scope,meeting_date) VALUES(?,?,?,?,?)",
                       (sid, total + i, f"{total + i}주차", study["goal"],
                        (last + timedelta(days=7 * i)).isoformat()))
        db.execute("UPDATE studies SET weeks=? WHERE id=?", (total + add, sid))
        return say(f"{add}주 늘렸어. 이제 총 {total + add}주야.", f"스터디를 {add}주 늘렸어요. 이제 총 {total + add}주예요.")

    if intent == "replan":
        remaining = [w for w in weeks if w["status"] != "complete"]
        if not remaining:
            return say("남은 주차가 없어서 바꿀 게 없어.", "남은 주차가 없어서 바꿀 계획이 없어요.")
        result = await generate_json(
            "완료하지 못한 범위와 복습 항목을 남은 주차에 재배분한 한국어 계획을 제안하세요. "
            "JSON 키는 weeks이며, 각 항목에 week_no,title,scope를 넣으세요. 날짜는 수정하지 마세요.",
            {"goal": study["goal"], "hours_per_week": study["hours_per_week"],
             "completed": [w for w in weeks if w["status"] == "complete"], "remaining": remaining})
        drafts = [w for w in result.get("weeks", []) if isinstance(w, dict) and w.get("title") and w.get("scope")]
        valid = {w["week_no"] for w in remaining}
        changed = 0
        for w in drafts:
            if w.get("week_no") in valid:
                db.execute("UPDATE weeks SET title=?,scope=? WHERE study_id=? AND week_no=?",
                           (str(w["title"])[:120], str(w["scope"])[:500], sid, w["week_no"]))
                changed += 1
        lines = "\n".join(f"· {w['week_no']}주차 {w['title']}" for w in drafts if w.get("week_no") in valid)
        return say(f"남은 {changed}개 주차 다시 짜 봤어.\n{lines}", f"남은 {changed}개 주차 계획을 다시 짰어요.\n{lines}") if changed \
            else say("지금 계획 그대로 가는 게 나을 듯.", "지금 계획을 그대로 두는 게 좋겠어요.")

    if intent == "previous_questions":
        on = bool(cmd.get("on"))
        db.execute("UPDATE weeks SET include_previous_questions=? WHERE study_id=? AND week_no>=? AND status!='complete'",
                   (int(on), sid, current_week))
        return (say("좋아, 지난 주차 것도 섞어서 얘기하자.", "좋아요, 지난 주차 내용도 섞어서 같이 확인할게요.") if on
                else say("알겠어, 이번 주 것만 얘기하자.", "알겠어요. 이제 이번 주 내용만 이야기할게요."))

    members = study["members"]
    if intent == "member_level":
        member = next((m for m in members if m["member_no"] == cmd.get("member_no")), None)
        if not member:
            return say("누구 난이도를 바꿀지 이름으로 말해 줘.", "누구의 난이도를 바꿀지 이름으로 한 번만 더 알려 주세요.")
        level = cmd.get("level") if cmd.get("level") in LEVELS else _shift(member["level"], int(cmd.get("direction") or 0))
        db.execute("UPDATE members SET level=? WHERE study_id=? AND member_no=?", (level, sid, member["member_no"]))
        cmd["speaker_no"] = member["member_no"]  # 바뀐 당사자가 직접 대답한다
        if level == member["level"]:
            return say(f"나 지금도 {level} 단계야. 더 바꾸고 싶으면 말해 줘.", f"지금도 {level} 단계로 이야기하고 있어요.")
        easier = LEVELS.index(level) < LEVELS.index(member["level"]) if member["level"] in LEVELS else False
        return say(f"알겠어, 이제 {level} 단계로 " + ("더 쉽게 풀어서 말할게." if easier else "좀 더 깊게 얘기할게."),
                   f"알겠어요! 이제 {level} 단계에 맞춰서 " + ("더 쉽게 풀어서 말할게요." if easier else "조금 더 깊게 이야기할게요."))

    if intent == "all_levels":
        changed = []
        for member in members:
            level = cmd.get("level") if cmd.get("level") in LEVELS else _shift(member["level"], int(cmd.get("direction") or 0))
            if level != member["level"]:
                db.execute("UPDATE members SET level=? WHERE study_id=? AND member_no=?", (level, sid, member["member_no"]))
                changed.append(f"{member['name']} {level}")
        if not changed:
            return say("이미 그 단계야.", "지금 난이도가 이미 그 단계예요.")
        easier = int(cmd.get("direction") or 0) < 0 or cmd.get("level") == "기초"
        return (say("그럼 다 같이 좀 쉽게 가자. ", "그럼 다 같이 한 단계 쉽게 가 볼게요. ") if easier
                else say("좋아, 다 같이 좀 깊게 가자. ", "좋아요, 다 같이 한 단계 깊게 가 볼게요. ")) + \
            f"({', '.join(changed)})"

    if intent in ("style", "style_reset"):
        prefs = load_preferences(study.get("preferences"))
        if intent == "style_reset":
            db.execute("UPDATE studies SET preferences='[]' WHERE id=?", (sid,))
            return say("알겠어, 처음처럼 할게.", "알겠어요. 처음처럼 할게요.") if prefs else say("따로 정해 둔 방식은 없어.", "지금은 따로 정한 진행 방식이 없어요.")
        label = guard.clean_label(cmd.get("preference"), 60)
        if guard.is_trick(label):
            label = ""
        if not label:
            return say("어떤 식으로 할지 한 번만 더 말해 줘.", "어떤 방식으로 진행하면 좋을지 한 번만 더 알려 주세요.")
        opposite = next((o for _, l, o in STYLES if l == label), None)
        prefs = [x for x in prefs if x not in (label, opposite)] + [label]
        db.execute("UPDATE studies SET preferences=? WHERE id=?", (json.dumps(prefs[-6:], ensure_ascii=False), sid))
        polite = label == "존댓말로 말하기" or (polite and label != "편한 반말로 말하기")
        return say(f"오케이, 이제 '{label}'로 할게.", f"좋아요! 앞으로는 '{label}'로 할게요.")

    if intent == "rename_room":
        title = guard.clean_label(cmd.get("title"), 120)
        if not title or guard.is_trick(title):
            return say("어떤 이름으로 바꿀지 말해 줘.", "어떤 이름으로 바꿀지 알려 주세요.")
        db.execute("UPDATE studies SET title=? WHERE id=?", (title, sid))
        return say(f"방 이름 '{title}'(으)로 바꿨어.", f"채팅방 이름을 '{title}'(으)로 바꿨어요.")
    return ""
