"""Run with: python -m unittest test_flow.py"""
import io
import json
import os
import tempfile
import unittest
from unittest.mock import patch

from fastapi.testclient import TestClient
from reportlab.pdfgen import canvas

from main import app


def sample_pdf():
    output = io.BytesIO()
    pdf = canvas.Canvas(output)
    pdf.drawString(40, 750, "Neural network training begins with data and a model.")
    pdf.drawString(40, 730, "Weights change during optimization. Loss measures prediction error.")
    pdf.drawString(40, 710, "Validation data helps check generalization after training.")
    pdf.showPage()
    pdf.save()
    return output.getvalue()


async def fake_ai(instructions, payload):
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
    return {"question": "검증 데이터를 따로 두는 이유는 무엇인가요?", "page_no": 1,
            "understanding": "훈련과 검증을 구분했다."}


class FlowTest(unittest.TestCase):
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
            self.assertEqual(study["weeks"][0]["title"], "핵심 개념 찾기")
            self.assertIn("핵심 용어", study["weeks"][0]["scope"])
            self.assertNotEqual(study["members"][0]["understanding"], study["members"][1]["understanding"])
            self.assertEqual(study["members"][1]["level"], "심화")
            session = client.post(f"/studies/{study['id']}/weeks/1/sessions",
                json={"text": "정렬 알고리즘의 비교 방식과 시간 복잡도를 설명합니다."})
            self.assertEqual(session.status_code, 200, session.text)
            question = client.post(f"/sessions/{session.json()['session_id']}/question")
            self.assertEqual(question.status_code, 200, question.text)
            self.assertIsNone(question.json()["messages"][0]["page_no"])
            hint = client.post(f"/sessions/{session.json()['session_id']}/explain")
            self.assertEqual(hint.status_code, 200, hint.text)
            self.assertIsNone(hint.json()["messages"][-1]["page_no"])
            self.assertEqual(client.post(f"/sessions/{session.json()['session_id']}/question").status_code, 409)

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


if __name__ == "__main__":
    unittest.main()
