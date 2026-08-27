from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from uuid import UUID

import asyncpg


class Database:
    def __init__(self, url: str) -> None:
        self._url = url
        self._pool: asyncpg.Pool | None = None

    async def connect(self) -> None:
        self._pool = await asyncpg.create_pool(
            self._url, min_size=1, max_size=10, command_timeout=20
        )

    async def close(self) -> None:
        if self._pool is not None:
            await self._pool.close()
            self._pool = None

    async def is_ready(self) -> bool:
        try:
            return await self.pool.fetchval("SELECT 1") == 1
        except (asyncpg.PostgresError, OSError):
            return False

    @property
    def pool(self) -> asyncpg.Pool:
        if self._pool is None:
            raise RuntimeError("database pool is not initialized")
        return self._pool

    @asynccontextmanager
    async def connection(self) -> AsyncIterator[asyncpg.Connection]:
        async with self.pool.acquire() as connection:
            yield connection

    @asynccontextmanager
    async def actor_transaction(self, actor_id: UUID) -> AsyncIterator[asyncpg.Connection]:
        async with self.pool.acquire() as connection, connection.transaction():
            # local=true prevents actor identity from leaking to a pooled connection.
            await connection.execute(
                "SELECT set_config('app.current_user_id', $1, true)", str(actor_id)
            )
            yield connection
