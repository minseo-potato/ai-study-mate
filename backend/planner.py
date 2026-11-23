"""채팅 메시지로 들어온 스터디 운영 요청(일정 변경, 주제 변경 등)을 해석하고 적용한다."""
import re
from datetime import date, timedelta

from ai import demo_mode, generate_json

KEYWORDS = ("미루", "연기", "늦추", "당기", "앞당", "바꾸", "바꿔", "변경", "일정", "계획",
            "주당", "시간", "주 더", "주 추가", "주 늘", "다시 짜", "재조정")
INTENTS = {"reschedule", "set_date", "change_week", "hours", "add_weeks", "replan"}


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


def parse_rules(text: str, week_no: int, total: int) -> dict | None:
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
    m = re.search(r"(?:(\d+)\s*주차|다음\s*주|이번\s*주)\s*(?:는|에는|엔|은|에)?\s*(.+?)\s*(?:으로|로)\s*"
                  r"(?:바꾸|바꿔|변경|하자|해\s*줘|공부하)", t)
    if m and len(m.group(2)) >= 2:
        return {"intent": "change_week", "week_no": _target_week(t, week_no, total),
                "title": m.group(2).strip(), "scope": m.group(2).strip()}
    return None


async def parse(text: str, week_no: int, total: int, weeks: list) -> dict | None:
    if not any(k in text for k in KEYWORDS) and not re.search(r"\d+\s*월\s*\d+\s*일", text):
        return None
    if demo_mode():
        return parse_rules(text, week_no, total)
    try:
        result = await generate_json(
            "스터디 운영 요청 판별: 사용자의 채팅 메시지가 학습 내용에 대한 답변인지, 스터디 일정·계획을 바꾸려는 요청인지 판단하세요. "
            "운영 요청이 아니면 intent를 none으로 두세요. JSON 키는 intent,week_no,days,month,day,title,scope,hours,add_weeks입니다. "
            "intent는 none,reschedule(모임 날짜를 days만큼 이동, 음수는 앞당김),set_date(특정 날짜로 지정),"
            "change_week(해당 주차의 제목과 학습 범위 변경),hours(주당 학습 시간 변경),add_weeks(기간 연장),replan(남은 계획 재조정) 중 하나입니다. "
            "'다음 주'는 current_week+1, 언급이 없으면 current_week입니다.",
            {"message": text, "current_week": week_no, "total_weeks": total,
             "weeks": [{"week_no": w["week_no"], "title": w["title"], "meeting_date": w["meeting_date"]} for w in weeks]})
    except Exception:
        return parse_rules(text, week_no, total)
    if result.get("intent") not in INTENTS:
        return None
    return result


def _fmt(d: str) -> str:
    y, m, dd = d.split("-")
    return f"{int(m)}월 {int(dd)}일"


async def apply(db, study: dict, cmd: dict, current_week: int) -> str:
    """요청을 DB에 반영하고 스터디원이 채팅방에 남길 확인 메시지를 돌려준다."""
    sid = study["id"]
    weeks = study["weeks"]
    total = len(weeks)
    intent = cmd["intent"]
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
            return f"{target}주차 모임은 이미 {_fmt(week['meeting_date'])}이에요."
        moved = [w for w in weeks if w["week_no"] >= target and w["status"] != "complete"]
        for w in moved:
            d = date.fromisoformat(w["meeting_date"]) + timedelta(days=delta)
            db.execute("UPDATE weeks SET meeting_date=? WHERE study_id=? AND week_no=?", (d.isoformat(), sid, w["week_no"]))
        new_date = (old + timedelta(days=delta)).isoformat()
        verb = "미뤘어요" if delta > 0 else "앞당겼어요"
        tail = f" 뒤 일정도 {abs(delta)}일씩 같이 옮겼어요." if len(moved) > 1 else ""
        return f"좋아요! {target}주차 모임을 {_fmt(new_date)}로 {verb}.{tail}"

    if intent == "change_week":
        title = str(cmd.get("title") or "").strip()[:120]
        scope = str(cmd.get("scope") or title).strip()[:500]
        if not title:
            return "어떤 내용으로 바꿀지 한 번만 더 알려 주세요."
        db.execute("UPDATE weeks SET title=?,scope=? WHERE study_id=? AND week_no=?", (title, scope, sid, target))
        return f"알겠어요. {target}주차는 '{title}'(으)로 바꿔 둘게요."

    if intent == "hours":
        hours = float(cmd.get("hours") or 0)
        if not 0.5 <= hours <= 80:
            return "주당 시간은 0.5~80시간 사이로 정해 주세요."
        db.execute("UPDATE studies SET hours_per_week=? WHERE id=?", (hours, sid))
        return f"좋아요, 앞으로 주당 {hours:g}시간 기준으로 진행할게요."

    if intent == "add_weeks":
        add = int(cmd.get("add_weeks") or 1)
        if not 1 <= add or total + add > 26:
            return "스터디 기간은 최대 26주까지만 늘릴 수 있어요."
        last = date.fromisoformat(weeks[-1]["meeting_date"])
        for i in range(1, add + 1):
            db.execute("INSERT INTO weeks(study_id,week_no,title,scope,meeting_date) VALUES(?,?,?,?,?)",
                       (sid, total + i, "복습과 심화", "앞에서 배운 내용 복습과 심화",
                        (last + timedelta(days=7 * i)).isoformat()))
        db.execute("UPDATE studies SET weeks=? WHERE id=?", (total + add, sid))
        return f"스터디를 {add}주 늘렸어요. 이제 총 {total + add}주예요."

    if intent == "replan":
        remaining = [w for w in weeks if w["status"] != "complete"]
        if not remaining:
            return "남은 주차가 없어서 바꿀 계획이 없어요."
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
        return f"남은 {changed}개 주차 계획을 다시 짰어요.\n{lines}" if changed else "지금 계획을 그대로 두는 게 좋겠어요."
    return ""
