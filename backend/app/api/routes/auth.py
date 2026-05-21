from fastapi import APIRouter, HTTPException
from app.models.user import UserRegister, UserLogin, UserResponse
from app.core.supabase import supabase

router = APIRouter(prefix="/auth", tags=["auth"])

@router.post("/register")
async def register(user: UserRegister):
    try:
        result = supabase.auth.sign_up({
            "email": user.email,
            "password": user.password,
        })

        if result.user is None:
            raise HTTPException(status_code=400, detail="Registration failed")

        # Create profile
        supabase.table("profiles").insert({
            "id": result.user.id,
            "username": user.username,
            "email": user.email,
            "total_wins": 0,
            "total_games": 0,
            "best_score": 0.0
        }).execute()

        return {
            "message": "Registered successfully. Check email to confirm.",
            "user_id": result.user.id
        }

    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@router.post("/login")
async def login(user: UserLogin):
    try:
        result = supabase.auth.sign_in_with_password({
            "email": user.email,
            "password": user.password,
        })

        if result.user is None:
            raise HTTPException(status_code=401, detail="Invalid credentials")

        profile = supabase.table("profiles")\
            .select("*").eq("id", result.user.id).execute()

        return {
            "access_token": result.session.access_token,
            "token_type": "bearer",
            "user": profile.data[0] if profile.data else {}
        }

    except Exception as e:
        raise HTTPException(status_code=401, detail=str(e))

@router.get("/profile/{user_id}")
async def get_profile(user_id: str):
    result = supabase.table("profiles").select("*").eq("id", user_id).execute()
    if not result.data:
        raise HTTPException(status_code=404, detail="Profile not found")
    return result.data[0]