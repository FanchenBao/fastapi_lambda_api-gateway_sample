# Introduction

This repo holds the source code for the article: [API Service with FastAPI + AWS Lambda + API Gateway and Make it Work](https://medium.com/@fanchenbao/api-service-with-fastapi-aws-lambda-api-gateway-and-make-it-work-c20edcf77bff). It consists of three main components

1. The FastAPI app inside the `app/` folder
2. The `Dockerfile` to build an image of the FastAPI app
3. The script in `scripts/deploy.sh` that facilitates the deployment of the FastAPI app to AWS Lambda

# Run the FastAPI App Locally

1. Create a virtual environment

    ```
    python -m venv venv
    source venv/bin/activate
    ```
2. Install the dependencies

    ```
    pip install -r requirements.txt
    ```
3. Run the app inside the `app/` folder
    ```
    cd app
    uvicorn main:app --reload
    ```
4. View the OpenAPI documentation at `http://127.0.0.1:8000/docs`