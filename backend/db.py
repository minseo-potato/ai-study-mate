import json
import os
import sqlite3
from contextlib import contextmanager


SCHEMA = """
CREATE TABLE IF NOT EXISTS studies (
 id INTEGER PRIMARY KEY, title TEXT NOT NULL, goal TEXT NOT NULL,
 start_date TEXT NOT NULL, weeks INTEGER NOT NULL, hours_per_week REAL NOT NULL,
 member_count INTEGER NOT NULL, rules TEXT NOT NULL, pdf_name TEXT NOT NULL,
 pinned INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS pages (
 study_id INTEGER NOT NULL, page_no INTEGER NOT NULL, body TEXT NOT NULL,
 PRIMARY KEY(study_id,page_no)
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
 member_no INTEGER, body TEXT NOT NULL, page_no INTEGER
);
"""


@contextmanager
def connect():
    db = sqlite3.connect(os.getenv("DATABASE_PATH", "study_mate.sqlite3"))
    db.row_factory = sqlite3.Row
    db.execute("PRAGMA foreign_keys=ON")
    db.executescript(SCHEMA)
    study_columns = {row["name"] for row in db.execute("PRAGMA table_info(studies)")}
    if "pinned" not in study_columns:
        db.execute("ALTER TABLE studies ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0")
    week_columns = {row["name"] for row in db.execute("PRAGMA table_info(weeks)")}
    if "progress_percent" not in week_columns:
        db.execute("ALTER TABLE weeks ADD COLUMN progress_percent INTEGER NOT NULL DEFAULT 0")
    if "remaining_scope" not in week_columns:
        db.execute("ALTER TABLE weeks ADD COLUMN remaining_scope TEXT NOT NULL DEFAULT ''")
    if "include_previous_questions" not in week_columns:
        db.execute("ALTER TABLE weeks ADD COLUMN include_previous_questions INTEGER NOT NULL DEFAULT 1")
    try:
        yield db
        db.commit()
    finally:
        db.close()


def obj(row):
    return dict(row) if row else None


def dumps(value):
    return json.dumps(value, ensure_ascii=False)


def loads(value):
    return json.loads(value or "[]")
