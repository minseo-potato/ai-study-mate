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

    def test_conversation_style_requests(self):
        members = [{"member_no": 1, "name": "서윤"}, {"member_no": 2, "name": "도현"}]
        cases = {
            "너무 어려워요 쉽게 해줘": {"intent": "all_levels", "level": None, "direction": -1},
            "서윤이는 심화로 물어봐줘": {"intent": "member_level", "member_no": 1, "level": "심화", "direction": 0},
            "예시 위주로 해줘": {"intent": "style", "preference": "예시를 많이 들어 가며 이야기하기"},
            "반말로 편하게 말해줘": {"intent": "style", "preference": "편한 반말로 말하기"},
            "지난 주 내용은 그만 물어봐": {"intent": "previous_questions", "on": False},
            '방 이름을 "OS 스터디"로 바꿔줘': {"intent": "rename_room", "title": "OS 스터디"},
            "원래대로 해줘": {"intent": "style_reset"},
        }
        for text, expected in cases.items():
            with self.subTest(text=text):
                self.assertEqual(parse_rules(text, 1, 4, members), expected)

    def test_normal_answers_are_not_commands(self):
        for text in ("손실 함수는 오차를 줄이는 방향을 알려줘요", "다음 주에 다시 보고 싶어요",
                     "예시를 들면 사과가 떨어지는 거예요", "기초 개념은 프로세스예요", "짧은 시간에 많이 처리하는 게 처리량이에요"):
            self.assertIsNone(parse_rules(text, 1, 4))


if __name__ == "__main__":
    unittest.main()
