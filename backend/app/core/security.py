import hashlib
import threading
import time
from dataclasses import dataclass
from typing import Dict, Optional, Tuple

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.core.supabase import supabase_admin

bearer_scheme = HTTPBearer(auto_error=False)

# Tokens that Supabase confirmed recently are remembered briefly so a burst of requests
# (for example live-preview calls while drawing) doesn't hit Supabase Auth every time.
_TOKEN_TTL_SECONDS = 30.0
_CACHE_MAX_ENTRIES = 2000
_token_cache: Dict[str, Tuple[float, "CurrentUser"]] = {}
_cache_lock = threading.Lock()


@dataclass(frozen=True)
class CurrentUser:
    id: str
    email: Optional[str] = None


def _unauthorized(detail: str = "Not authenticated") -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail=detail,
        headers={"WWW-Authenticate": "Bearer"},
    )


def _cache_key(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def _cache_get(token: str) -> Optional[CurrentUser]:
    key = _cache_key(token)
    with _cache_lock:
        entry = _token_cache.get(key)
        if entry is None:
            return None
        expires_at, user = entry
        if expires_at < time.monotonic():
            _token_cache.pop(key, None)
            return None
        return user


def _cache_put(token: str, user: CurrentUser) -> None:
    with _cache_lock:
        if len(_token_cache) >= _CACHE_MAX_ENTRIES:
            now = time.monotonic()
            for key in [k for k, (exp, _) in _token_cache.items() if exp < now]:
                _token_cache.pop(key, None)
            if len(_token_cache) >= _CACHE_MAX_ENTRIES:
                _token_cache.clear()
        _token_cache[_cache_key(token)] = (time.monotonic() + _TOKEN_TTL_SECONDS, user)


def clear_token_cache() -> None:
    with _cache_lock:
        _token_cache.clear()


def get_current_user(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(bearer_scheme),
) -> CurrentUser:
    """Validate the Supabase access token and return the caller.

    The user id always comes from the verified token, never from the request body or query.
    (Declared as a plain `def` so FastAPI runs it in a worker thread; the Supabase call blocks.)
    """
    if credentials is None or not credentials.credentials:
        raise _unauthorized()

    token = credentials.credentials

    cached = _cache_get(token)
    if cached is not None:
        return cached

    try:
        response = supabase_admin.auth.get_user(token)
    except Exception:
        raise _unauthorized("Invalid or expired token")

    user = getattr(response, "user", None)
    if user is None or not getattr(user, "id", None):
        raise _unauthorized("Invalid or expired token")

    current = CurrentUser(id=str(user.id), email=getattr(user, "email", None))
    _cache_put(token, current)
    return current