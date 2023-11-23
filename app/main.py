from fastapi import FastAPI
import uvicorn
import os

from api.api_v0.api import router as api_v0_router
from mangum import Mangum
from dotenv import load_dotenv
from fastapi.middleware.cors import CORSMiddleware


load_dotenv()

root_path = os.getenv('ENV', default='')
app = FastAPI(root_path=f'/{root_path}')

app.add_middleware(
    CORSMiddleware,
    allow_origins=['*'],
    allow_methods=["*"],
    allow_headers=["*"],
)

# Add or comment out the following lines of code to include a new version of
# API or deprecate an old version
app.include_router(api_v0_router, prefix="/api/v0")

# The magic that allows the integration with AWS Lambda
handler = Mangum(app)


if __name__ == "__main__":
    uvicorn.run(app, port=8000)
