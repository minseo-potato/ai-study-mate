import unittest

from planner import parse_rules


class PlanCommandTest(unittest.TestCase):
    def test_commands(self):
        cases = {
            "이번 주 모임 3일 미루자": {"intent": "reschedule", "week_no": 1, "days": 3},
            "다음 주는 CNN으로 바꾸자": {"intent": "change_week", "week_no": 2, "title": "CNN", "scope": "CNN"},
            "12월 5일로 옮기자": {"intent": "set_date", "week_no": 1, "month": 12, "day": 5},
            "2주 더 늘리자": {"intent": "add_weeks", "add_weeks": 2},
            "주당 5시간으로 하자": {"intent": "hours", "hours": 5.0},
            "남은 계획 다시 짜줘": {"intent": "replan"},
        }
        for text, expected in cases.items():
            with self.subTest(text=text):
                self.assertEqual(parse_rules(text, 1, 4), expected)

    def test_normal_answers_are_not_commands(self):
        for text in ("손실 함수는 오차를 줄이는 방향을 알려줘요", "다음 주에 다시 보고 싶어요"):
            self.assertIsNone(parse_rules(text, 1, 4))


if __name__ == "__main__":
    unittest.main()
