from fastapi import APIRouter
import os
from .endpoints import items, users

router = APIRouter()


@router.get("")
async def root():
    return {
        "ENV": os.getenv("ENV", default='dev'),
        "message": "Hello World!",
    }


router.include_router(items.router)
router.include_router(users.router)
