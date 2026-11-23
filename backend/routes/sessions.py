"""채팅 세션 API: 질문, 힌트, 답변(운영 요청 포함), 주차 마무리."""
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
import ai
from auth import current_user
import planner
from db import connect, dumps, loads
from common import PEER_RULES, build_qa, clean_list, learning_messages, qa_stats, required, session_data, source_pages, study_data


router = APIRouter(dependencies=[Depends(current_user)])


class Note(BaseModel):
    text: str = Field(default="", max_length=12000)


@router.post("/studies/{study_id}/weeks/{week_no}/sessions")
def start_session(study_id: int, week_no: int, body: Note):
    with connect() as db:
        required(db, "SELECT 1 FROM weeks WHERE study_id=? AND week_no=?", (study_id, week_no))
        note = body.text.strip()
        if note and len(note) < 10:
            raise HTTPException(400, "학습 정리를 적는다면 10자 이상 적어 주세요.")
        active = db.execute("SELECT id FROM sessions WHERE study_id=? AND week_no=? AND status='active'", (study_id, week_no)).fetchone()
        if active:
            raise HTTPException(409, f"진행 중인 세션이 있습니다: {active['id']}")
        cur = db.execute("INSERT INTO sessions(study_id,week_no,initial_note) VALUES(?,?,?)",
                         (study_id, week_no, note))
        db.execute("UPDATE weeks SET status='in_progress' WHERE study_id=? AND week_no=?", (study_id, week_no))
        return {"session_id": cur.lastrowid}


@router.get("/sessions/{session_id}")
def get_session(session_id: int):
    with connect() as db:
        return session_data(db, session_id)


@router.post("/studies/{study_id}/room")
def open_room(study_id: int):
    """채팅방 열기: 지금 주차 대화(없으면 새로 시작)와 지난 주차 대화를 요청 한 번에 돌려준다."""
    with connect() as db:
        week = db.execute("SELECT week_no FROM weeks WHERE study_id=? AND status!='complete' ORDER BY week_no LIMIT 1",
                          (study_id,)).fetchone() or required(
            db, "SELECT week_no FROM weeks WHERE study_id=? ORDER BY week_no DESC LIMIT 1", (study_id,))
        active = db.execute("SELECT id FROM sessions WHERE study_id=? AND week_no=? AND status='active' "
                            "ORDER BY id LIMIT 1", (study_id, week["week_no"])).fetchone()
        if active:
            session_id = active["id"]
        else:
            session_id = db.execute("INSERT INTO sessions(study_id,week_no,initial_note) VALUES(?,?,'')",
                                    (study_id, week["week_no"])).lastrowid
            db.execute("UPDATE weeks SET status='in_progress' WHERE study_id=? AND week_no=?",
                       (study_id, week["week_no"]))
        history = [session_data(db, r["id"]) for r in db.execute(
            "SELECT id FROM sessions WHERE study_id=? AND status='finished' AND id!=? ORDER BY week_no,id",
            (study_id, session_id))]
        return {"session": session_data(db, session_id), "history": history}


@router.get("/studies/{study_id}/history")
def study_history(study_id: int):
    """채팅방에서 지난 주차 대화를 한 번에 불러온다. 마친 세션만 주차 순서대로 돌려준다."""
    with connect() as db:
        required(db, "SELECT 1 FROM studies WHERE id=?", (study_id,))
        ids = [r["id"] for r in db.execute(
            "SELECT id FROM sessions WHERE study_id=? AND status='finished' ORDER BY week_no,id", (study_id,))]
        return [session_data(db, session_id) for session_id in ids]


@router.get("/sessions/{session_id}/sources/{message_id}")
def message_source(session_id: int, message_id: int):
    with connect() as db:
        session = required(db, "SELECT study_id FROM sessions WHERE id=?", (session_id,))
        message = required(db, "SELECT page_no,pdf_version FROM messages WHERE id=? AND session_id=?",
                           (message_id, session_id))
        if message["page_no"] is None:
            raise HTTPException(404, "이 메시지에는 교안 쪽수가 없습니다.")
        study = required(db, "SELECT pdf_name,pdf_version FROM studies WHERE id=?", (session["study_id"],))
        version = message["pdf_version"] if message["pdf_version"] is not None else 0
        if version == study["pdf_version"]:
            page = required(db, "SELECT body FROM pages WHERE study_id=? AND page_no=?",
                            (session["study_id"], message["page_no"]))
            name = study["pdf_name"]
        else:
            page = required(db, "SELECT body,pdf_name FROM page_history "
                            "WHERE study_id=? AND pdf_version=? AND page_no=?",
                            (session["study_id"], version, message["page_no"]))
            name = page["pdf_name"]
        return {"page_no": message["page_no"], "text": page["body"], "pdf_name": name}


@router.post("/sessions/{session_id}/question")
async def next_question(session_id: int):
    with connect() as db:
        session = session_data(db, session_id)
        if session["status"] != "active":
            raise HTTPException(409, "종료된 세션입니다.")
        if session["messages"] and session["messages"][-1]["role"] in ("assistant", "assistant_hint"):
            raise HTTPException(409, "먼저 현재 질문에 답해 주세요.")
        study = study_data(db, session["study_id"])
        member = study["members"][(session["next_member"] - 1) % len(study["members"])]
        week = study["weeks"][session["week_no"] - 1]
        question_week = {**week, "review": week["review"] if week["include_previous_questions"] else []}
        question_count = sum(m["role"] == "assistant" for m in session["messages"])
        review_focus = (week["review"][0] if week["include_previous_questions"] and
                        session["week_no"] > 1 and question_count == 0 and week["review"] else "")
        pages = source_pages(db, session["study_id"], week["scope"],
                             session["initial_note"] or study["goal"], session["week_no"], len(study["weeks"]))
        previous_context, previous_pages = [], []
        if week["include_previous_questions"]:
            previous_context = [{"week_no": row["week_no"], "initial_note": row["initial_note"],
                                 "revised_note": row["revised_note"], "minutes": loads(row["minutes"]) if row["minutes"] else {}}
                                for row in db.execute(
                                    "SELECT week_no,initial_note,revised_note,minutes FROM sessions "
                                    "WHERE study_id=? AND week_no<? AND status='finished' ORDER BY week_no DESC,id DESC LIMIT 4",
                                    (session["study_id"], session["week_no"]))]
            seen = {p["page_no"] for p in pages}
            for older in reversed(study["weeks"][:session["week_no"] - 1]):
                for page in source_pages(db, session["study_id"], older["scope"], study["goal"],
                                         older["week_no"], len(study["weeks"]))[:1]:
                    if page["page_no"] not in seen and len(previous_pages) < 3:
                        previous_pages.append(page)
                        seen.add(page["page_no"])
    result = await ai.generate_json(
        PEER_RULES +
        "스터디 대화의 다음 차례를 만드세요. JSON 키는 speaker_no,comment,comment_member_no,question,page_no,understanding입니다. "
        "지금 대화 흐름에 가장 필요한 관점을 가진 동료를 speaker_no로 고르세요. 개념이 흐릿하면 '개념 정리', 이해했지만 막연하면 '사례 찾기', "
        "앞 내용과 이어 볼 때는 '흐름 연결', 설명이 단정적이면 '깊이 파기' 역할이 어울립니다. suggested_member_no는 참고일 뿐입니다. "
        "question은 그 동료가 자기 persona.focus 관점에서 실제로 궁금해할 질문 한 개이며, persona.style 말투와 level_guide 깊이를 따르세요. "
        "comment는 다른 동료가 짧게 공감하거나 자기 관점에서 한마디 보탤 때만 넣고, 아니면 빈 문자열로 두세요. comment_member_no는 그 동료 번호입니다. "
        "각 동료의 누적 understanding과 앞선 발언을 반영하세요. "
        "사용자 답변과 직전 동료의 반응에 맞춰 후속 질문을 바꾸세요. 발표문이 비어 있으면 current_source_pages의 교안 내용을 중심으로 질문하세요. "
        "사용자 답변을 그대로 인용해 질문하지 마세요. 무관한 답변을 받았다면 교안의 핵심 개념으로 부드럽게 돌아오세요. "
        "include_previous_questions가 참이고 review_focus가 있으면 이번 세션 첫 질문은 그 복습 내용을 먼저 확인하세요. "
        "거짓이면 이번 주차 범위만 질문하세요. "
        "거짓이어도 동료들의 누적 understanding을 지우거나 되돌리지 마세요. 기존 질문을 반복하지 말고 바로 정답을 알려주지 마세요. "
        "교안 근거가 있다면 page_no에 제공된 쪽수 하나를 쓰고, understanding에는 질문자가 이번 대화에서 이해한 내용을 짧게 적으세요.",
        {"study_goal": study["goal"], "week": question_week, "member": member,
         "members": study["members"], "suggested_member_no": member["member_no"],
         "initial_note": session["initial_note"], "messages": session["messages"][-12:],
         "question_count": question_count, "review_focus": review_focus,
         "asked_questions": [m["body"] for m in session["messages"] if m["role"] == "assistant"][-20:],
         "include_previous_questions": bool(week["include_previous_questions"]),
         "current_source_pages": pages, "previous_source_pages": previous_pages,
         "previous_study": previous_context, "source_pages": pages + previous_pages},
    )
    question = str(result.get("question", "")).strip()
    if not question:
        raise HTTPException(502, "질문이 비어 있습니다.")
    prior_questions = {m["body"].strip() for m in session["messages"] if m["role"] == "assistant"}
    if question in prior_questions:
        result = await ai.generate_json(
            PEER_RULES +
        "앞선 질문과 겹쳤습니다. 아래 질문과 다른 새 질문 한 개를 speaker의 persona 관점으로 만드세요. "
            "JSON 키는 speaker_no,comment,comment_member_no,question,page_no,understanding입니다. "
            "이번 주 범위와 교안에 근거하고, 답변의 맥락을 이어 가세요.",
            {"study_goal": study["goal"], "week": question_week, "member": member,
             "members": study["members"], "messages": session["messages"][-12:],
             "question_count": question_count, "review_focus": review_focus,
             "asked_questions": list(prior_questions), "source_pages": pages + previous_pages,
             "current_source_pages": pages, "previous_source_pages": previous_pages},
        )
        question = str(result.get("question", "")).strip()
        if not question or question in prior_questions:
            raise HTTPException(502, "새 질문을 만들지 못했습니다. 다시 시도해 주세요.")
    member_no = result.get("speaker_no")
    speaker = next((m for m in study["members"] if m["member_no"] == member_no), member)
    comment = str(result.get("comment") or "").strip()[:500]
    comment_member_no = result.get("comment_member_no")
    if comment_member_no not in {m["member_no"] for m in study["members"]} or comment_member_no == speaker["member_no"]:
        comment = ""
    valid_pages = {p["page_no"] for p in pages + previous_pages}
    page_no = result.get("page_no") if result.get("page_no") in valid_pages else None
    if pages and not session["initial_note"] and page_no is None:
        raise HTTPException(502, "교안 근거가 있는 질문을 만들지 못했습니다. 다시 시도해 주세요.")
    with connect() as db:
        current = session_data(db, session_id)
        if len(current["messages"]) != len(session["messages"]):
            raise HTTPException(409, "세션이 변경되었습니다. 다시 시도해 주세요.")
        if comment:
            db.execute("INSERT INTO messages(session_id,role,member_no,body) VALUES(?,?,?,?)",
                       (session_id, "assistant_comment", comment_member_no, comment))
        db.execute("INSERT INTO messages(session_id,role,member_no,body,page_no,pdf_version) VALUES(?,?,?,?,?,?)",
                   (session_id, "assistant", speaker["member_no"], question, page_no,
                    study["pdf_version"] if page_no is not None else None))
        db.execute("UPDATE sessions SET next_member=? WHERE id=?",
                   (speaker["member_no"] % len(study["members"]) + 1, session_id))
        db.execute("UPDATE members SET understanding=? WHERE study_id=? AND member_no=?",
                   (str(result.get("understanding") or speaker["understanding"])[:500],
                    session["study_id"], speaker["member_no"]))
        return session_data(db, session_id)


@router.post("/sessions/{session_id}/explain")
async def explain(session_id: int):
    with connect() as db:
        session = session_data(db, session_id)
        messages = session["messages"]
        if session["status"] != "active" or not messages or messages[-1]["role"] != "assistant":
            raise HTTPException(409, "설명을 요청할 질문이 없습니다.")
        question = messages[-1]
        study = study_data(db, session["study_id"])
        week = study["weeks"][session["week_no"] - 1]
        pages = source_pages(db, session["study_id"], week["scope"], question["body"],
                             session["week_no"], len(study["weeks"]))
        if week["include_previous_questions"] and question["page_no"] not in {p["page_no"] for p in pages}:
            older = [p for w in study["weeks"][:session["week_no"] - 1]
                     for p in source_pages(db, session["study_id"], w["scope"], question["body"],
                                           w["week_no"], len(study["weeks"]))]
            pages = (pages + [p for p in older if p["page_no"] == question["page_no"]])[:4]
    result = await ai.generate_json(
        PEER_RULES +
        "교안 기반 설명을 요청받았습니다. 질문한 동료(member)가 자기 persona 관점과 말투로, 정답을 통째로 말하지 말고 "
        "생각의 실마리가 되는 힌트를 두세 문장으로 주세요. 개념 정리는 핵심 정의의 단서, 사례 찾기는 떠올릴 만한 상황, "
        "흐름 연결은 앞에서 배운 관련 내용, 깊이 파기는 따져 볼 기준을 짚어 주면 좋습니다. "
        "교안에 없는 사실이나 페이지 번호를 만들지 마세요. 교안이 없으면 생각의 방향만 알려주세요. "
        "JSON 키는 explanation,page_no입니다.",
        {"goal": study["goal"], "week": week, "question": question["body"],
         "member": next((m for m in study["members"] if m["member_no"] == question["member_no"]), None),
         "initial_note": session["initial_note"], "messages": messages[-12:], "source_pages": pages},
    )
    explanation = str(result.get("explanation", "")).strip()
    if not explanation:
        raise HTTPException(502, "설명이 비어 있습니다.")
    valid_pages = {p["page_no"] for p in pages}
    page_no = result.get("page_no") if result.get("page_no") in valid_pages else None
    with connect() as db:
        current = session_data(db, session_id)
        if current["status"] != "active" or len(current["messages"]) != len(messages):
            raise HTTPException(409, "세션이 변경되었습니다. 다시 시도해 주세요.")
        db.execute("INSERT INTO messages(session_id,role,member_no,body,page_no,pdf_version) VALUES(?,?,?,?,?,?)",
                   (session_id, "assistant_hint", question["member_no"], explanation, page_no,
                    study["pdf_version"] if page_no is not None else None))
        return session_data(db, session_id)


class Answer(BaseModel):
    text: str = Field(min_length=1, max_length=12000)
    needs_review: bool = False


@router.post("/sessions/{session_id}/answer")
async def answer(session_id: int, body: Answer):
    text = body.text.strip()
    with connect() as db:
        session = session_data(db, session_id)
        if session["status"] != "active":
            raise HTTPException(409, "종료된 대화입니다.")
        study = study_data(db, session["study_id"])
    # 일정·계획 변경 같은 운영 요청은 채팅에서 바로 반영하고 스터디원이 확인 메시지를 남긴다.
    command = await planner.parse(text, session["week_no"], len(study["weeks"]), study["weeks"])
    if command:
        with connect() as db:
            reply = await planner.apply(db, study_data(db, session["study_id"]), command, session["week_no"])
            speaker = (session["next_member"] - 1) % max(1, len(study["members"])) + 1
            db.execute("INSERT INTO messages(session_id,role,body) VALUES(?,?,?)", (session_id, "user", text))
            db.execute("INSERT INTO messages(session_id,role,member_no,body) VALUES(?,?,?,?)",
                       (session_id, "assistant_plan", speaker, reply or "알겠어요!"))
            response = session_data(db, session_id)
            response["plan_changed"] = True
            return response
    if not session["messages"] or session["messages"][-1]["role"] not in ("assistant", "assistant_hint"):
        # 질문이 없을 때 보낸 말은 대화로 남기고, 다음 질문이 이를 이어받는다.
        with connect() as db:
            db.execute("INSERT INTO messages(session_id,role,body) VALUES(?,?,?)", (session_id, "user", text))
            return session_data(db, session_id)
    with connect() as db:
        session = session_data(db, session_id)
        question = next(m for m in reversed(session["messages"]) if m["role"] == "assistant")
        study = study_data(db, session["study_id"])
        week = study["weeks"][session["week_no"] - 1]
        page_query = body.text.strip() if "?" in body.text or "？" in body.text else question["body"] + " " + body.text.strip()
        pages = source_pages(db, session["study_id"], week["scope"], page_query,
                             session["week_no"], len(study["weeks"]))
        if question["page_no"] is not None and question["page_no"] not in {p["page_no"] for p in pages}:
            cited = db.execute("SELECT page_no,body FROM pages WHERE study_id=? AND page_no=?",
                               (session["study_id"], question["page_no"])).fetchone()
            if cited and week["include_previous_questions"]:
                pages = [{"page_no": cited["page_no"], "text": cited["body"][:2500]}] + pages[:2]
        member = next(m for m in study["members"] if m["member_no"] == question["member_no"])
    result = await ai.generate_json(
        PEER_RULES +
        "답변 검토: 질문한 동료(member)로서 사용자의 답변이 직전 질문에 실제로 답했는지 먼저 확인하고, "
        "자기 persona 관점에서 좋았던 점이나 더 생각해 볼 점을 한 가지 짚으세요. "
        "교안 페이지가 있으면 그 내용과 맞는 부분, 다른 부분, 확인할 수 없는 부분을 구분하세요. "
        "교안이 없거나 근거가 부족하면 정답이라고 단정하지 마세요. 무관하거나 장난스러운 답변은 인용하지 말고 "
        "질문으로 돌아올 수 있게 친절하게 말하세요. 사용자가 역으로 질문했다면 그 질문에 교안 기준으로 짧게 답하고 대화를 이어가세요. "
        "다른 동료들도 대화를 듣고 있으므로 이번 답에서 새로 이해한 점을 understanding에 반영하세요. "
        "자연스러운 한국어 존댓말 한두 문장으로 반응하세요. JSON 키는 reaction,alignment,page_no,understanding입니다. "
        "alignment는 supported,partial,off_topic,uncertain,user_question 중 하나입니다. page_no는 제공된 교안 쪽수만 쓰세요.",
        {"question": question["body"], "answer": body.text.strip(), "member": member,
         "study_goal": study["goal"], "week": week, "source_pages": pages, "messages": session["messages"][-8:]},
    )
    reaction = str(result.get("reaction", "")).strip()
    if not reaction:
        raise HTTPException(502, "답변에 대한 반응을 만들지 못했습니다.")
    alignment = result.get("alignment")
    if alignment not in ("supported", "partial", "off_topic", "uncertain", "user_question") or (not pages and alignment != "user_question"):
        alignment = "uncertain"
    page_no = result.get("page_no") if result.get("page_no") in {p["page_no"] for p in pages} else None
    with connect() as db:
        current = session_data(db, session_id)
        if current["status"] != "active" or len(current["messages"]) != len(session["messages"]):
            raise HTTPException(409, "세션이 변경되었습니다. 다시 시도해 주세요.")
        db.execute("INSERT INTO messages(session_id,role,body) VALUES(?,?,?)",
                   (session_id, "user", body.text.strip()))
        db.execute("INSERT INTO messages(session_id,role,member_no,body,page_no,pdf_version) VALUES(?,?,?,?,?,?)",
                   (session_id, "assistant_reaction", question["member_no"], reaction, page_no,
                    study["pdf_version"] if page_no is not None else None))
        if result.get("understanding"):
            db.execute("UPDATE members SET understanding=? WHERE study_id=? AND member_no=?",
                       (str(result["understanding"])[:500], session["study_id"], question["member_no"]))
        if body.needs_review:
            pending = session["unanswered"] + [question["body"]]
            db.execute("UPDATE sessions SET unanswered=? WHERE id=?", (dumps(pending), session_id))
        response = session_data(db, session_id)
        response["answer_alignment"] = alignment
        return response


class Finish(BaseModel):
    revised_note: str = Field(default="", max_length=12000)


@router.post("/sessions/{session_id}/finish")
async def finish(session_id: int, body: Finish):
    with connect() as db:
        session = session_data(db, session_id)
        if session["status"] != "active":
            raise HTTPException(409, "이미 종료된 세션입니다.")
        study = study_data(db, session["study_id"])
        week = study["weeks"][session["week_no"] - 1]
        talk = learning_messages(session["messages"])
        last_user_note = next((m["body"] for m in reversed(talk) if m["role"] == "user"), "")
        learned_source = body.revised_note.strip() or last_user_note or session["initial_note"] or study["goal"]
        pages = source_pages(db, session["study_id"], week["scope"], learned_source,
                             session["week_no"], len(study["weeks"]))
        pending = list(session["unanswered"])
        if session["messages"] and session["messages"][-1]["role"] in ("assistant", "assistant_hint"):
            pending.append(next(m["body"] for m in reversed(session["messages"]) if m["role"] == "assistant"))
        qa = build_qa(talk)
    summary = await ai.generate_json(
        "랩미팅 회의록을 한국어로 정리하세요. 학습 기록으로 남아 나중에 다시 보는 용도입니다. "
        "JSON 키는 summary, keywords, learned, gaps, highlight, next_checks입니다. "
        "summary: 이번 주 주제(week.title)에 대해 사용자가 무엇을 설명했고 무엇이 분명해졌는지 두세 문장. "
        "keywords: 이번 대화에서 다룬 핵심 개념 3~6개(짧은 명사). "
        "learned: 사용자가 실제로 설명해 낸 내용을 사용자 입장에서 한 문장씩, 최대 4개('~를 ~라고 설명했다' 형태). "
        "gaps: 답이 부족했거나 헷갈려 한 부분을 구체적으로 한 문장씩, 최대 4개. "
        "highlight: 사용자 답변 중 가장 잘 설명한 문장 하나를 그대로 인용(없으면 빈 문자열). "
        "next_checks: 다음 주에 다시 확인할 질문 배열이며, 이미 충분히 답한 내용은 넣지 마세요. "
        "qa에 질문과 사용자 답이 짝지어 있습니다. 일정·계획 변경 대화는 학습 내용이 아니므로 빼고, "
        "사용자가 말하지 않은 내용을 사용자가 설명했다고 쓰지 마세요.",
        {"study_goal": study["goal"], "week": week, "qa": qa,
         "initial_note": session["initial_note"], "revised_note": body.revised_note,
         "messages": talk, "unanswered": pending, "source_pages": pages},
    )
    checks = list(dict.fromkeys(str(x).strip()[:500] for x in pending + clean_list(summary.get("next_checks"), 20, 500)
                                if str(x).strip()))[:20]
    highlight = str(summary.get("highlight") or "").strip()[:300]
    minutes = {"summary": str(summary.get("summary", "")), "source_pages": [p["page_no"] for p in pages],
               "keywords": clean_list(summary.get("keywords"), 6, 30),
               "learned": clean_list(summary.get("learned"), 4),
               "gaps": clean_list(summary.get("gaps"), 4),
               "highlight": highlight if any(highlight and highlight in p["answer"] for p in qa) else "",
               "qa": qa, "stats": {**qa_stats(qa), "reviews": len(checks)},
               "initial_note": session["initial_note"], "revised_note": body.revised_note,
               "messages": session["messages"], "next_checks": checks}
    with connect() as db:
        required(db, "SELECT id FROM sessions WHERE id=? AND status='active'", (session_id,))
        db.execute("UPDATE sessions SET revised_note=?,unanswered=?,minutes=?,status='finished' WHERE id=?",
                   (body.revised_note, dumps(checks), dumps(minutes), session_id))
        for question in checks:
            db.execute("INSERT INTO review_items(study_id,question,source_week) VALUES(?,?,?) "
                       "ON CONFLICT(study_id,question) DO UPDATE SET source_week=excluded.source_week,"
                       "status='open',resolved_at=NULL",
                       (session["study_id"], question, session["week_no"]))
        for member in study["members"]:
            learned = f"{member['understanding']} | {session['week_no']}주차 학습: {learned_source}"
            db.execute("UPDATE members SET understanding=? WHERE study_id=? AND member_no=?",
                       (learned[-500:], session["study_id"], member["member_no"]))
        db.execute("UPDATE weeks SET status='complete',progress_percent=100,remaining_scope='' WHERE study_id=? AND week_no=?",
                   (session["study_id"], session["week_no"]))
        if session["week_no"] < len(study["weeks"]):
            next_no = session["week_no"] + 1
            next_week = required(db, "SELECT review FROM weeks WHERE study_id=? AND week_no=?",
                                 (session["study_id"], next_no))
            review = list(dict.fromkeys(loads(next_week["review"]) + checks))
            db.execute("UPDATE weeks SET review=? WHERE study_id=? AND week_no=?",
                       (dumps(review), session["study_id"], next_no))
        return session_data(db, session_id)
