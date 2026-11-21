"""Run with: python -m unittest test_flow.py"""
import io
import asyncio
import json
import os
import tempfile
import unittest
from unittest.mock import patch

from fastapi.testclient import TestClient
from fastapi import HTTPException
import httpx
from reportlab.pdfgen import canvas

from ai import demo_mode, demo_response, generate_json
from db import connect
from main import app


def sample_pdf():
    output = io.BytesIO()
    pdf = canvas.Canvas(output)
    pdf.drawString(40, 750, "Neural network training begins with data and a model.")
    pdf.drawString(40, 730, "Weights change during optimization. Loss measures prediction error.")
    pdf.drawString(40, 710, "Validation data helps check generalization after training.")
    pdf.showPage()
    pdf.drawString(40, 750, "The second week studies deployment and monitoring.")
    pdf.drawString(40, 730, "Model drift means real world input patterns can change.")
    pdf.showPage()
    pdf.save()
    return output.getvalue()


def replacement_pdf():
    output = io.BytesIO()
    pdf = canvas.Canvas(output)
    pdf.drawString(40, 750, "Sorting algorithms compare pairs and reorder elements in a list.")
    pdf.drawString(40, 730, "Insertion sort moves each item into a sorted prefix. Merge sort divides the list.")
    pdf.drawString(40, 710, "Compare running time and memory use for different input sizes.")
    pdf.save()
    return output.getvalue()


async def fake_ai(instructions, payload):
    if "답변 검토" in instructions:
        pages = payload["source_pages"]
        return {"reaction": "교안 내용을 떠올려 다시 설명해 볼까요?", "alignment": "supported",
                "page_no": pages[0]["page_no"] if pages else None}
    if "교안 기반 설명" in instructions:
        pages = payload["source_pages"]
        return {"explanation": "훈련과 검증의 차이를 다시 생각해 보세요.",
                "page_no": pages[0]["page_no"] if pages else None}
    if "완료하지 못한 범위" in instructions:
        return {"weeks": [{"week_no": w["week_no"], "title": "변경된 목표", "scope": w["scope"]}
                          for w in payload["remaining"]]}
    if "주간 학습 계획" in instructions:
        return {"weeks": [{"week_no": w["week_no"], "title": "AI 제안", "scope": w["scope"]}
                          for w in payload["weeks"]]}
    if "랩미팅 회의록" in instructions:
        return {"summary": "손실 함수와 검증 데이터를 다시 설명했다.", "next_checks": ["일반화 개념 확인"]}
    current_pages = payload.get("current_source_pages", payload["source_pages"])
    suffix = f" ({payload.get('question_count', 0) + 1}번째 질문)" if payload.get("question_count") else ""
    return {"question": "검증 데이터를 따로 두는 이유는 무엇인가요?" + suffix,
            "page_no": current_pages[0]["page_no"] if current_pages else None,
            "understanding": "훈련과 검증을 구분했다."}


class FlowTest(unittest.TestCase):
    def test_next_week_starts_with_pending_review_when_enabled(self):
        with tempfile.TemporaryDirectory() as folder, patch.dict(os.environ, {
            "DATABASE_PATH": os.path.join(folder, "test.sqlite3"), "DEMO_MODE": "1"}):
            client = TestClient(app)
            study = client.post("/studies", data={"title": "신경망", "goal": "훈련 이해",
                "start_date": "2026-11-22", "weeks": "2", "hours_per_week": "3"},
                files={"pdf": ("guide.pdf", sample_pdf(), "application/pdf")}).json()
            first_id = client.post(f"/studies/{study['id']}/weeks/1/sessions",
                                   json={"text": ""}).json()["session_id"]
            first_question = client.post(f"/sessions/{first_id}/question").json()["messages"][-1]["body"]
            client.post(f"/sessions/{first_id}/answer",
                        json={"text": "조금 더 살펴보겠습니다.", "needs_review": True})
            client.post(f"/sessions/{first_id}/finish", json={"revised_note": ""})
            second_id = client.post(f"/studies/{study['id']}/weeks/2/sessions",
                                    json={"text": ""}).json()["session_id"]
            second_question = client.post(f"/sessions/{second_id}/question")
            self.assertEqual(second_question.status_code, 200, second_question.text)
            self.assertIn(first_question[:30], second_question.json()["messages"][-1]["body"])
            self.assertEqual(second_question.json()["messages"][-1]["page_no"], 1)

    def test_review_queue_and_learning_report_follow_real_study_records(self):
        with tempfile.TemporaryDirectory() as folder, patch.dict(os.environ, {
            "DATABASE_PATH": os.path.join(folder, "test.sqlite3")}), patch("main.generate_json", fake_ai):
            client = TestClient(app)
            study = client.post("/studies", data={"title": "신경망", "goal": "훈련과 검증 이해",
                "start_date": "2026-11-22", "weeks": "2", "hours_per_week": "3"}).json()
            study_id = study["id"]
            session_id = client.post(f"/studies/{study_id}/weeks/1/sessions",
                json={"text": "훈련 데이터와 검증 데이터를 구분해 보겠습니다."}).json()["session_id"]
            client.post(f"/sessions/{session_id}/question")
            client.post(f"/sessions/{session_id}/answer",
                        json={"text": "검증 데이터는 일반화를 확인합니다.", "needs_review": True})
            done = client.post(f"/sessions/{session_id}/finish",
                               json={"revised_note": "훈련으로 가중치를 바꾸고 검증으로 일반화를 살핍니다."})
            self.assertEqual(done.status_code, 200, done.text)
            reviews = client.get(f"/studies/{study_id}/reviews").json()
            self.assertEqual(len(reviews), 2)
            self.assertTrue(all(item["status"] == "open" for item in reviews))
            report = client.get(f"/studies/{study_id}/learning-report").json()
            self.assertEqual((report["completed_weeks"], report["question_count"], report["answer_count"]), (1, 1, 1))
            self.assertEqual(report["open_reviews"], 2)
            self.assertEqual(report["weeks"][0]["initial_note"], "훈련 데이터와 검증 데이터를 구분해 보겠습니다.")
            self.assertEqual(report["weeks"][0]["baseline_label"], "대화 전 내 생각")
            self.assertIn("일반화", report["weeks"][0]["revised_note"])
            first = reviews[0]
            resolved = client.put(f"/studies/{study_id}/reviews/{first['id']}", json={"resolved": True})
            self.assertEqual(resolved.json()["status"], "done")
            week2 = client.get(f"/studies/{study_id}").json()["weeks"][1]
            self.assertNotIn(first["question"], week2["review"])
            self.assertEqual(client.get(f"/studies/{study_id}/learning-report").json()["resolved_reviews"], 1)
            reopened = client.put(f"/studies/{study_id}/reviews/{first['id']}", json={"resolved": False})
            self.assertEqual(reopened.json()["status"], "open")
            self.assertIn(first["question"], client.get(f"/studies/{study_id}").json()["weeks"][1]["review"])
            self.assertEqual(client.put(f"/studies/{study_id}/reviews/999999", json={"resolved": True}).status_code, 404)
            with connect() as db:
                db.execute("DELETE FROM review_items")
            migrated = client.get(f"/studies/{study_id}/reviews").json()
            self.assertEqual(len(migrated), 2)

    def test_room_management_and_later_pdf_keep_old_sources(self):
        with tempfile.TemporaryDirectory() as folder, patch.dict(os.environ, {
            "DATABASE_PATH": os.path.join(folder, "test.sqlite3")}), patch("main.generate_json", fake_ai):
            client = TestClient(app)
            study = client.post("/studies", data={"title": "첫 이름", "goal": "정렬 배우기",
                "start_date": "2026-11-22", "weeks": "2", "hours_per_week": "3"}).json()
            study_id = study["id"]
            renamed = client.put(f"/studies/{study_id}/details", json={"title": "새 이름"})
            self.assertEqual(renamed.json()["title"], "새 이름")
            first_pdf = client.put(f"/studies/{study_id}/pdf",
                files={"pdf": ("first.pdf", sample_pdf(), "application/pdf")})
            self.assertEqual(first_pdf.status_code, 200, first_pdf.text)
            self.assertEqual(first_pdf.json()["weeks"][0]["scope"], "1~1쪽")
            session_id = client.post(f"/studies/{study_id}/weeks/1/sessions", json={"text": ""}).json()["session_id"]
            asked = client.post(f"/sessions/{session_id}/question")
            self.assertEqual(asked.status_code, 200, asked.text)
            message_id = asked.json()["messages"][-1]["id"]
            old_source = client.get(f"/sessions/{session_id}/sources/{message_id}").json()
            self.assertEqual(old_source["pdf_name"], "first.pdf")
            self.assertIn("Neural network", old_source["text"])
            changed = client.put(f"/studies/{study_id}/pdf",
                files={"pdf": ("sorting.pdf", replacement_pdf(), "application/pdf")})
            self.assertEqual(changed.status_code, 200, changed.text)
            self.assertEqual(changed.json()["pdf_name"], "sorting.pdf")
            self.assertEqual(client.get(f"/sessions/{session_id}/sources/{message_id}").json(), old_source)
            self.assertEqual(client.get(f"/sessions/{session_id}").json()["pdf_name"], "sorting.pdf")
            archived = client.put(f"/studies/{study_id}/details", json={"archived": True})
            self.assertEqual(archived.json()["archived"], 1)
            self.assertEqual(client.get("/studies").json()[-1]["id"], study_id)
            self.assertEqual(client.put(f"/studies/{study_id}/pin").status_code, 404)
            self.assertEqual(client.put(f"/studies/{study_id}/details", json={"archived": False}).json()["archived"], 0)

    def test_offline_mode_is_default_and_live_requires_opt_in(self):
        with patch.dict(os.environ, {"OPENAI_API_KEY": ""}):
            os.environ.pop("DEMO_MODE", None)
            self.assertTrue(demo_mode())
            self.assertTrue(TestClient(app).get("/health").json()["demo_mode"])
        with patch.dict(os.environ, {"DEMO_MODE": "0", "OPENAI_API_KEY": ""}):
            self.assertFalse(demo_mode())
            self.assertFalse(TestClient(app).get("/health").json()["ai_ready"])

    def test_pinned_room_opens_first_and_empty_notes_can_finish(self):
        with tempfile.TemporaryDirectory() as folder, patch.dict(os.environ, {
            "DATABASE_PATH": os.path.join(folder, "test.sqlite3")}), patch("main.generate_json", fake_ai):
            client = TestClient(app)
            ids = []
            for title in ("첫 방", "두 번째 방"):
                response = client.post("/studies", data={"title": title, "goal": title,
                    "start_date": "2026-11-21", "weeks": "2", "hours_per_week": "3"})
                ids.append(response.json()["id"])
            self.assertEqual(client.put(f"/studies/{ids[0]}/pin").status_code, 200)
            self.assertEqual(client.get("/studies").json()[0]["id"], ids[0])
            session = client.post(f"/studies/{ids[0]}/weeks/1/sessions", json={"text": ""})
            self.assertEqual(session.status_code, 200, session.text)
            session_id = session.json()["session_id"]
            self.assertEqual(client.get(f"/sessions/{session_id}").json()["week"]["week_no"], 1)
            done = client.post(f"/sessions/{session_id}/finish", json={"revised_note": ""})
            self.assertEqual(done.status_code, 200, done.text)
            self.assertEqual(done.json()["status"], "finished")
            report = client.get(f"/studies/{ids[0]}/learning-report").json()
            self.assertEqual(report["weeks"][0]["baseline_text"], "")
            self.assertEqual(client.get(f"/studies/{ids[0]}").json()["weeks"][0]["status"], "complete")

    def test_api_credit_error_is_actionable(self):
        client_class = httpx.AsyncClient
        def no_credits(request):
            return httpx.Response(429, json={"error": {"type": "insufficient_quota",
                "code": "credit_balance_exhausted"}})
        with patch.dict(os.environ, {"OPENAI_API_KEY": "test-only-key", "DEMO_MODE": "0"}), \
             patch("ai.httpx.AsyncClient", side_effect=lambda **kwargs: client_class(
                 transport=httpx.MockTransport(no_credits))):
            with self.assertRaises(HTTPException) as failure:
                asyncio.run(generate_json("질문", {"topic": "정렬"}))
        self.assertEqual(failure.exception.status_code, 503)
        self.assertIn("크레딧", failure.exception.detail)

    def test_responses_api_adapter_uses_server_key_and_parses_json(self):
        seen = {}
        def respond(request):
            seen["authorization"] = request.headers.get("Authorization")
            seen["body"] = json.loads(request.content)
            return httpx.Response(200, json={"output": [{"type": "message", "content": [
                {"type": "output_text", "text": '{"question":"같이 생각해 볼까요?"}'}]}]})

        client_class = httpx.AsyncClient
        with patch.dict(os.environ, {"OPENAI_API_KEY": "test-only-key", "OPENAI_MODEL": "gpt-6-sol", "DEMO_MODE": "0"}), \
             patch("ai.httpx.AsyncClient", side_effect=lambda **kwargs: client_class(
                 transport=httpx.MockTransport(respond))):
            result = asyncio.run(generate_json("질문", {"topic": "정렬"}))
        self.assertEqual(result["question"], "같이 생각해 볼까요?")
        self.assertEqual(seen["authorization"], "Bearer test-only-key")
        self.assertEqual(seen["body"]["model"], "gpt-6-sol")
        self.assertFalse(seen["body"]["store"])

    def test_demo_reacts_to_user_question(self):
        result = demo_response("답변 검토", {"question": "손실 함수란?",
            "answer": "검증 데이터에는 어떤 차이가 있어요?",
            "source_pages": [{"page_no": 1, "text": "Validation data checks generalization."}]})
        self.assertEqual(result["alignment"], "user_question")
        self.assertIn("궁금한 점", result["reaction"])

    def test_peer_can_join_and_another_peer_can_ask(self):
        async def social_ai(instructions, payload):
            if "suggested_member_no" in payload:
                return {"speaker_no": 2, "comment_member_no": 1, "comment": "저도 궁금했어요.",
                        "question": "정렬 방법을 실제 예시에 적용해 볼까요?", "page_no": None,
                        "understanding": "정렬 예시를 더 알고 싶다."}
            return await fake_ai(instructions, payload)

        with tempfile.TemporaryDirectory() as folder, patch.dict(os.environ, {"DATABASE_PATH": os.path.join(folder, "test.sqlite3")}), patch("main.generate_json", social_ai):
            client = TestClient(app)
            study = client.post("/studies", data={"title": "정렬", "goal": "정렬 방법 비교",
                "start_date": "2026-11-18", "weeks": "2", "hours_per_week": "3", "member_count": "2"}).json()
            session_id = client.post(f"/studies/{study['id']}/weeks/1/sessions",
                json={"text": "정렬의 원리와 예시를 공부했습니다."}).json()["session_id"]
            result = client.post(f"/sessions/{session_id}/question")
            self.assertEqual(result.status_code, 200, result.text)
            self.assertEqual([(m["role"], m["member_no"]) for m in result.json()["messages"]],
                             [("assistant_comment", 1), ("assistant", 2)])
            self.assertEqual(result.json()["next_member"], 1)

    def test_demo_study_reacts_and_follows_up_without_echoing_answer(self):
        with tempfile.TemporaryDirectory() as folder, patch.dict(os.environ, {
            "DATABASE_PATH": os.path.join(folder, "test.sqlite3"), "DEMO_MODE": "1"}):
            client = TestClient(app)
            study = client.post("/studies", data={"title": "신경망", "goal": "학습과 배포 이해",
                "start_date": "2026-11-16", "weeks": "2", "hours_per_week": "3", "member_count": "2"},
                files={"pdf": ("guide.pdf", sample_pdf(), "application/pdf")}).json()
            session_id = client.post(f"/studies/{study['id']}/weeks/1/sessions", json={"text": ""}).json()["session_id"]
            first = client.post(f"/sessions/{session_id}/question")
            self.assertEqual(first.status_code, 200, first.text)
            self.assertEqual([m["role"] for m in first.json()["messages"]],
                             ["assistant_comment", "assistant"])
            self.assertEqual(first.json()["messages"][-1]["page_no"], 1)
            answer = client.post(f"/sessions/{session_id}/answer", json={"text": "뭔소리야 동문서답이네"})
            self.assertEqual(answer.status_code, 200, answer.text)
            self.assertEqual(answer.json()["answer_alignment"], "off_topic")
            self.assertNotIn("동문서답", answer.json()["messages"][-1]["body"])
            follow_up = client.post(f"/sessions/{session_id}/question")
            self.assertEqual(follow_up.status_code, 200, follow_up.text)
            self.assertEqual([m["role"] for m in follow_up.json()["messages"][-3:]],
                             ["user", "assistant_reaction", "assistant"])
            self.assertNotIn("동문서답", follow_up.json()["messages"][-1]["body"])

    def test_demo_question_uses_goal_when_note_is_unclear(self):
        payload = {"member": {"perspective": "개념과 정의"},
                   "study_goal": "정렬 원리 설명", "initial_note": "ㅇㄹㅇㄹㅁㄴㅇㄹ",
                   "messages": [], "source_pages": []}
        question = demo_response("질문", payload)["question"]
        self.assertIn("정렬 원리 설명", question)
        self.assertNotIn("ㅇㄹㅇㄹ", question)

    def test_demo_question_uses_pdf_when_note_is_empty(self):
        payload = {"member": {"perspective": "개념과 정의"},
                   "study_goal": "학습 과정", "initial_note": "", "messages": [],
                   "source_pages": [{"page_no": 2, "text": "Model drift changes deployment inputs."}],
                   "current_source_pages": [{"page_no": 2, "text": "Model drift changes deployment inputs."}],
                   "previous_source_pages": [], "include_previous_questions": False}
        question = demo_response("질문", payload)
        self.assertIn("Model drift", question["question"])
        self.assertEqual(question["page_no"], 2)

    def test_demo_reaction_does_not_repeat_irrelevant_answer(self):
        result = demo_response("답변 검토", {"question": "손실 함수란?", "answer": "뭔소리야 동문서답이네",
            "source_pages": [{"page_no": 1, "text": "Loss measures prediction error."}]})
        self.assertEqual(result["alignment"], "off_topic")
        self.assertNotIn("동문서답", result["reaction"])
        self.assertEqual(result["page_no"], 1)

    def test_study_without_pdf_can_start_chat(self):
        with tempfile.TemporaryDirectory() as folder, patch.dict(os.environ, {"DATABASE_PATH": os.path.join(folder, "test.sqlite3")}), patch("main.generate_json", fake_ai):
            client = TestClient(app)
            created = client.post("/studies", data={"title": "알고리즘", "goal": "정렬 원리 설명", "start_date": "2026-11-16",
                "weeks": "2", "hours_per_week": "3", "member_count": "2",
                "member_profiles": json.dumps([
                    {"level": "기초", "understanding": "정렬을 처음 배웠다."},
                    {"level": "심화", "understanding": "삽입 정렬은 설명할 수 있다."}], ensure_ascii=False)})
            self.assertEqual(created.status_code, 200, created.text)
            study = created.json()
            self.assertEqual(study["pdf_name"], "")
            session = client.post(f"/studies/{study['id']}/weeks/1/sessions", json={"text": ""})
            self.assertEqual(session.status_code, 200, session.text)
            self.assertEqual(study["weeks"][0]["title"], "핵심 개념 찾기")
            self.assertIn("핵심 용어", study["weeks"][0]["scope"])
            self.assertNotEqual(study["members"][0]["understanding"], study["members"][1]["understanding"])
            self.assertEqual(study["members"][1]["level"], "심화")
            question = client.post(f"/sessions/{session.json()['session_id']}/question")
            self.assertEqual(question.status_code, 200, question.text)
            self.assertIsNone(question.json()["messages"][0]["page_no"])
            hint = client.post(f"/sessions/{session.json()['session_id']}/explain")
            self.assertEqual(hint.status_code, 200, hint.text)
            self.assertIsNone(hint.json()["messages"][-1]["page_no"])
            self.assertEqual(client.post(f"/sessions/{session.json()['session_id']}/question").status_code, 409)
            answer = client.post(f"/sessions/{session.json()['session_id']}/answer", json={"text": "정렬 순서를 비교합니다."})
            self.assertEqual(answer.status_code, 200, answer.text)
            self.assertEqual(answer.json()["answer_alignment"], "uncertain")

    def test_study_to_minutes_and_next_week_review(self):
        with tempfile.TemporaryDirectory() as folder, patch.dict(os.environ, {"DATABASE_PATH": os.path.join(folder, "test.sqlite3")}), patch("main.generate_json", fake_ai):
            client = TestClient(app)
            created = client.post("/studies", data={"title": "신경망", "goal": "학습 과정을 설명한다", "start_date": "2026-11-16",
                "weeks": "2", "hours_per_week": "3", "member_count": "2"},
                files={"pdf": ("guide.pdf", sample_pdf(), "application/pdf")})
            self.assertEqual(created.status_code, 200, created.text)
            study = created.json()
            self.assertEqual(len(study["weeks"]), 2)
            self.assertEqual(len(study["members"]), 2)
            self.assertNotEqual(study["members"][0]["understanding"], study["members"][1]["understanding"])
            self.assertEqual(study["weeks"][0]["scope"], "1~1쪽")
            plan = client.post(f"/studies/{study['id']}/plan-draft")
            self.assertEqual(plan.status_code, 200, plan.text)
            self.assertEqual(len(plan.json()["weeks"]), 2)
            replan = client.post(f"/studies/{study['id']}/replan-draft")
            self.assertEqual(replan.status_code, 200, replan.text)
            edited = client.put(f"/studies/{study['id']}/weeks/1", json={
                "title": "가중치 학습", "scope": "1~1쪽", "meeting_date": "2026-11-22",
                "status": "planned", "progress_percent": 40, "remaining_scope": "검증 데이터"})
            self.assertEqual(edited.status_code, 200, edited.text)
            self.assertEqual(edited.json()["weeks"][0]["progress_percent"], 40)
            self.assertEqual(edited.json()["weeks"][0]["status"], "in_progress")
            replan = client.post(f"/studies/{study['id']}/replan-draft")
            self.assertEqual(replan.status_code, 200, replan.text)
            preserved = client.put(f"/studies/{study['id']}/weeks/1", json={
                "title": "다시 짠 목표", "scope": "1~1쪽", "meeting_date": "2026-11-22", "status": "in_progress"})
            self.assertEqual(preserved.json()["weeks"][0]["remaining_scope"], "검증 데이터")
            self.assertEqual(preserved.json()["weeks"][0]["progress_percent"], 40)

            opened = client.post(f"/studies/{study['id']}/weeks/1/sessions",
                json={"text": "손실 함수로 오차를 계산하고 가중치를 바꿉니다."})
            self.assertEqual(opened.status_code, 200, opened.text)
            session_id = opened.json()["session_id"]
            in_progress = client.get(f"/studies/{study['id']}").json()
            self.assertEqual(in_progress["weeks"][0]["active_session_id"], session_id)
            question = client.post(f"/sessions/{session_id}/question")
            self.assertEqual(question.status_code, 200, question.text)
            self.assertEqual(question.json()["messages"][0]["page_no"], 1)
            self.assertEqual(client.post(f"/sessions/{session_id}/question").status_code, 409)
            hint = client.post(f"/sessions/{session_id}/explain")
            self.assertEqual(hint.status_code, 200, hint.text)
            self.assertEqual(hint.json()["messages"][-1]["page_no"], 1)
            self.assertEqual(client.post(f"/sessions/{session_id}/explain").status_code, 409)
            answer = client.post(f"/sessions/{session_id}/answer", json={"text": "아직 모르겠습니다.", "needs_review": True})
            self.assertEqual(answer.status_code, 200, answer.text)
            self.assertEqual([m["role"] for m in answer.json()["messages"][-2:]], ["user", "assistant_reaction"])
            self.assertEqual(answer.json()["answer_alignment"], "supported")
            self.assertEqual(answer.json()["unanswered"], ["검증 데이터를 따로 두는 이유는 무엇인가요?"])
            done = client.post(f"/sessions/{session_id}/finish", json={"revised_note": "훈련 데이터로 가중치를 바꾸고 검증 데이터로 일반화를 확인합니다."})
            self.assertEqual(done.status_code, 200, done.text)
            self.assertEqual(done.json()["status"], "finished")
            updated = client.get(f"/studies/{study['id']}").json()
            self.assertIsNone(updated["weeks"][0]["active_session_id"])
            self.assertEqual(updated["weeks"][0]["progress_percent"], 100)
            self.assertEqual(updated["weeks"][0]["remaining_scope"], "")
            self.assertIn("검증 데이터를 따로 두는 이유는 무엇인가요?", updated["weeks"][1]["review"])
            self.assertEqual(len(client.get(f"/studies/{study['id']}/minutes").json()), 1)

    def test_pdf_questions_without_note_and_previous_week_toggle(self):
        captured = []

        async def recording_ai(instructions, payload):
            if "current_source_pages" in payload:
                captured.append(payload)
            return await fake_ai(instructions, payload)

        with tempfile.TemporaryDirectory() as folder, patch.dict(os.environ, {"DATABASE_PATH": os.path.join(folder, "test.sqlite3")}), patch("main.generate_json", recording_ai):
            client = TestClient(app)
            created = client.post("/studies", data={"title": "신경망", "goal": "학습과 배포 이해", "start_date": "2026-11-16",
                "weeks": "2", "hours_per_week": "3", "member_count": "2"},
                files={"pdf": ("guide.pdf", sample_pdf(), "application/pdf")})
            self.assertEqual(created.status_code, 200, created.text)
            study = created.json()
            self.assertEqual(study["weeks"][1]["include_previous_questions"], 1)
            first = client.post(f"/studies/{study['id']}/weeks/1/sessions", json={"text": ""})
            self.assertEqual(first.status_code, 200, first.text)
            first_id = first.json()["session_id"]
            self.assertEqual(client.post(f"/sessions/{first_id}/question").json()["messages"][0]["page_no"], 1)
            self.assertEqual(captured[-1]["initial_note"], "")
            self.assertEqual(captured[-1]["current_source_pages"][0]["page_no"], 1)
            client.post(f"/sessions/{first_id}/answer", json={"text": "훈련 내용을 이해했습니다."})
            self.assertEqual(client.post(f"/sessions/{first_id}/finish", json={"revised_note": "훈련과 검증의 차이를 다시 정리했습니다."}).status_code, 200)
            first_report = client.get(f"/studies/{study['id']}/learning-report").json()
            self.assertEqual(first_report["weeks"][0]["baseline_label"], "처음 남긴 답변")
            self.assertEqual(first_report["weeks"][0]["baseline_text"], "훈련 내용을 이해했습니다.")
            week2 = study["weeks"][1]
            changed = client.put(f"/studies/{study['id']}/weeks/2", json={
                "title": week2["title"], "scope": week2["scope"], "meeting_date": week2["meeting_date"],
                "include_previous_questions": False})
            self.assertEqual(changed.json()["weeks"][1]["include_previous_questions"], 0)
            second = client.post(f"/studies/{study['id']}/weeks/2/sessions", json={"text": ""})
            self.assertEqual(second.status_code, 200, second.text)
            second_id = second.json()["session_id"]
            question = client.post(f"/sessions/{second_id}/question")
            self.assertEqual(question.json()["messages"][0]["page_no"], 2)
            self.assertFalse(captured[-1]["include_previous_questions"])
            self.assertEqual(captured[-1]["week"]["review"], [])
            self.assertEqual(captured[-1]["previous_source_pages"], [])
            self.assertEqual(captured[-1]["previous_study"], [])
            self.assertEqual(captured[-1]["current_source_pages"][0]["page_no"], 2)
            retained_understanding = captured[-1]["member"]["understanding"]
            self.assertIn("훈련과 검증의 차이를 다시 정리했습니다.", retained_understanding)
            client.post(f"/sessions/{second_id}/answer", json={"text": "배포와 감시가 연결됩니다."})
            client.put(f"/studies/{study['id']}/weeks/2", json={
                "title": week2["title"], "scope": week2["scope"], "meeting_date": week2["meeting_date"],
                "status": "in_progress", "include_previous_questions": True})
            question = client.post(f"/sessions/{second_id}/question")
            self.assertEqual(question.status_code, 200, question.text)
            self.assertTrue(captured[-1]["include_previous_questions"])
            self.assertTrue(captured[-1]["week"]["review"])
            self.assertEqual(captured[-1]["previous_source_pages"][0]["page_no"], 1)
            self.assertEqual(captured[-1]["previous_study"][0]["week_no"], 1)


if __name__ == "__main__":
    unittest.main()
