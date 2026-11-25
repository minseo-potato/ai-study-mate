"""AI 스터디메이트 local demo API. Start with: uvicorn main:app --reload"""
import os

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from ai import demo_mode
from common import MAX_FILE
from limits import SafetyMiddleware
from routes import account, records, sessions, studies

# 여러 사람에게 공개할 때는 DOCS=0으로 API 문서를 끄고, ALLOWED_ORIGINS에 앱 주소를 적는다.
docs = os.getenv("DOCS", "1") != "0"
app = FastAPI(title="AI 스터디메이트", docs_url="/docs" if docs else None, redoc_url=None,
              openapi_url="/openapi.json" if docs else None)
origins = [x.strip() for x in os.getenv("ALLOWED_ORIGINS", "").split(",") if x.strip()]
app.add_middleware(SafetyMiddleware, file_limit=MAX_FILE + 2_000_000)
# 로그인 헤더 때문에 생기는 브라우저 사전 확인(OPTIONS) 결과를 하루 동안 재사용하게 한다.
app.add_middleware(CORSMiddleware, allow_origins=origins,
                   allow_origin_regex=None if origins else r"https?://(localhost|127\.0\.0\.1|\[::1\])(:\d+)?",
                   allow_methods=["GET", "POST", "PUT", "DELETE"], allow_headers=["Authorization", "Content-Type"], max_age=86400)
for module in (account, studies, sessions, records):
    app.include_router(module.router)


@app.get("/health")
def health():
    return {"ok": True, "demo_mode": demo_mode(),
            "ai_ready": bool(os.getenv("OPENAI_API_KEY")) and not demo_mode()}
