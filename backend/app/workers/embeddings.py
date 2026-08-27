import argparse
import asyncio
import logging

from app.infrastructure.ai.factory import build_ai_gateway
from app.infrastructure.config import get_settings
from app.infrastructure.db.database import Database
from app.infrastructure.db.repositories import PostgresSightingRepository

logger = logging.getLogger(__name__)


class EmbeddingWorker:
    def __init__(self, database: Database) -> None:
        self._database = database
        self._settings = get_settings()
        self._embeddings, _ = build_ai_gateway(self._settings)

    async def run_once(self) -> bool:
        async with self._database.connection() as connection:
            repository = PostgresSightingRepository(connection)
            async with connection.transaction():
                job = await repository.claim_embedding_job()
        if job is None:
            return False
        sighting_id, field_notes, attempts = job
        try:
            embedding = await self._embeddings.embed_document(field_notes)
            async with self._database.connection() as connection:
                await PostgresSightingRepository(connection).store_embedding(
                    sighting_id, embedding, self._embeddings.embedding_model_name
                )
            logger.info("embedding_ready sighting_id=%s attempts=%s", sighting_id, attempts)
        except Exception as error:
            async with self._database.connection() as connection:
                await PostgresSightingRepository(connection).mark_embedding_failed(
                    sighting_id, type(error).__name__
                )
            logger.exception("embedding_failed sighting_id=%s attempts=%s", sighting_id, attempts)
        return True

    async def run_forever(self) -> None:
        poll_seconds = self._settings.embedding_worker_poll_seconds
        while True:
            processed = await self.run_once()
            if not processed:
                await asyncio.sleep(poll_seconds)


async def main() -> None:
    database = Database(get_settings().database_url)
    await database.connect()
    try:
        parser = argparse.ArgumentParser(description="Process Bioma embedding jobs")
        parser.add_argument("--once", action="store_true", help="process at most one job")
        options = parser.parse_args()
        worker = EmbeddingWorker(database)
        if options.once:
            processed = await worker.run_once()
            print(f"embedding_worker_once processed={processed}", flush=True)
        else:
            await worker.run_forever()
    finally:
        await database.close()


if __name__ == "__main__":
    asyncio.run(main())
