"""AI 스터디메이트 local demo API. Start with: uvicorn main:app --reload"""
import os

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from ai import demo_mode
from routes import records, sessions, studies

app = FastAPI(title="AI 스터디메이트")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])
for module in (studies, sessions, records):
    app.include_router(module.router)


@app.get("/health")
def health():
    return {"ok": True, "demo_mode": demo_mode(),
            "ai_ready": bool(os.getenv("OPENAI_API_KEY")) and not demo_mode()}
