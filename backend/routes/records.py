"""학습 기록 API: 회의록, 복습 항목, 성장 리포트."""
import json
from datetime import datetime, timezone
from fastapi import APIRouter, Depends
from pydantic import BaseModel
from auth import current_user
from db import connect, dumps, loads
from common import learning_messages, required, study_data


router = APIRouter(dependencies=[Depends(current_user)])


@router.get("/studies/{study_id}/minutes")
def list_minutes(study_id: int):
    with connect() as db:
        required(db, "SELECT 1 FROM studies WHERE id=?", (study_id,))
        return [{"week_no": r["week_no"], "session_id": r["id"], "minutes": json.loads(r["minutes"])}
                for r in db.execute("SELECT * FROM sessions WHERE study_id=? AND status='finished' ORDER BY week_no,id", (study_id,))]


@router.get("/studies/{study_id}/reviews")
def list_reviews(study_id: int):
    with connect() as db:
        required(db, "SELECT 1 FROM studies WHERE id=?", (study_id,))
        return [dict(row) for row in db.execute(
            "SELECT * FROM review_items WHERE study_id=? ORDER BY status='open' DESC,source_week,id",
            (study_id,))]


class ReviewEdit(BaseModel):
    resolved: bool


@router.put("/studies/{study_id}/reviews/{review_id}")
def edit_review(study_id: int, review_id: int, body: ReviewEdit):
    with connect() as db:
        item = required(db, "SELECT * FROM review_items WHERE id=? AND study_id=?", (review_id, study_id))
        if body.resolved:
            db.execute("UPDATE review_items SET status='done',resolved_at=? WHERE id=?",
                       (datetime.now(timezone.utc).isoformat(), review_id))
        else:
            db.execute("UPDATE review_items SET status='open',resolved_at=NULL WHERE id=?", (review_id,))
        weeks = list(db.execute("SELECT week_no,review FROM weeks WHERE study_id=? AND status!='complete' ORDER BY week_no",
                                (study_id,)))
        for index, week in enumerate(weeks):
            reviews = [q for q in loads(week["review"]) if q != item["question"]]
            if not body.resolved and index == 0:
                reviews.append(item["question"])
            db.execute("UPDATE weeks SET review=? WHERE study_id=? AND week_no=?",
                       (dumps(reviews), study_id, week["week_no"]))
        return dict(required(db, "SELECT * FROM review_items WHERE id=?", (review_id,)))


@router.get("/studies/{study_id}/learning-report")
def learning_report(study_id: int):
    with connect() as db:
        study = study_data(db, study_id)
        sessions = [dict(row) for row in db.execute(
            "SELECT * FROM sessions WHERE study_id=? AND status='finished' ORDER BY week_no,id", (study_id,))]
        all_reviews = [dict(row) for row in db.execute(
            "SELECT source_week,status FROM review_items WHERE study_id=?", (study_id,))]
        report_weeks = []
        total_questions = total_answers = 0
        for week in study["weeks"]:
            finished = [s for s in sessions if s["week_no"] == week["week_no"]]
            question_count = answer_count = 0
            talks = {}
            for session in finished:
                # 일정 변경 같은 운영 대화는 질문·답변 수와 처음 답변에서 뺀다.
                talks[session["id"]] = learning_messages([dict(m) for m in db.execute(
                    "SELECT role,body FROM messages WHERE session_id=? ORDER BY id", (session["id"],))])
                question_count += sum(m["role"] == "assistant" for m in talks[session["id"]])
                answer_count += sum(m["role"] == "user" for m in talks[session["id"]])
            total_questions += question_count
            total_answers += answer_count
            latest = finished[-1] if finished else None
            minutes = json.loads(latest["minutes"]) if latest and latest["minutes"] else {}
            first_answer = next((m["body"] for m in talks[latest["id"]] if m["role"] == "user"), "") if latest else ""
            baseline = (latest["initial_note"] if latest else "") or first_answer
            report_weeks.append({
                "week_no": week["week_no"], "title": week["title"], "status": week["status"],
                "initial_note": latest["initial_note"] if latest else "",
                "baseline_text": baseline,
                "baseline_label": "대화 전 내 생각" if latest and latest["initial_note"] else "처음 남긴 답변",
                "revised_note": latest["revised_note"] if latest else "",
                "summary": minutes.get("summary", ""),
                "question_count": question_count, "answer_count": answer_count,
                "source_pages": minutes.get("source_pages", []),
                "open_reviews": sum(r["status"] == "open" and r["source_week"] == week["week_no"]
                                    for r in all_reviews),
            })
        return {
            "title": study["title"], "goal": study["goal"],
            "total_weeks": len(study["weeks"]),
            "completed_weeks": sum(w["status"] == "complete" for w in study["weeks"]),
            "question_count": total_questions, "answer_count": total_answers,
            "open_reviews": sum(r["status"] == "open" for r in all_reviews),
            "resolved_reviews": sum(r["status"] == "done" for r in all_reviews),
            "weeks": report_weeks,
        }
