import logging
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from gotrue.errors import AuthApiError

from app.core.rate_limit import limit_by_ip
from app.core.security import CurrentUser, get_current_user
from app.core.supabase import new_anon_client, supabase_admin
from app.models.user import (
    LoginResponse,
    PublicProfile,
    RegisterResponse,
    UserLogin,
    UserRegister,
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/auth", tags=["auth"])

PUBLIC_PROFILE_COLUMNS = "id,username,total_wins,total_games,best_score"


def _escape_like(value: str) -> str:
    """Escape LIKE wildcards so '_' in a username is matched literally."""
    return value.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")


def _username_taken(username: str) -> bool:
    result = (
        supabase_admin.table("profiles")
        .select("id")
        .ilike("username", _escape_like(username))
        .limit(1)
        .execute()
    )
    return bool(result.data)


def _auth_message(error: Exception) -> str:
    return getattr(error, "message", None) or str(error)


@router.post(
    "/register",
    response_model=RegisterResponse,
    dependencies=[Depends(limit_by_ip("register", 5))],
)
def register(user: UserRegister):
    if _username_taken(user.username):
        raise HTTPException(status.HTTP_409_CONFLICT, "Username is already taken")

    # A fresh client per call: supabase-py clients keep the session of whoever signed in last.
    try:
        result = new_anon_client().auth.sign_up(
            {"email": user.email, "password": user.password}
        )
    except AuthApiError as error:
        message = _auth_message(error)
        if "already" in message.lower():
            raise HTTPException(status.HTTP_409_CONFLICT, "Email is already registered")
        raise HTTPException(status.HTTP_400_BAD_REQUEST, message)
    except Exception:
        logger.exception("sign_up failed")
        raise HTTPException(status.HTTP_502_BAD_GATEWAY, "Authentication service unavailable")

    new_user = result.user
    if new_user is None:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Registration failed")

    # With e-mail confirmation on, Supabase hides duplicates by returning a user with no identities.
    identities = getattr(new_user, "identities", None)
    if identities is not None and len(identities) == 0:
        raise HTTPException(status.HTTP_409_CONFLICT, "Email is already registered")

    try:
        supabase_admin.table("profiles").insert(
            {
                "id": new_user.id,
                "username": user.username,
                "email": user.email,
                "total_wins": 0,
                "total_games": 0,
                "best_score": 0.0,
            }
        ).execute()
    except Exception:
        logger.exception("profile insert failed; rolling back auth user %s", new_user.id)
        try:
            supabase_admin.auth.admin.delete_user(new_user.id)
        except Exception:
            logger.exception("could not roll back auth user %s", new_user.id)
        raise HTTPException(status.HTTP_409_CONFLICT, "Could not create the profile (username taken?)")

    confirmation_required = result.session is None
    message = "Registered successfully."
    if confirmation_required:
        message += " Check your email to confirm your account."

    return RegisterResponse(
        message=message,
        user_id=str(new_user.id),
        email_confirmation_required=confirmation_required,
    )


@router.post(
    "/login",
    response_model=LoginResponse,
    dependencies=[Depends(limit_by_ip("login", 10))],
)
def login(user: UserLogin):
    try:
        result = new_anon_client().auth.sign_in_with_password(
            {"email": user.email, "password": user.password}
        )
    except AuthApiError as error:
        if "not confirmed" in _auth_message(error).lower():
            raise HTTPException(status.HTTP_403_FORBIDDEN, "Email not confirmed")
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid email or password")
    except Exception:
        logger.exception("sign_in failed")
        raise HTTPException(status.HTTP_502_BAD_GATEWAY, "Authentication service unavailable")

    if result.user is None or result.session is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid email or password")

    profile = (
        supabase_admin.table("profiles").select("*").eq("id", result.user.id).limit(1).execute()
    )

    return LoginResponse(
        access_token=result.session.access_token,
        user=profile.data[0] if profile.data else {},
    )


@router.get("/profile/{user_id}", response_model=PublicProfile)
def get_profile(user_id: UUID, _: CurrentUser = Depends(get_current_user)):
    result = (
        supabase_admin.table("profiles")
        .select(PUBLIC_PROFILE_COLUMNS)
        .eq("id", str(user_id))
        .limit(1)
        .execute()
    )
    if not result.data:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Profile not found")
    return result.data[0]