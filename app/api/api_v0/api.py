from fastapi import APIRouter
import os
from .endpoints import items

router = APIRouter()


@router.get("")
async def root():
    return {
        "ENV": os.getenv("ENV"),
        "FOO": os.getenv("FOO"),
        "BAR": os.getenv("BAR"),
        "message": "Hello World!",
    }


router.include_router(items.router)
