"""요청 횟수와 크기 제한, 보안 헤더. 서버 하나로 돌리는 것을 기준으로 메모리에 센다."""
import threading
import time
from collections import defaultdict, deque

from fastapi import HTTPException

_lock = threading.Lock()
_hits: dict[tuple, deque] = defaultdict(deque)


def hit(key: tuple, limit: int, seconds: int, message: str):
    """seconds 동안 limit번을 넘으면 429를 돌려준다."""
    now = time.monotonic()
    with _lock:
        if len(_hits) > 20_000:  # 오래된 기록이 쌓이지 않게 정리한다.
            for old in [k for k, q in _hits.items() if not q or now - q[-1] > 3600]:
                del _hits[old]
        queue = _hits[key]
        while queue and now - queue[0] > seconds:
            queue.popleft()
        if len(queue) >= limit:
            raise HTTPException(429, message, headers={"Retry-After": str(max(1, int(seconds - (now - queue[0]))))})
        queue.append(now)


def clear(key: tuple):
    with _lock:
        _hits.pop(key, None)


SLOW = "조금만 천천히 보내 주세요."


def limit_user(user_id: int, method: str, path: str):
    """로그인한 사용자의 요청 제한. AI를 부르거나 파일을 읽는 요청은 더 엄하게 센다."""
    if method == "GET":
        return hit(("get", user_id), 300, 60, SLOW)
    if path.endswith(("/files", "/pdf")) or path == "/studies":
        hit(("file", user_id), 30, 600, "파일을 너무 자주 올렸어요. 잠시 뒤에 다시 해 주세요.")
    if path.endswith(("/question", "/answer", "/continue", "/explain", "/evaluate", "/finish", "/file-reply", "-draft")):
        hit(("ai", user_id), 80, 60, SLOW)
        hit(("ai-hour", user_id), 1200, 3600, "이번 시간에 쓸 수 있는 대화를 다 썼어요. 잠시 뒤에 다시 해 주세요.")
    hit(("write", user_id), 120, 60, SLOW)


class TooLarge(Exception):
    pass


class SafetyMiddleware:
    """본문 크기를 제한하고 보안 헤더를 붙인다."""
    JSON_LIMIT = 1_000_000

    def __init__(self, app, file_limit: int):
        self.app, self.file_limit = app, file_limit

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            return await self.app(scope, receive, send)
        headers = dict(scope["headers"])
        multipart = headers.get(b"content-type", b"").startswith(b"multipart/form-data")
        limit = self.file_limit if multipart else self.JSON_LIMIT
        started = over = False

        async def reply(message):
            nonlocal started
            if over and not started and message["type"] == "http.response.start":
                raise TooLarge  # 앱이 다른 오류로 바꿔도 크기 초과로 알린다.
            if message["type"] == "http.response.start":
                started = True
                extra = [(b"x-content-type-options", b"nosniff"), (b"x-frame-options", b"DENY"), (b"referrer-policy", b"no-referrer")]
                if scope["path"] not in ("/docs", "/openapi.json"):
                    extra.append((b"cache-control", b"no-store"))
                    extra.append((b"content-security-policy", b"default-src 'none'; frame-ancestors 'none'"))
                message = {**message, "headers": list(message.get("headers", [])) + extra}
            await send(message)

        async def refuse():
            nonlocal over
            over = False
            await reply({"type": "http.response.start", "status": 413,
                         "headers": [(b"content-type", b"application/json; charset=utf-8")]})
            await reply({"type": "http.response.body", "body": '{"detail":"보낸 내용이 너무 커요."}'.encode()})

        length = headers.get(b"content-length", b"")
        if length.isdigit() and int(length) > limit:
            return await refuse()
        seen = 0

        async def counted():
            nonlocal seen, over
            message = await receive()
            seen += len(message.get("body", b""))
            if seen > limit:
                over = True
                raise TooLarge
            return message
        try:
            await self.app(scope, counted, reply)
        except TooLarge:
            if not started:
                await refuse()
