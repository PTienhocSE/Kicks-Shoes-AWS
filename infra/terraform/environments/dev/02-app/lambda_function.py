import json
import boto3
import os
import time
from datetime import datetime

# Initialize clients
bedrock_agent_runtime = boto3.client(
    'bedrock-agent-runtime',
    region_name=os.environ.get('BEDROCK_REGION', 'us-east-1')
)

dynamodb = boto3.client(
    'dynamodb',
    region_name=os.environ.get('DYNAMODB_REGION', 'us-east-1')
)

BEDROCK_KB_ID = os.environ.get('BEDROCK_KB_ID')
DYNAMODB_TABLE = os.environ.get('DYNAMODB_TABLE')

def lambda_handler(event, context):
    """
    Main Lambda handler for Bedrock retrieval + DynamoDB query
    """
    try:
        # Parse request
        if isinstance(event.get('body'), str):
            body = json.loads(event['body'])
        else:
            body = event
            
        user_query = body.get('query', 'Show top shoes')
        
        print(f"[{datetime.now()}] User query: {user_query}")
        
        # Step 1: Retrieve from Bedrock KB if ID is available
        bedrock_response = {'response_text': 'Bedrock KB not configured', 'sources': []}
        if BEDROCK_KB_ID:
            bedrock_response = retrieve_from_bedrock_kb(user_query)
        
        # Step 2: Query DynamoDB
        dynamodb_products = query_dynamodb_products(user_query)
        
        # Step 3: Merge and format response
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'response': bedrock_response.get('response_text'),
                'products': dynamodb_products,
                'sources': bedrock_response.get('sources', []),
                'timestamp': datetime.now().isoformat()
            })
        }
        
    except Exception as e:
        print(f"[ERROR] {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def retrieve_from_bedrock_kb(query):
    try:
        response = bedrock_agent_runtime.retrieve_and_generate(
            input={'text': query},
            retrieveAndGenerateConfiguration={
                'type': 'KNOWLEDGE_BASE',
                'knowledgeBaseConfiguration': {
                    'knowledgeBaseId': BEDROCK_KB_ID,
                    'modelArn': f'arn:aws:bedrock:{os.environ.get("BEDROCK_REGION", "us-east-1")}::foundation-model/anthropic.claude-v2'
                }
            }
        )
        return {
            'response_text': response['output']['text'],
            'sources': [ref.get('location', {}).get('s3Location', {}).get('uri') 
                        for c in response.get('citations', []) 
                        for ref in c.get('retrievedReferences', [])]
        }
    except Exception as e:
        return {'response_text': f"Error: {str(e)}", 'sources': []}

def query_dynamodb_products(query):
    # Simple scan for now, or filter by keyword
    try:
        response = dynamodb.scan(
            TableName=DYNAMODB_TABLE,
            Limit=5
        )
        return response.get('Items', [])
    except Exception as e:
        print(f"DynamoDB error: {str(e)}")
        return []
