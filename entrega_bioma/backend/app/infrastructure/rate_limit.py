import hashlib
import hmac
from dataclasses import dataclass

from redis.asyncio import Redis

RATE_LIMIT_SCRIPT = """
local count = redis.call('INCR', KEYS[1])
if count == 1 then
  redis.call('EXPIRE', KEYS[1], ARGV[1])
end
local remaining = redis.call('TTL', KEYS[1])
return {count, remaining}
"""


@dataclass(frozen=True, slots=True)
class RateLimitDecision:
    allowed: bool
    retry_after: int


class RedisRateLimiter:
    def __init__(self, redis: Redis) -> None:
        self._redis = redis

    @property
    def client(self) -> Redis:
        """Shared Redis client used by infrastructure concerns in this process."""
        return self._redis

    @classmethod
    def from_url(cls, url: str) -> "RedisRateLimiter":
        return cls(Redis.from_url(url, decode_responses=False))

    async def ping(self) -> bool:
        return bool(await self._redis.ping())

    async def check(self, *, key: str, limit: int, window_seconds: int) -> RateLimitDecision:
        count, ttl = await self._redis.eval(
            RATE_LIMIT_SCRIPT, 1, key, window_seconds
        )
        return RateLimitDecision(
            allowed=int(count) <= limit,
            retry_after=max(int(ttl), 1),
        )

    async def close(self) -> None:
        await self._redis.aclose()


def private_fingerprint(secret: str, value: str) -> str:
    return hmac.new(secret.encode(), value.encode(), hashlib.sha256).hexdigest()
