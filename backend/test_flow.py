"""Run with: python -m unittest test_flow.py"""
import io
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
            self.assertEqual(study["weeks"][0]["scope"], "1~1쪽")
            plan = client.post(f"/studies/{study['id']}/plan-draft")
            self.assertEqual(plan.status_code, 200, plan.text)
            self.assertEqual(len(plan.json()["weeks"]), 2)
            replan = client.post(f"/studies/{study['id']}/replan-draft")
            self.assertEqual(replan.status_code, 200, replan.text)

            opened = client.post(f"/studies/{study['id']}/weeks/1/sessions",
                json={"text": "손실 함수로 오차를 계산하고 가중치를 바꿉니다."})
            self.assertEqual(opened.status_code, 200, opened.text)
            session_id = opened.json()["session_id"]
            question = client.post(f"/sessions/{session_id}/question")
            self.assertEqual(question.status_code, 200, question.text)
            self.assertEqual(question.json()["messages"][0]["page_no"], 1)
            self.assertEqual(client.post(f"/sessions/{session_id}/question").status_code, 409)
            answer = client.post(f"/sessions/{session_id}/answer", json={"text": "아직 모르겠습니다.", "needs_review": True})
            self.assertEqual(answer.status_code, 200, answer.text)
            done = client.post(f"/sessions/{session_id}/finish", json={"revised_note": "훈련 데이터로 가중치를 바꾸고 검증 데이터로 일반화를 확인합니다."})
            self.assertEqual(done.status_code, 200, done.text)
            self.assertEqual(done.json()["status"], "finished")
            updated = client.get(f"/studies/{study['id']}").json()
            self.assertIn("검증 데이터를 따로 두는 이유는 무엇인가요?", updated["weeks"][1]["review"])
            self.assertEqual(len(client.get(f"/studies/{study['id']}/minutes").json()), 1)


if __name__ == "__main__":
    unittest.main()
