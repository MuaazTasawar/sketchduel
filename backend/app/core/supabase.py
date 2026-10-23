from supabase import Client, create_client

from app.core.config import settings

# Service-role client.
#
# This is the ONLY client the API uses for database access. It bypasses Row Level Security,
# so every route must authorise the caller itself (see app/core/security.py).
# Never expose this key to the Flutter app.
supabase_admin: Client = create_client(settings.SUPABASE_URL, settings.SUPABASE_SERVICE_KEY)


def new_anon_client() -> Client:
    """Return a brand-new anon-key client.

    supabase-py clients remember the last signed-in session, so a single shared client would
    leak one user's session into other users' requests. Create one per sign-up / sign-in call
    and throw it away afterwards.
    """
    return create_client(settings.SUPABASE_URL, settings.SUPABASE_KEY)


# Legacy alias kept so older imports (`from app.core.supabase import supabase`) keep working.
# It points at the service-role client, matching the rule above.
supabase: Client = supabase_admin