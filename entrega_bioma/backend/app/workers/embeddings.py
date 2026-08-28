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

    async def run_chat_once(self) -> bool:
        async with self._database.connection() as connection, connection.transaction():
            row = await connection.fetchrow("SELECT * FROM bio_fn_claim_chat_embedding_job()")
        if row is None:
            return False
        try:
            embedding = await self._embeddings.embed_document(row["message_text"])
            async with self._database.connection() as connection:
                await connection.execute(
                    "SELECT bio_fn_store_chat_message_embedding($1, $2::vector, $3)",
                    row["message_id"], str(list(embedding)), self._embeddings.embedding_model_name,
                )
        except Exception as error:
            async with self._database.connection() as connection:
                await connection.execute(
                    "SELECT bio_fn_mark_chat_embedding_failed($1, $2)", row["message_id"], type(error).__name__
                )
            logger.exception("chat_embedding_failed message_id=%s", row["message_id"])
        return True

    async def run_catalog_once(self) -> bool:
        async with self._database.connection() as connection, connection.transaction():
            row = await connection.fetchrow("SELECT * FROM bio_fn_claim_catalog_embedding_job()")
        if row is None:
            return False
        try:
            embedding = await self._embeddings.embed_document(row["catalog_text"])
            async with self._database.connection() as connection:
                await connection.execute(
                    "SELECT bio_fn_store_catalog_embedding($1, $2, $3::vector, $4)",
                    row["catalog_type"], row["catalog_id"], str(list(embedding)), self._embeddings.embedding_model_name,
                )
            logger.info("catalog_embedding_ready type=%s id=%s", row["catalog_type"], row["catalog_id"])
        except Exception as error:
            async with self._database.connection() as connection:
                await connection.execute(
                    "SELECT bio_fn_mark_catalog_embedding_failed($1, $2, $3)",
                    row["catalog_type"], row["catalog_id"], type(error).__name__,
                )
            logger.exception("catalog_embedding_failed type=%s id=%s", row["catalog_type"], row["catalog_id"])
        return True

    async def run_forever(self) -> None:
        base_poll = max(10, self._settings.embedding_worker_poll_seconds)
        idle_seconds = base_poll
        max_idle = 60
        while True:
            try:
                processed = await self.run_once()
                if not processed:
                    processed = await self.run_chat_once()
                if not processed:
                    processed = await self.run_catalog_once()
                if processed:
                    idle_seconds = base_poll
                    await asyncio.sleep(0.5)
                else:
                    await asyncio.sleep(idle_seconds)
                    idle_seconds = min(idle_seconds * 1.5, max_idle)
            except asyncio.CancelledError:
                break
            except Exception:
                logger.exception("Unexpected error in embedding worker loop, sleeping...")
                await asyncio.sleep(max_idle)



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
