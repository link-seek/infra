"""Custom auth: accept any API key (pass-through proxy mode)."""
from litellm.proxy.auth.user_api_key_auth import UserAPIKeyAuth

async def always_allow(request, api_key):
    """Accept any non-empty API key (pass-through proxy mode); empty key -> 401."""
    # user_role 必须小写 internal_user（上游 pin 的 LiteLLM 版枚举值，大写 INTERNAL_USER 会被 pydantic 拒收 → 全员 401）
    if not api_key:
        raise Exception("Missing API key")
    return UserAPIKeyAuth(
        api_key=api_key,
        user_role="internal_user",
    )
