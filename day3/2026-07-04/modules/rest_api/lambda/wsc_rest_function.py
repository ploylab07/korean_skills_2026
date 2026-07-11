import json
import os
import boto3
from botocore.exceptions import ClientError

_dynamodb = None
_table = None

def get_table():
    global _dynamodb, _table
    if _table is None:
        _dynamodb = boto3.resource('dynamodb', region_name=os.environ.get('AWS_REGION', 'us-east-1'))
        _table = _dynamodb.Table(os.environ['TABLE_NAME'])
    return _table

def response(status_code, body):
    return {
        'statusCode': status_code,
        'headers': {'Content-Type': 'application/json'},
        'body': json.dumps(body)
    }

def handler(event, context):
    try:
        method = event.get('httpMethod', event.get('requestContext', {}).get('http', {}).get('method', ''))
        if method == 'POST':
            return create_user(event)
        if method == 'GET':
            return get_user(event)
        return response(405, {'message': 'Method not allowed'})
    except Exception:
        return response(500, {'message': 'Internal server error'})

def create_user(event):
    try:
        body = json.loads(event.get('body') or '{}')
    except json.JSONDecodeError:
        return response(400, {'message': 'Invalid request body'})

    name = body.get('name')
    age = body.get('age')
    country = body.get('country')

    if not name or age is None or not country:
        return response(400, {'message': 'Invalid request body'})

    try:
        age = int(age)
    except (TypeError, ValueError):
        return response(400, {'message': 'Invalid request body'})

    item = {'name': str(name), 'age': age, 'country': str(country)}
    table = get_table()

    try:
        table.put_item(
            Item=item,
            ConditionExpression='attribute_not_exists(#n) AND attribute_not_exists(#a)',
            ExpressionAttributeNames={'#n': 'name', '#a': 'age'}
        )
        return response(200, {'message': 'User created successfully'})
    except ClientError as e:
        if e.response['Error']['Code'] == 'ConditionalCheckFailedException':
            return response(200, {'message': 'User already exists'})
        return response(500, {'message': 'Internal server error'})

def get_user(event):
    params = event.get('queryStringParameters') or {}
    name = params.get('name')
    age = params.get('age')

    if not name or age is None:
        return response(400, {'message': 'Missing required request parameters: [age]'})

    try:
        age = int(age)
    except (TypeError, ValueError):
        return response(400, {'message': 'Invalid parameter type'})

    table = get_table()
    result = table.get_item(Key={'name': str(name), 'age': age})
    item = result.get('Item')

    if not item:
        return response(404, {'message': 'User not found'})

    return response(200, {
        'name': item['name'],
        'age': int(item['age']),
        'country': item['country']
    })
