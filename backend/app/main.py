from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.api import api_router

app = FastAPI(
    title="SketchDuel API",
    description="Real-time AI-judged drawing battle game",
    version="1.0.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:51220",   # Flutter web dev port
        "http://localhost:3000",
        "http://localhost:8080",
        "http://127.0.0.1:8080",
        "*",                        # allows all during development
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(api_router, prefix="/api/v1")

@app.get("/")
async def root():
    return {"message": "SketchDuel API is running"}

@app.get("/health")
async def health():
    return {"status": "ok"}