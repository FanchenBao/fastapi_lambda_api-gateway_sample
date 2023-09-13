#!/bin/bash
trap "exit" INT

# Color reference: https://stackoverflow.com/a/28938235/9723036
ColorOff='\033[0m'       # Text Reset
# Regular Colors
BRed='\033[1;31m'         # Red
BGreen='\033[1;32m'       # Green
BWhite='\033[1;37m'       # White
Yellow='\033[0;33m'       # Yellow


# Must provide docker IMAGE name. The IMAGE name will also serve as the AWS Lambda
# function name
if [ "$IMAGE" == "" ];
then
    echo -e "${BRed}IMAGE cannot be empty${ColorOff}\n"
    exit 1
fi


# Default ENV is "stage" unless specified as "prod"
if [ "$ENV" == "" ];
then
    ENV="stage"
fi
if [ "$ENV" != "stage" ] && [ "$ENV" != "prod" ];
then
    echo -e "${BRed}ENV must be either dev or prod${ColorOff}\n"
    exit 1
fi


echo -e "${BWhite}Confirming for ${BRed}$ENV${BWhite} deployment...${ColorOff}\n"
while true; do
    read -p "Do you wish to continue? " Yn
    case $Yn in
        [Yy]* ) break;;
        [Nn]* ) exit 1;;
        * ) echo "Please answer Y (yes) or n (no)";;
    esac
done

echo -e "${BWhite}Collecting variables...${ColorOff}\n"

TAG=$(date +%Y%m%d_%H%M%S)
AWS_ACCOUNT=$(aws sts get-caller-identity --query 'Account' --output text)
# To get region, follow this: https://stackoverflow.com/a/63496689/9723036
AWS_REGION=$(aws ec2 describe-availability-zones --query 'AvailabilityZones[0].RegionName' --output text)
AWS_LAMBDA_ROLE_NAME=$IMAGE-lambda-ex
AWS_LAMBDA_FUNC_NAME="$IMAGE-$ENV"
API_GATEWAY_NAME=$IMAGE


# Create ECR repository if necessary. The repository bear the same name as the IMAGE
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT.dkr.ecr.$AWS_REGION.amazonaws.com
if aws ecr describe-repositories --repository-names $IMAGE &> /dev/null
then
    echo -e "${BGreen}Repository $IMAGE already exists.${ColorOff}\n"
else
    echo -e "${Yellow}Repository $IMAGE does not exist, creating it now...${ColorOff}\n"
    aws ecr create-repository --repository-name $IMAGE --image-scanning-configuration scanOnPush=true --image-tag-mutability MUTABLE
fi


# This is the method to update the docker image on ECR with different tags. The local
# image is always tagged with latest
# Ref: https://stackoverflow.com/a/69763455/9723036
echo -e "${BWhite}Building the docker image...${ColorOff}\n"
docker build --platform linux/amd64 -t $IMAGE:latest .
docker tag $IMAGE:latest $AWS_ACCOUNT.dkr.ecr.$AWS_REGION.amazonaws.com/$IMAGE:$TAG


# Push image to ECR
echo -e "${BWhite}Pushing the image to ECR...${ColorOff}\n"
docker push $AWS_ACCOUNT.dkr.ecr.$AWS_REGION.amazonaws.com/$IMAGE:$TAG


# Create or update lambda function
if aws lambda get-function --function-name $AWS_LAMBDA_FUNC_NAME &> /dev/null;
then
    echo -e "${BGreen}Function $AWS_LAMBDA_FUNC_NAME already exists on lambda; proceed to update...${ColorOff}\n"
    aws lambda update-function-code \
        --function-name $AWS_LAMBDA_FUNC_NAME \
        --image-uri $AWS_ACCOUNT.dkr.ecr.$AWS_REGION.amazonaws.com/$IMAGE:$TAG
else
    # To create a lambda function, one must first create a role to execute the function
    # if such role does not exist
    echo -e "${Yellow}Function $AWS_LAMBDA_FUNC_NAME does not exist on lambda; proceed to check on lambda execution role...${ColorOff}\n"
    if aws iam get-role --role-name $AWS_LAMBDA_ROLE_NAME &> /dev/null;
    then
        echo -e "${BGreen}Lambda execution role $AWS_LAMBDA_ROLE_NAME alraedy exists.${ColorOff}\n"
    else
        echo -e "${Yellow}Lambda execution role $AWS_LAMBDA_ROLE_NAME does not exist; proceed to create...${ColorOff}\n"
        aws iam create-role --role-name $AWS_LAMBDA_ROLE_NAME --assume-role-policy-document '{"Version": "2012-10-17","Statement": [{ "Effect": "Allow", "Principal": {"Service": "lambda.amazonaws.com"}, "Action": "sts:AssumeRole"}]}'
        aws iam attach-role-policy --role-name $AWS_LAMBDA_ROLE_NAME --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
        aws iam attach-role-policy --role-name $AWS_LAMBDA_ROLE_NAME --policy-arn arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess
    fi
    echo -e "${BWhite}Create lambda function $AWS_LAMBDA_FUNC_NAME...${ColorOff}\n"
    until aws lambda create-function \
        --function-name $AWS_LAMBDA_FUNC_NAME \
        --package-type Image \
        --code ImageUri=$AWS_ACCOUNT.dkr.ecr.$AWS_REGION.amazonaws.com/$IMAGE:$TAG \
        --role $(aws iam get-role --role-name $AWS_LAMBDA_ROLE_NAME --query 'Role.Arn' --output text) 2> /dev/null
    do
        sleep 2
    done
fi


# Update ENV variables for the lambda function
echo -e "${BWhite}Update environment variables for Lambda function $AWS_LAMBDA_FUNC_NAME...${ColorOff}\n"
until aws lambda update-function-configuration \
    --function-name $AWS_LAMBDA_FUNC_NAME \
    --environment "Variables={ENV=$ENV}" 2> /dev/null
do
    sleep 2
done


# Configure API Gateway
API_GATEWAY_ID=$(aws apigateway get-rest-apis --query "items[?name=='$API_GATEWAY_NAME'].id" --output text)
if [ "$API_GATEWAY_ID" == "" ]
then
    echo -e "${BWhite}Create API Gateway $API_GATEWAY_NAME...${ColorOff}\n"
    aws apigateway create-rest-api --name $API_GATEWAY_NAME --region $AWS_REGION
    # Wait for API Gateway to be ready
    while [ "$API_GATEWAY_ID" == "" ]
    do
        API_GATEWAY_ID=$(aws apigateway get-rest-apis --query "items[?name=='$API_GATEWAY_NAME'].id" --output text)
        sleep 2
    done


    echo -e "${BWhite}Create proxy resource...${ColorOff}\n"
    PARENT_ID=""
    # Wait for parent id to be ready
    while [ "$PARENT_ID" == "" ]
    do
        PARENT_ID=$(aws apigateway get-resources --rest-api-id $API_GATEWAY_ID --region $AWS_REGION --query 'items[0].id' --output text)
        sleep 2
    done
    aws apigateway create-resource --rest-api-id $API_GATEWAY_ID --region $AWS_REGION --parent-id $PARENT_ID --path-part {proxy+}


    echo -e "${BWhite}Create ANY method on the proxy resource...${ColorOff}\n"
    RESOURCE_ID=""
    # Wait for parent id to be ready
    while [ "$RESOURCE_ID" == "" ]
    do
        RESOURCE_ID=$(aws apigateway get-resources --rest-api-id $API_GATEWAY_ID --query "items[?parentId=='$PARENT_ID'].id" --output text)
        sleep 2
    done
    aws apigateway put-method --rest-api-id $API_GATEWAY_ID --region $AWS_REGION --resource-id $RESOURCE_ID --http-method ANY --authorization-type "NONE"

    echo -e "${BWhite}Create integration to dynamic Lambda funtion...${ColorOff}\n"
    aws apigateway put-integration \
        --region $AWS_REGION \
        --rest-api-id $API_GATEWAY_ID \
        --resource-id $RESOURCE_ID \
        --http-method ANY \
        --type AWS_PROXY \
        --integration-http-method POST \
        --uri arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/arn:aws:lambda:$AWS_REGION:$AWS_ACCOUNT:function:$IMAGE-\${stageVariables.env}/invocations
else
    echo -e "${BGreen}API Gateway $API_GATEWAY_NAME already exist${ColorOff}\n"
fi


# Grant permission
echo -e "${BWhite}Grant permission for API Gateway to invoke lambda function...${ColorOff}\n"
LAMBDA_ARN=$(aws lambda get-function --function-name $AWS_LAMBDA_FUNC_NAME --query 'Configuration.FunctionArn' --output text)
aws lambda add-permission --function-name $LAMBDA_ARN --source-arn "arn:aws:execute-api:$AWS_REGION:$AWS_ACCOUNT:$API_GATEWAY_ID/*/*/{proxy+}" --principal apigateway.amazonaws.com --statement-id apigateway-access --action lambda:InvokeFunction &> /dev/null


# Check if the API deployment stage exists. If not, create one
if aws apigateway get-stage --rest-api-id $API_GATEWAY_ID --stage-name $ENV &> /dev/null;
then
    echo -e "${BGreen}API Gateway deployment Stage $ENV already exist"
else
    echo -e "${Yellow}API Gateway deployment Stage $ENV does not exist. Create one...${ColorOff}\n"
    aws apigateway create-deployment --rest-api-id $API_GATEWAY_ID --stage-name $ENV --variables env=$ENV
fi


echo -e "${BGreen}Success!${ColorOff}\n"
# Show OpenAPI documentation
python3 -m webbrowser "https://$API_GATEWAY_ID.execute-api.$AWS_REGION.amazonaws.com/$ENV/docs"
