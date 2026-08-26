from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.infrastructure.config import get_settings
from app.infrastructure.db.database import Database
from app.presentation.api.routers import health, sightings


@asynccontextmanager
async def lifespan(app: FastAPI):
    database = Database(get_settings().database_url)
    await database.connect()
    app.state.database = database
    try:
        yield
    finally:
        await database.close()


app = FastAPI(title="Bioma API", version="0.1.0", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=[get_settings().frontend_origin],
    allow_credentials=True,
    allow_methods=["GET", "POST", "PATCH", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "X-Correlation-ID"],
)
app.include_router(health.router)
app.include_router(sightings.router)
