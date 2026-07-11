#!/bin/bash

#2-4 REAT API Implement
#2-4 과제의 채점은 CloudShell에서 진행합니다.

#사전 준비
aws configure set region us-east-1

echo ====================
echo "       4-1        "
echo ====================

aws apigateway get-rest-apis \
  --query "items[?name=='wsc-rest-api'].name" \
  --output text

aws apigateway get-stages \
  --rest-api-id $(aws apigateway get-rest-apis \
    --query "items[?name=='wsc-rest-api'].id" \
    --output text) \
  --query "item[?stageName=='prod'].stageName" \
  --output text

aws lambda get-function-configuration \
  --function-name wsc-rest-function \
  --query '{LambdaName:FunctionName}' \
  --output text

aws lambda get-function-configuration \
  --function-name wsc-rest-function \
  --query 'Runtime' \
  --output text

aws dynamodb list-tables \
  --query "TableNames[?@=='wsc-rest-table']" \
  --output text

echo ""
sleep 2


echo ====================
echo "       4-2        "
echo ====================

API_URL=$(aws apigateway get-rest-apis \
  --region us-east-1 \
  --query "items[?name=='wsc-rest-api'].id" \
  --output text)
  
curl https://$API_URL.execute-api.us-east-1.amazonaws.com/prod/v1/healthcheck
echo ""
echo ""
sleep 2


echo ====================
echo "       4-3        "
echo ====================

API_KEY=$(aws apigateway get-api-keys \
  --region us-east-1 \
  --include-values \
  --query "items[?name=='wsc-rest-api-key'].value" \
  --output text)

aws dynamodb scan --table-name wsc-rest-table --projection-expression "#n" --expression-attribute-names '{"#n":"name"}' | jq -c '.Items[]' | while read item; do
    aws dynamodb delete-item --table-name wsc-rest-table --key "$item" > /dev/null
done

curl -X POST https://$API_URL.execute-api.us-east-1.amazonaws.com/prod/v1/user \
  -H "x-api-key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"name": "kim", "age": 19, "country": "korea"}'
echo ""
curl "https://$API_URL.execute-api.us-east-1.amazonaws.com/prod/v1/user?name=kim&age=19" \
  -H "x-api-key: $API_KEY"

echo ""
echo ""
sleep 2

echo ====================
echo "       4-4        "
echo ====================

curl -X POST https://$API_URL.execute-api.us-east-1.amazonaws.com/prod/v1/user \
  -H "x-api-key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"name": "kim", "age": 19, "country": "korea"}'
echo ""
curl "https://$API_URL.execute-api.us-east-1.amazonaws.com/prod/v1/user?name=nobody&age=19" \
  -H "x-api-key: $API_KEY"

echo ""
echo ""
sleep 2

echo ====================
echo "       4-5        "
echo ====================

curl -X POST https://$API_URL.execute-api.us-east-1.amazonaws.com/prod/v1/user \
  -H "Content-Type: application/json" \
  -d '{"name": "kim", "age": 19, "country": "korea"}'
echo ""
echo ""
sleep 2


echo ====================
echo "       4-6        "
echo ====================

curl "https://$API_URL.execute-api.us-east-1.amazonaws.com/prod/v1/user?name=nobody" \
  -H "x-api-key: $API_KEY"
echo ""