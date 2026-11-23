"""간단한 로그인: 이름 + 비밀번호, 토큰은 Authorization: Bearer 헤더로 보낸다."""
import hashlib
import hmac
import secrets
from datetime import datetime, timezone

from fastapi import HTTPException, Request

from db import connect


def hash_password(password: str, salt: str) -> str:
    return hashlib.pbkdf2_hmac("sha256", password.encode(), salt.encode(), 120_000).hex()


def check_password(password: str, salt: str, expected: str) -> bool:
    return hmac.compare_digest(hash_password(password, salt), expected)


def issue_token(db, user_id: int) -> str:
    token = secrets.token_urlsafe(32)
    db.execute("INSERT INTO auth_tokens(token,user_id,created_at) VALUES(?,?,?)",
               (token, user_id, datetime.now(timezone.utc).isoformat()))
    return token


def current_user(request: Request) -> dict:
    """로그인한 사용자를 찾고, 주소에 있는 스터디·세션이 그 사용자 것인지 함께 확인한다."""
    token = request.headers.get("authorization", "").removeprefix("Bearer ").strip()
    if not token:
        raise HTTPException(401, "로그인이 필요해요.")
    params = request.path_params
    with connect() as db:
        user = db.execute("SELECT u.id,u.name FROM auth_tokens t JOIN users u ON u.id=t.user_id WHERE t.token=?",
                          (token,)).fetchone()
        if not user:
            raise HTTPException(401, "다시 로그인해 주세요.")
        if "study_id" in params and not db.execute(
                "SELECT 1 FROM studies WHERE id=? AND user_id=?", (params["study_id"], user["id"])).fetchone():
            raise HTTPException(404, "대상을 찾을 수 없습니다.")
        if "session_id" in params and not db.execute(
                "SELECT 1 FROM sessions s JOIN studies st ON st.id=s.study_id WHERE s.id=? AND st.user_id=?",
                (params["session_id"], user["id"])).fetchone():
            raise HTTPException(404, "대상을 찾을 수 없습니다.")
    request.state.user = dict(user)
    return dict(user)
