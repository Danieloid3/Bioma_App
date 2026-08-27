import asyncio
from contextlib import asynccontextmanager, suppress

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.infrastructure.config import get_settings
from app.infrastructure.db.database import Database
from app.infrastructure.rate_limit import RedisRateLimiter
from app.presentation.api.errors import install_exception_handlers
from app.presentation.api.middleware import correlation_id_middleware
from app.presentation.api.routers import (
    admin,
    auth,
    catalog,
    chat,
    copilot,
    dashboard,
    health,
    sightings,
)
from app.workers.embeddings import EmbeddingWorker


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = get_settings()
    database = Database(settings.database_url)
    await database.connect()
    rate_limiter = RedisRateLimiter.from_url(settings.redis_url)
    await rate_limiter.ping()
    app.state.rate_limiter = rate_limiter
    app.state.database = database

    # Background embedding worker runs inside the API container to save Railway resources
    worker = EmbeddingWorker(database)
    worker_task = asyncio.create_task(worker.run_forever())

    try:
        yield
    finally:
        worker_task.cancel()
        with suppress(asyncio.CancelledError):
            await worker_task
        await database.close()
        await rate_limiter.close()



app = FastAPI(
    title="Bioma API",
    version="0.1.0",
    description="API para investigación y registro de biodiversidad.",
    lifespan=lifespan,
)
app.middleware("http")(correlation_id_middleware)
app.add_middleware(
    CORSMiddleware,
    allow_origins=[get_settings().frontend_origin],
    allow_credentials=True,
    allow_methods=["GET", "POST", "PATCH", "DELETE", "OPTIONS"],

    allow_headers=["Authorization", "Content-Type", "X-Correlation-ID"],
)
install_exception_handlers(app)
app.include_router(health.router)
app.include_router(auth.router)
app.include_router(admin.router)
app.include_router(catalog.router)
app.include_router(dashboard.router)
app.include_router(sightings.router)
app.include_router(chat.router)
app.include_router(copilot.router)
