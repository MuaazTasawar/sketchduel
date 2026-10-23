import logging

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.api import api_router
from app.core.config import settings

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
logger = logging.getLogger("sketchduel")

app = FastAPI(
    title="SketchDuel API",
    description="Real-time AI-judged drawing battle game",
    version="1.1.0",
)

# --- CORS -------------------------------------------------------------------------------------
# Only browsers care about CORS (the Android/iOS apps are unaffected).
# Production: set ALLOWED_ORIGINS to your deployed web origin(s).
# Development: any http://localhost:<port> / http://127.0.0.1:<port> is allowed, because
# `flutter run -d chrome` picks a random port. The API uses Bearer tokens, not cookies,
# so credentials are not allowed.
cors_options = {
    "allow_origins": settings.allowed_origins_list,
    "allow_credentials": False,
    "allow_methods": ["GET", "POST", "OPTIONS"],
    "allow_headers": ["Authorization", "Content-Type"],
}
if not settings.is_production:
    cors_options["allow_origin_regex"] = r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$"

app.add_middleware(CORSMiddleware, **cors_options)


# --- Request size guard -----------------------------------------------------------------------
# Drawings are uploaded as base64 PNG; refuse absurdly large bodies before parsing them.
MAX_BODY_BYTES = settings.MAX_DRAWING_BYTES + 100_000


@app.middleware("http")
async def limit_request_size(request: Request, call_next):
    content_length = request.headers.get("content-length")
    if content_length and content_length.isdigit() and int(content_length) > MAX_BODY_BYTES:
        return JSONResponse(status_code=413, content={"detail": "Request body too large"})
    return await call_next(request)


@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception):
    logger.exception("Unhandled error on %s %s", request.method, request.url.path)
    return JSONResponse(status_code=500, content={"detail": "Internal server error"})


app.include_router(api_router, prefix="/api/v1")


@app.get("/")
async def root():
    return {"message": "SketchDuel API is running"}


@app.get("/health")
async def health():
    return {"status": "ok"}