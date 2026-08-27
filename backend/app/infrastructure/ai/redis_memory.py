import json
from uuid import UUID

from redis.asyncio import Redis

from app.domain.models import ConversationMessage

CONTEXT_MAX_MESSAGES = 16
CONTEXT_TTL_SECONDS = 7 * 24 * 3600


class RedisConversationMemory:
    """Manages short-term conversation context in Redis for the copilot."""

    def __init__(self, redis: Redis) -> None:
        self._redis = redis

    def _key(self, researcher_id: UUID, conversation_id: UUID) -> str:
        return f"bioma:copilot:context:{researcher_id}:{conversation_id}"

    async def get_recent_messages(
        self, researcher_id: UUID, conversation_id: UUID, limit: int = CONTEXT_MAX_MESSAGES
    ) -> list[ConversationMessage]:
        key = self._key(researcher_id, conversation_id)
        raw_items = await self._redis.lrange(key, -limit, -1)
        messages: list[ConversationMessage] = []
        for raw in raw_items:
            try:
                data = json.loads(raw.decode("utf-8") if isinstance(raw, bytes) else raw)
                messages.append(ConversationMessage(role=data["role"], content=data["content"]))
            except (json.JSONDecodeError, KeyError):
                continue
        return messages

    async def append_turn(
        self,
        researcher_id: UUID,
        conversation_id: UUID,
        user_message: str,
        assistant_message: str,
        max_messages: int = CONTEXT_MAX_MESSAGES,
    ) -> None:
        key = self._key(researcher_id, conversation_id)
        u_json = json.dumps({"role": "user", "content": user_message})
        a_json = json.dumps({"role": "assistant", "content": assistant_message})
        async with self._redis.pipeline(transaction=True) as pipe:
            pipe.rpush(key, u_json, a_json)
            pipe.ltrim(key, -max_messages, -1)
            pipe.expire(key, CONTEXT_TTL_SECONDS)
            await pipe.execute()

    async def clear_conversation(self, researcher_id: UUID, conversation_id: UUID) -> None:
        key = self._key(researcher_id, conversation_id)
        await self._redis.delete(key)