"""로그인·회원가입과 마이페이지, 모든 스터디 기록을 한 번에 보는 API."""
import json
import secrets
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field

from ai import demo_mode
import guard
import limits
from auth import check_password, current_user, hash_password, issue_token, needs_rehash, token_hash
from common import AVATAR_PATTERN
from db import connect

router = APIRouter()


MIN_PASSWORD = 8
_DUMMY = hash_password("x", "x")


def client_ip(request: Request) -> str:
    return request.client.host if request.client else "?"


class Credentials(BaseModel):
    name: str = Field(min_length=2, max_length=20)
    password: str = Field(min_length=4, max_length=64)


def account_payload(db, user_id: int) -> dict:
    user = db.execute("SELECT id,name,avatar,created_at FROM users WHERE id=?", (user_id,)).fetchone()
    stats = db.execute(
        "SELECT COUNT(*) AS studies,"
        " COALESCE(SUM((SELECT COUNT(*) FROM weeks w WHERE w.study_id=st.id AND w.status='complete')),0) AS completed_weeks,"
        " COALESCE(SUM((SELECT COUNT(*) FROM review_items r WHERE r.study_id=st.id AND r.status='open')),0) AS open_reviews"
        " FROM studies st WHERE st.user_id=?", (user_id,)).fetchone()
    talk = db.execute(
        "SELECT SUM(m.role='user') AS users, SUM(m.role='assistant_plan') AS plans FROM messages m"
        " JOIN sessions s ON s.id=m.session_id JOIN studies st ON st.id=s.study_id WHERE st.user_id=?",
        (user_id,)).fetchone()
    return {"user": dict(user), "demo_mode": demo_mode(), "stats": {
        **dict(stats), "answers": max(0, (talk["users"] or 0) - (talk["plans"] or 0))}}


@router.post("/auth/signup")
def signup(body: Credentials, request: Request):
    limits.hit(("signup", client_ip(request)), 30, 3600, "가입을 너무 자주 시도했어요. 잠시 뒤에 다시 해 주세요.")
    name = guard.clean_label(body.name, 20)
    if len(body.password) < MIN_PASSWORD:
        raise HTTPException(400, f"비밀번호는 {MIN_PASSWORD}자 이상이에요.")
    if guard.is_trick(name):
        raise HTTPException(400, "다른 이름을 써 주세요.")
    if len(name) < 2:
        raise HTTPException(400, "이름은 2자 이상이에요.")
    with connect() as db:
        if db.execute("SELECT 1 FROM users WHERE name=?", (name,)).fetchone():
            raise HTTPException(409, "이미 쓰고 있는 이름이에요.")
        salt = secrets.token_hex(16)
        user_id = db.execute("INSERT INTO users(name,password_hash,salt,created_at) VALUES(?,?,?,?)",
                             (name, hash_password(body.password, salt), salt,
                              datetime.now(timezone.utc).isoformat())).lastrowid
        if db.execute("SELECT COUNT(*) FROM users").fetchone()[0] == 1:
            # 로그인 기능이 생기기 전에 만든 스터디는 첫 사용자에게 넘긴다.
            db.execute("UPDATE studies SET user_id=? WHERE user_id IS NULL", (user_id,))
        return {"token": issue_token(db, user_id), **account_payload(db, user_id)}


@router.post("/auth/login")
def login(body: Credentials, request: Request):
    name = body.name.strip()
    key = ("login", client_ip(request), name.lower())
    wait = "로그인을 여러 번 틀렸어요. 몇 분 뒤에 다시 해 주세요."
    limits.hit(key, 8, 300, wait)
    limits.hit(("login-ip", client_ip(request)), 60, 300, wait)
    with connect() as db:
        user = db.execute("SELECT * FROM users WHERE name=?", (name,)).fetchone()
        # 없는 이름도 같은 시간이 걸리게 해서 가입 여부가 드러나지 않게 한다.
        ok = check_password(body.password, user["salt"] if user else "x", user["password_hash"] if user else _DUMMY)
        if not user or not ok:
            raise HTTPException(401, "이름 또는 비밀번호가 맞지 않아요.")
        limits.clear(key)
        if needs_rehash(user["password_hash"]):
            db.execute("UPDATE users SET password_hash=? WHERE id=?", (hash_password(body.password, user["salt"]), user["id"]))
        return {"token": issue_token(db, user["id"]), **account_payload(db, user["id"])}


@router.post("/auth/logout")
def logout(request: Request, user: dict = Depends(current_user)):
    token = request.headers.get("authorization", "").removeprefix("Bearer ").strip()
    with connect() as db:
        db.execute("DELETE FROM auth_tokens WHERE token=?", (token_hash(token),))
    return {"ok": True}


@router.get("/me")
def me(user: dict = Depends(current_user)):
    with connect() as db:
        return account_payload(db, user["id"])


class Profile(BaseModel):
    name: str | None = Field(default=None, min_length=2, max_length=20)
    avatar: str | None = Field(default=None, pattern=AVATAR_PATTERN)


@router.put("/me")
def edit_me(body: Profile, user: dict = Depends(current_user)):
    with connect() as db:
        if body.name is not None:
            name = guard.clean_label(body.name, 20)
            if len(name) < 2 or guard.is_trick(name):
                raise HTTPException(400, "다른 이름을 써 주세요.")
            if db.execute("SELECT 1 FROM users WHERE name=? AND id!=?", (name, user["id"])).fetchone():
                raise HTTPException(409, "이미 쓰고 있는 이름이에요.")
            db.execute("UPDATE users SET name=? WHERE id=?", (name, user["id"]))
        if body.avatar is not None:
            db.execute("UPDATE users SET avatar=? WHERE id=?", (body.avatar, user["id"]))
        return account_payload(db, user["id"])


@router.get("/me/records")
def my_records(user: dict = Depends(current_user)):
    """모든 스터디의 남은 복습과 주차별 정리를 스터디·주차 순서로 한 번에 돌려준다."""
    with connect() as db:
        reviews = [dict(r) for r in db.execute(
            "SELECT r.id,r.study_id,st.title AS study_title,r.question,r.source_week FROM review_items r"
            " JOIN studies st ON st.id=r.study_id WHERE st.user_id=? AND r.status='open'"
            " ORDER BY r.study_id DESC,r.source_week,r.id", (user["id"],))]
        weeks = []
        for row in db.execute(
                "SELECT s.id AS session_id,s.study_id,st.title AS study_title,s.week_no,w.title,s.minutes,s.kind"
                " FROM sessions s JOIN studies st ON st.id=s.study_id"
                " JOIN weeks w ON w.study_id=s.study_id AND w.week_no=s.week_no"
                " WHERE st.user_id=? AND s.status='finished' AND s.kind!='review' ORDER BY s.week_no,s.id", (user["id"],)):
            minutes = json.loads(row["minutes"]) if row["minutes"] else {}
            weeks.append({k: row[k] for k in ("session_id", "study_id", "study_title", "week_no", "title", "kind")}
                         | ({"title": "최종 발표"} if row["kind"] == "presentation" else {})
                         | {"summary": minutes.get("summary", ""), "keywords": minutes.get("keywords", []),
                            "stats": minutes.get("stats", {}), "learned": minutes.get("learned", [])[:2],
                            "evaluated": bool(minutes.get("evaluation"))})
        studies = [dict(r) for r in db.execute(
            "SELECT st.id,st.title,st.avatar,st.weeks,"
            "(SELECT COUNT(*) FROM weeks w WHERE w.study_id=st.id AND w.status='complete') AS completed"
            " FROM studies st WHERE st.user_id=? ORDER BY st.archived,st.pinned DESC,st.id DESC", (user["id"],))]
        return {"studies": studies, "reviews": reviews, "weeks": weeks}
