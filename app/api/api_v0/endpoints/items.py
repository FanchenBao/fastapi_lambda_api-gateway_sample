from fastapi import APIRouter

router = APIRouter(prefix='/items', tags=["Items"])


@router.get("")
async def root():
    return {"message": "Get all items"}
