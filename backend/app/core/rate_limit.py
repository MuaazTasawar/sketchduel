import threading
import time
from collections import deque
from typing import Callable, Deque, Dict, Optional

from fastapi import Depends, HTTPException, Request, status

from app.core.config import settings
from app.core.security import CurrentUser, get_current_user


class RateLimiter:
    """In-memory sliding-window limiter (per process).

    Good enough for a single Render instance. If you ever run several instances, move the
    counters to Redis or Postgres.
    """

    def __init__(
        self,
        limit: int,
        window_seconds: float = 60.0,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self.limit = limit
        self.window = window_seconds
        self._clock = clock
        self._hits: Dict[str, Deque[float]] = {}
        self._lock = threading.Lock()

    def check(self, key: str) -> float:
        """Record a hit. Returns 0 if allowed, otherwise the seconds until a slot frees up."""
        now = self._clock()
        with self._lock:
            hits = self._hits.setdefault(key, deque())
            while hits and now - hits[0] >= self.window:
                hits.popleft()

            if len(hits) >= self.limit:
                return max(self.window - (now - hits[0]), 0.1)

            hits.append(now)

            if len(self._hits) > 10_000:
                self._prune(now)
            return 0.0

    def _prune(self, now: float) -> None:
        for key in [k for k, h in self._hits.items() if not h or now - h[-1] >= self.window]:
            self._hits.pop(key, None)


def client_ip(request: Request) -> str:
    """Best-effort client IP (Render puts the real address in X-Forwarded-For)."""
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        return forwarded.split(",")[0].strip()
    return request.client.host if request.client else "unknown"


def _reject(retry_after: float) -> HTTPException:
    seconds = max(int(retry_after) + 1, 1)
    return HTTPException(
        status_code=status.HTTP_429_TOO_MANY_REQUESTS,
        detail="Too many requests. Please slow down.",
        headers={"Retry-After": str(seconds)},
    )


def limit_by_ip(bucket: str, per_minute: Optional[int] = None):
    """Dependency for unauthenticated routes (register, login)."""
    limiter = RateLimiter(per_minute or settings.RATE_LIMIT_PER_MINUTE)

    def dependency(request: Request) -> None:
        retry_after = limiter.check(f"{bucket}:{client_ip(request)}")
        if retry_after:
            raise _reject(retry_after)

    return dependency


def limit_by_user(bucket: str, per_minute: Optional[int] = None):
    """Dependency for authenticated routes. Returns the verified user."""
    limiter = RateLimiter(per_minute or settings.RATE_LIMIT_PER_MINUTE)

    def dependency(user: CurrentUser = Depends(get_current_user)) -> CurrentUser:
        retry_after = limiter.check(f"{bucket}:{user.id}")
        if retry_after:
            raise _reject(retry_after)
        return user

    return dependency