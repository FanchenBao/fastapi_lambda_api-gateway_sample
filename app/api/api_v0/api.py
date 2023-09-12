from fastapi import APIRouter
import os
from .endpoints import items

router = APIRouter()


@router.get("")
async def root():
    return {
        "ENV": os.getenv("ENV"),
        "message": "Hello World!",
    }


router.include_router(items.router)
