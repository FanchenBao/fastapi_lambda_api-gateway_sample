from fastapi import APIRouter

router = APIRouter(prefix='/users', tags=["Users"])


@router.get("")
async def root():
    return {"message": "Get all users"}
