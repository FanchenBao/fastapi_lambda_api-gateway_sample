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


echo -e "${BWhite}Confirming for ${BRed}$ENV${BWhite} TEAR DOWN...${ColorOff}\n"
while true; do
    read -p "Do you wish to continue? " Yn
    case $Yn in
        [Yy]* ) break;;
        [Nn]* ) exit 1;;
        * ) echo "Please answer Y (yes) or n (no)";;
    esac
done

echo -e "${BWhite}Collecting environmental variables...${ColorOff}\n"

AWS_ACCOUNT=$(aws sts get-caller-identity | ggrep -Po '(?<="Account":\s")\d+(?=")')
# To get region, follow this: https://stackoverflow.com/a/63496689/9723036
AWS_REGION=$(aws ec2 describe-availability-zones --output text --query 'AvailabilityZones[0].[RegionName]')
AWS_LAMBDA_ROLE_NAME=$IMAGE-lambda-ex
AWS_LAMBDA_FUNC_NAME=$IMAGE
API_GATEWAY_NAME=$IMAGE


echo -e "${BWhite}Deleting API Gateway...${ColorOff}\n"
API_GATEWAY_ID=$(aws apigateway get-rest-apis --query "items[?name=='$API_GATEWAY_NAME'].id" --output text)
if [ "$API_GATEWAY_ID" != "" ]
then
    aws apigateway delete-rest-api --rest-api-id $API_GATEWAY_ID
fi


echo -e "${BWhite}Deleting Lambda function...${ColorOff}\n"
if aws lambda get-function --function-name $AWS_LAMBDA_FUNC_NAME &> /dev/null;
then
    aws lambda delete-function --function-name $AWS_LAMBDA_FUNC_NAME
fi


echo -e "${BWhite}Deleting Lambda execution role...${ColorOff}\n"
if aws iam get-role --role-name $AWS_LAMBDA_ROLE_NAME &> /dev/null
then
    for POLICY_ARN in $(aws iam list-attached-role-policies --role-name $AWS_LAMBDA_ROLE_NAME --query 'AttachedPolicies[*].PolicyArn' --output text)
    do
        aws iam detach-role-policy --role-name $AWS_LAMBDA_ROLE_NAME --policy-arn $POLICY_ARN
    done
    aws iam delete-role --role-name $AWS_LAMBDA_ROLE_NAME
fi

echo -e "${BGreen}Tear down complete!${ColorOff}\n"
