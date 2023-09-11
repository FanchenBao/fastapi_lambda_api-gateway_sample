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

echo -e "${BWhite}Collecting environmental variables...${ColorOff}\n"
# Environment variables, Read from either .env.stage or .env.prod
FOO=$(cat .env.$ENV | ggrep -Po '(?<=FOO=).+')
BAR=$(cat .env.$ENV | ggrep -Po '(?<=BAR=).+')

TAG=$(date +%Y%m%d_%H%M%S)
AWS_ACCOUNT=$(aws sts get-caller-identity | ggrep -Po '(?<="Account":\s")\d+(?=")')
# To get region, follow this: https://stackoverflow.com/a/63496689/9723036
AWS_REGION=$(aws ec2 describe-availability-zones --output text --query 'AvailabilityZones[0].[RegionName]')
AWS_LAMBDA_ROLE_NAME=lambda-ex

# Get other variables
TAG=$(date +%Y%m%d_%H%M%S)
AWS_ACCOUNT=$(aws sts get-caller-identity | ggrep -Po '(?<="Account":\s")\d+(?=")')
# To get region, follow this: https://stackoverflow.com/a/63496689/9723036
AWS_REGION=$(aws ec2 describe-availability-zones --output text --query 'AvailabilityZones[0].RegionName')
AWS_LAMBDA_ROLE_NAME=lambda-ex


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
if aws lambda get-function --function-name $IMAGE &> /dev/null;
then
    echo -e "${BGreen}Function $IMAGE already exists on lambda; proceed to update...${ColorOff}\n"
    aws lambda update-function-code \
        --function-name $IMAGE \
        --image-uri $AWS_ACCOUNT.dkr.ecr.$AWS_REGION.amazonaws.com/$IMAGE:$TAG
else
    # To create a lambda function, one must first create a role to execute the function
    # if such role does not exist
    echo -e "${Yellow}Function $IMAGE does not exist on lambda; proceed to check on lambda execution role...${ColorOff}\n"
    if aws iam get-role --role-name $AWS_LAMBDA_ROLE_NAME &> /dev/null;
    then
        echo -e "${BGreen}Lambda execution role $AWS_LAMBDA_ROLE_NAME alraedy exists.${ColorOff}\n"
    else
        echo -e "${Yellow}Lambda execution role $AWS_LAMBDA_ROLE_NAME does not exist; proceed to create...${ColorOff}\n"
        aws iam create-role --role-name $AWS_LAMBDA_ROLE_NAME --assume-role-policy-document '{"Version": "2012-10-17","Statement": [{ "Effect": "Allow", "Principal": {"Service": "lambda.amazonaws.com"}, "Action": "sts:AssumeRole"}]}'
        aws iam attach-role-policy --role-name $AWS_LAMBDA_ROLE_NAME --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
        aws iam attach-role-policy --role-name $AWS_LAMBDA_ROLE_NAME --policy-arn arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess
    fi
    echo -e "${BWhite}Create lambda function $IMAGE...${ColorOff}\n"
    until aws lambda create-function \
        --function-name $IMAGE \
        --package-type Image \
        --code ImageUri=$AWS_ACCOUNT.dkr.ecr.$AWS_REGION.amazonaws.com/$IMAGE:$TAG \
        --role $(aws iam get-role --role-name $AWS_LAMBDA_ROLE_NAME --query 'Role.Arn' | tr -d '"') 2> /dev/null
    do
        echo -e "${Yellow}Waiting for $AWS_LAMBDA_ROLE_NAME to be ready...${ColorOff}\n"
        sleep 2
    done
fi


# Update ENV variables for the lambda function
echo -e "${BWhite}Update environment variables...${ColorOff}\n"
until aws lambda update-function-configuration \
    --function-name $IMAGE \
    --environment "Variables={ENV=$ENV,FOO=$FOO,BAR=$BAR}" 2> /dev/null
do
    echo -e "${Yellow}Waitng for function creation or update to complete...${ColorOff}\n"
    sleep 2
done



