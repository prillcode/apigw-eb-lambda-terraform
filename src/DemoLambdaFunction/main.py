import json

from aws_lambda_powertools import logger #be sure to run in Terminal: pip install aws_lambda_powertools

logger = logger.Logger()

def lambda_handler(event, context):
    logger.info(event)
    return {
        'statusCode': 200,
        'body': logger.info(f"Received event: {event}")
    }   