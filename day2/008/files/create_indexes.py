import json, boto3
from pymongo import MongoClient, ASCENDING, DESCENDING
from urllib.parse import quote_plus
region="ap-northeast-2"
sec=json.loads(boto3.client("secretsmanager",region_name=region).get_secret_value(SecretId="skills-nosql-docdb-secret")["SecretString"])
uri=f"mongodb://{quote_plus(sec['username'])}:{quote_plus(sec['password'])}@{sec['host']}:27017/?replicaSet=rs0&readPreference=secondaryPreferred&retryWrites=false"
cli=MongoClient(uri,tls=True,tlsCAFile="/opt/skills-nosql/global-bundle.pem",serverSelectionTimeoutMS=20000)
db=cli["skills_retail"]
db.orders.create_index([("orderId", ASCENDING)], unique=True, name="orderId_1")
db.orders.create_index([("customerId", ASCENDING), ("createdAt", DESCENDING)], name="customerId_1_createdAt_-1")
db.orders.create_index([("status", ASCENDING), ("dueAt", ASCENDING)], name="status_1_dueAt_1")
db.products.create_index([("productId", ASCENDING)], unique=True, name="productId_1")
db.products.create_index([("warehouseId", ASCENDING), ("stock", ASCENDING)], name="warehouseId_1_stock_1")
db.sessions.create_index([("sessionId", ASCENDING)], unique=True, name="sessionId_1")
db.sessions.create_index([("expiresAt", ASCENDING)], expireAfterSeconds=0, name="expiresAt_ttl")
db.sessions.create_index([("customerId", ASCENDING), ("lastSeen", DESCENDING)], name="customerId_1_lastSeen_-1")
print("indexes_created")
