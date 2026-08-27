from uuid import UUID

from app.application.use_cases.sightings import EditSighting, VoidSighting


class FakeSightingRepository:
    def __init__(self) -> None:
        self.edit_args: dict[str, object] | None = None
        self.void_args: dict[str, object] | None = None

    async def edit(self, **kwargs) -> None:
        self.edit_args = kwargs

    async def void(self, **kwargs) -> None:
        self.void_args = kwargs


async def test_edit_trims_mutable_text_but_preserves_the_reason() -> None:
    repository = FakeSightingRepository()
    sighting_id = UUID("80000000-0000-0000-0000-000000000002")

    await EditSighting(repository).execute(
        sighting_id=sighting_id,
        field_notes="  Nota actualizada  ",
        classification_level=None,
        latitude=None,
        longitude=None,
        change_reason="  Corrección de cuaderno  ",
    )

    assert repository.edit_args == {
        "sighting_id": sighting_id,
        "field_notes": "Nota actualizada",
        "classification_level": None,
        "latitude": None,
        "longitude": None,
        "change_reason": "Corrección de cuaderno",
    }


async def test_void_trims_the_required_reason() -> None:
    repository = FakeSightingRepository()
    sighting_id = UUID("80000000-0000-0000-0000-000000000003")

    await VoidSighting(repository).execute(sighting_id=sighting_id, reason="  Registro duplicado  ")

    assert repository.void_args == {"sighting_id": sighting_id, "reason": "Registro duplicado"}
