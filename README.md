# Introduction

This repo holds the source code for the article: [API Service with FastAPI + AWS Lambda + API Gateway and Make it Work](https://medium.com/@fanchenbao/api-service-with-fastapi-aws-lambda-api-gateway-and-make-it-work-c20edcf77bff). It consists of four main components

1. The FastAPI app inside the `app/` folder
2. The `Dockerfile` to build an image of the FastAPI app
3. `scripts/deploy.sh` to automatically spin up the necessary AWS resources (AWS Lambda, API Gateway, IAM role, etc.) and deploy the FastAPI app
4. `scripts/teardown.sh` to automatically tear down the AWS resources needed to run the API service.

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
3. Add `.env` file to hold the environment variables. The file itself is not committed to the repo per standard practice. Example content is shown below:
    ```
    SOME_ENV=SOJ
    OTHER_ENV=Shako
    ```
4. Run the app inside the `app/` folder
    ```
    cd app
    uvicorn main:app --reload
    ```
5. View the OpenAPI documentation at `http://127.0.0.1:8000/docs`

# Deploy the FastAPI App to AWS
The FastAPI app is packaged into a docker image and executed on AWS Lambda.

First create a `.env.stage` or `.env.prod` files to hold the environment variables specific to the `stage` or `prod`. These two files should NOT be committed.

```
# example content for .env.stage
SOME_ENV=Anni
OTHER_ENV=Raven
```

```
# example content for .env.prod
SOME_ENV=Torch
OTHER_ENV=Griffon
```

Then run the following script to automate the entire process of building and deploying the FastAPI app to AWS.

```
IMAGE=fastapi ENV=stage ./scripts/deploy.sh
```

`IMAGE` is the docker image name. It is also the name of the Lambda function and the API Gateway. `ENV` marks the current environment (either `stage` or `prod`).

# Tear Down the AWS Resources

To tear down all the resources used to run the API service, use the following script

```
IMAGE=fastapi ENV=stage ./scripts/teardown.sh
```
