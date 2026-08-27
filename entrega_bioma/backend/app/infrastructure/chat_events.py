"""Internal, content-free events for synchronising chat clients in real time."""

import json
import logging
from dataclasses import dataclass
from uuid import UUID

from redis.asyncio import Redis

logger = logging.getLogger(__name__)

CHAT_EVENTS_CHANNEL = "bioma:chat-events:v1"


@dataclass(frozen=True, slots=True)
class ChatEvent:
    type: str
    channel_id: UUID

    def as_json(self) -> str:
        # Never place chat text, author data, citations or RLS-sensitive data in Redis.
        return json.dumps({"type": self.type, "channel_id": str(self.channel_id)})

    @classmethod
    def from_json(cls, value: bytes | str) -> "ChatEvent | None":
        try:
            raw = json.loads(value)
            event_type = raw["type"]
            channel_id = UUID(raw["channel_id"])
            if event_type not in {"channel.created", "message.created", "message.updated", "message.deleted"}:
                return None
            return cls(type=event_type, channel_id=channel_id)
        except (KeyError, TypeError, ValueError, json.JSONDecodeError):
            return None


class RedisChatEventPublisher:
    """Publishes invalidation events only after the database transaction commits."""

    def __init__(self, redis: Redis) -> None:
        self._redis = redis

    async def publish(self, event_type: str, channel_id: UUID) -> None:
        try:
            await self._redis.publish(CHAT_EVENTS_CHANNEL, ChatEvent(event_type, channel_id).as_json())
        except Exception:  # A reconnecting client refreshes from REST if Redis is unavailable.
            logger.warning("Unable to publish chat realtime event", exc_info=True)
