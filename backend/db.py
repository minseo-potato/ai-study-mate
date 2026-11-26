import hashlib
import json
import os
import sqlite3
from contextlib import contextmanager


SCHEMA = """
CREATE TABLE IF NOT EXISTS studies (
 id INTEGER PRIMARY KEY, title TEXT NOT NULL, goal TEXT NOT NULL,
 start_date TEXT NOT NULL, weeks INTEGER NOT NULL, hours_per_week REAL NOT NULL,
 member_count INTEGER NOT NULL, rules TEXT NOT NULL, pdf_name TEXT NOT NULL,
 pinned INTEGER NOT NULL DEFAULT 0, archived INTEGER NOT NULL DEFAULT 0,
 pdf_version INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS pages (
 study_id INTEGER NOT NULL, page_no INTEGER NOT NULL, body TEXT NOT NULL,
 PRIMARY KEY(study_id,page_no)
);
CREATE TABLE IF NOT EXISTS page_history (
 study_id INTEGER NOT NULL, pdf_version INTEGER NOT NULL, page_no INTEGER NOT NULL,
 body TEXT NOT NULL, pdf_name TEXT NOT NULL,
 PRIMARY KEY(study_id,pdf_version,page_no)
);
CREATE TABLE IF NOT EXISTS weeks (
 study_id INTEGER NOT NULL, week_no INTEGER NOT NULL, title TEXT NOT NULL,
 scope TEXT NOT NULL, meeting_date TEXT NOT NULL, review TEXT NOT NULL DEFAULT '[]',
 status TEXT NOT NULL DEFAULT 'planned', progress_percent INTEGER NOT NULL DEFAULT 0,
 remaining_scope TEXT NOT NULL DEFAULT '', include_previous_questions INTEGER NOT NULL DEFAULT 1,
 PRIMARY KEY(study_id,week_no)
);
CREATE TABLE IF NOT EXISTS members (
 study_id INTEGER NOT NULL, member_no INTEGER NOT NULL, name TEXT NOT NULL,
 perspective TEXT NOT NULL, level TEXT NOT NULL, understanding TEXT NOT NULL DEFAULT '',
 PRIMARY KEY(study_id,member_no)
);
CREATE TABLE IF NOT EXISTS sessions (
 id INTEGER PRIMARY KEY, study_id INTEGER NOT NULL, week_no INTEGER NOT NULL,
 initial_note TEXT NOT NULL, revised_note TEXT NOT NULL DEFAULT '',
 next_member INTEGER NOT NULL DEFAULT 1, unanswered TEXT NOT NULL DEFAULT '[]',
 minutes TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'active'
);
CREATE TABLE IF NOT EXISTS messages (
 id INTEGER PRIMARY KEY, session_id INTEGER NOT NULL, role TEXT NOT NULL,
 member_no INTEGER, body TEXT NOT NULL, page_no INTEGER, pdf_version INTEGER
);
CREATE TABLE IF NOT EXISTS attachments (
 id INTEGER PRIMARY KEY, study_id INTEGER NOT NULL, session_id INTEGER NOT NULL,
 name TEXT NOT NULL, size INTEGER NOT NULL, body TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS attachments_session ON attachments(session_id,id);
CREATE TABLE IF NOT EXISTS review_items (
 id INTEGER PRIMARY KEY, study_id INTEGER NOT NULL, question TEXT NOT NULL,
 source_week INTEGER NOT NULL, status TEXT NOT NULL DEFAULT 'open',
 resolved_at TEXT, UNIQUE(study_id,question)
);
CREATE INDEX IF NOT EXISTS review_items_study_status ON review_items(study_id,status);
CREATE INDEX IF NOT EXISTS messages_session ON messages(session_id,id);
CREATE INDEX IF NOT EXISTS sessions_study ON sessions(study_id,status,week_no);
CREATE TABLE IF NOT EXISTS users (
 id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE COLLATE NOCASE,
 password_hash TEXT NOT NULL, salt TEXT NOT NULL, created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS auth_tokens (
 token TEXT PRIMARY KEY, user_id INTEGER NOT NULL, created_at TEXT NOT NULL
);
"""

# 테이블 생성·컬럼 추가는 DB 파일마다 서버가 켜진 뒤 처음 연결할 때 한 번만 한다.
_migrated: set[str] = set()


@contextmanager
def connect():
    path = os.getenv("DATABASE_PATH", "study_mate.sqlite3")
    db = sqlite3.connect(path, timeout=10)
    db.row_factory = sqlite3.Row
    db.execute("PRAGMA foreign_keys=ON")
    if path not in _migrated:
        migrate(db)
        db.commit()
        _migrated.add(path)
    try:
        yield db
        db.commit()
    finally:
        db.close()


def migrate(db):
    db.executescript(SCHEMA)
    study_columns = {row["name"] for row in db.execute("PRAGMA table_info(studies)")}
    if "pinned" not in study_columns:
        db.execute("ALTER TABLE studies ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0")
    if "archived" not in study_columns:
        db.execute("ALTER TABLE studies ADD COLUMN archived INTEGER NOT NULL DEFAULT 0")
    if "pdf_version" not in study_columns:
        db.execute("ALTER TABLE studies ADD COLUMN pdf_version INTEGER NOT NULL DEFAULT 0")
    message_columns = {row["name"] for row in db.execute("PRAGMA table_info(messages)")}
    if "pdf_version" not in message_columns:
        db.execute("ALTER TABLE messages ADD COLUMN pdf_version INTEGER")
    # 첨부 파일, 복습 질문, 발표 평가처럼 말 이외의 정보가 있는 메시지에 쓴다.
    for column, kind in (("attachment_id", "INTEGER"), ("review_id", "INTEGER"), ("data", "TEXT")):
        if column not in message_columns:
            db.execute(f"ALTER TABLE messages ADD COLUMN {column} {kind}")
    # kind='review'는 끝난 스터디에서 복습만 하려고 연 대화다.
    if "kind" not in {row["name"] for row in db.execute("PRAGMA table_info(sessions)")}:
        db.execute("ALTER TABLE sessions ADD COLUMN kind TEXT NOT NULL DEFAULT 'study'")
    # 이번 차례에 이어서 말할 친구들(JSON). 한 명씩 차례로 불러서 만든다.
    if "plan" not in {row["name"] for row in db.execute("PRAGMA table_info(sessions)")}:
        db.execute("ALTER TABLE sessions ADD COLUMN plan TEXT NOT NULL DEFAULT '[]'")
    if "pdf_size" not in study_columns:
        db.execute("ALTER TABLE studies ADD COLUMN pdf_size INTEGER NOT NULL DEFAULT 0")
    # 사용자가 친구마다 적어 둔 성격·말투 조정 한두 줄
    if "note" not in {row["name"] for row in db.execute("PRAGMA table_info(members)")}:
        db.execute("ALTER TABLE members ADD COLUMN note TEXT NOT NULL DEFAULT ''")
    week_columns = {row["name"] for row in db.execute("PRAGMA table_info(weeks)")}
    if "progress_percent" not in week_columns:
        db.execute("ALTER TABLE weeks ADD COLUMN progress_percent INTEGER NOT NULL DEFAULT 0")
    if "remaining_scope" not in week_columns:
        db.execute("ALTER TABLE weeks ADD COLUMN remaining_scope TEXT NOT NULL DEFAULT ''")
    if "include_previous_questions" not in week_columns:
        db.execute("ALTER TABLE weeks ADD COLUMN include_previous_questions INTEGER NOT NULL DEFAULT 1")
    if db.execute("SELECT COUNT(*) FROM review_items").fetchone()[0] == 0:
        for session in db.execute("SELECT study_id,week_no,unanswered FROM sessions WHERE status='finished'"):
            for question in loads(session["unanswered"]):
                if isinstance(question, str) and question.strip():
                    db.execute("INSERT OR IGNORE INTO review_items(study_id,question,source_week) VALUES(?,?,?)",
                               (session["study_id"], question.strip(), session["week_no"]))
    if "user_id" not in study_columns:
        db.execute("ALTER TABLE studies ADD COLUMN user_id INTEGER")
    # 프로필 모양: "아이콘:색번호" (예: "book:3"). 비어 있으면 앱이 기본 모양을 쓴다.
    # 사용자가 채팅으로 정한 진행 방식(JSON 문자열 배열). 모든 스터디원 프롬프트에 들어간다.
    if "preferences" not in study_columns:
        db.execute("ALTER TABLE studies ADD COLUMN preferences TEXT NOT NULL DEFAULT '[]'")
    if "avatar" not in study_columns:
        db.execute("ALTER TABLE studies ADD COLUMN avatar TEXT NOT NULL DEFAULT ''")
    # 예전 기본 이름(지식이 등)을 그대로 쓰는 AI 친구는 새 기본 이름으로 바꾼다. 직접 바꾼 이름은 그대로 둔다.
    for old, new in (("지식이", "서윤"), ("사례이", "도현"), ("융합이", "하은"), ("탐구이", "지호")):
        db.execute("UPDATE members SET name=? WHERE name=?", (new, old))
    for table in ("members", "users"):
        if "avatar" not in {row["name"] for row in db.execute(f"PRAGMA table_info({table})")}:
            db.execute(f"ALTER TABLE {table} ADD COLUMN avatar TEXT NOT NULL DEFAULT ''")
    # 예전에 그대로 저장한 로그인 토큰은 해시로 바꾼다(로그인은 유지된다).
    for row in db.execute("SELECT token FROM auth_tokens WHERE length(token)!=64").fetchall():
        db.execute("UPDATE auth_tokens SET token=? WHERE token=?",
                   (hashlib.sha256(row["token"].encode()).hexdigest(), row["token"]))
    db.execute("CREATE INDEX IF NOT EXISTS studies_user ON studies(user_id,archived)")


def obj(row):
    return dict(row) if row else None


def dumps(value):
    return json.dumps(value, ensure_ascii=False)


def loads(value):
    return json.loads(value or "[]")
