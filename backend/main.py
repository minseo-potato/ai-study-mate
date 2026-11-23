"""AI 스터디메이트 local demo API. Start with: uvicorn main:app --reload"""
import os

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from ai import demo_mode
from routes import account, records, sessions, studies

app = FastAPI(title="AI 스터디메이트")
# 로그인 헤더 때문에 생기는 브라우저 사전 확인(OPTIONS) 결과를 하루 동안 재사용하게 한다.
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"], max_age=86400)
for module in (account, studies, sessions, records):
    app.include_router(module.router)


@app.get("/health")
def health():
    return {"ok": True, "demo_mode": demo_mode(),
            "ai_ready": bool(os.getenv("OPENAI_API_KEY")) and not demo_mode()}
