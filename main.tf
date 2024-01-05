terraform {
  required_providers {
    aws = {
        source = "hashicorp/aws"
        version = "~> 4.48"
    }
  }

  required_version = ">= 1.3"
}

provider "aws" {
  profile = "cloudops" #<-- Change profile name as needed to match aws cli connection in dev environment
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# Create an API Gateway HTTP with integration with EventBridge
resource "aws_apigatewayv2_api" "DemoHTTPApi" {
    name = "DemoHTTPApi with EventBridge created by Terraform"
    protocol_type = "HTTP"
    body = jsonencode(
        {
            "openapi": "3.0.1",
            "info": {
                "title": "DemoHTTPApi with EventBridge created by Aaron",
                "version": "1.0"
            },
            "paths": {
                "post" : {
                    "responses" : {
                        "default" : {
                            "description" : "EventBridge response"
                        }
                    },
                    "x-amazon-apigateway-integration" : {
                        "integrationSubtype" : "EventBridge-PutEvents",
                        "credentials" : "${aws_iam_role.APIGWRole.arn}",
                        "requestParameters" : {
                            "Detail" : "$request.body.Detail",
                            "DetailType" : "MyDetailType",
                            "Source" : "demo.apigw"
                        },
                        "payloadFormatVersion" : "1.0",
                        "type" : "aws_proxy",
                        "connectionType" : "INTERNET"
                    }
                }
            }
        }
    )
}

# Create an API Gateway Stage with automatic deployment
resource "aws_apigatewayv2_stage" "DemoHTTPApiStage" {
  api_id = aws_apigatewayv2_api.DemoHTTPApi.id
  name = "$default"
  auto_deploy = true
}

# Create an IAM role for API Gateway
resource "aws_iam_role" "APIGWRole" {
  assume_role_policy = <<POLICY1
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Service": "apigateway.amazonaws.com"
        },
          "Action": "sts:AssumeRole"
      }
    ]
  }
  POLICY1
}


# Create an IAM policy for API Gateway to write to an EventBridge event
resource "aws_iam_policy" "APIGWPolicy" {
  policy = <<POLICY2
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": "events:PutEvents",
        "Resource": "${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}"
      }
    ]
  }
  POLICY2
}

# Attach the IAM policy to the IAM role
resource "aws_iam_role_policy_attachment" "APIGWPolicyAttachment" {
  role = aws_iam_role.APIGWRole.name
  policy_arn = aws_iam_policy.APIGWPolicy.arn
}

# Create an EventBridge rule
resource "aws_cloudwatch_event_rule" "EventBridgeRule" {
  event_pattern = <<PATTERN
  {
    "account": ["${data.aws_caller_identity.current.account_id}"]
    "source": ["demo.apigw"]
  }
  PATTERN
}

# Set the Lambda function (created below) as the target of the EventBridge rule
resource "aws_cloudwatch_event_target" "EventBridgeTarget" {
  rule = aws_cloudwatch_event_rule.EventBridgeRule.name
  arn = aws_lambda_function.DemoLambdaFunction.arn
}

# Create a zip file from the Lambda source code
data "archive_file" "LambdaZip" {
  type = "zip"
  source_dir = "${path.module}/src/DemoLambdaFunction"
  output_path = "${path.module}/lambda.zip"
}

# Create a Lambda function from the zip file
# - make sure resource name is same as above in EventBridge rule target (DemoLambdaFunction in this case)
# - prefix the function name with the name of the API Gateway (optional)
# - for lambda layer, get latest arn here: https://docs.powertools.aws.dev/lambda/python/latest/
resource "aws_lambda_function" "DemoLambdaFunction" {
  function_name = "${aws_apigatewayv2_api.DemoHTTPApi.name}-DemoLambdaFunction"
  filename = data.archive_file.LambdaZip.output_path
  source_code_hash = filebase64sha256(data.archive_file.LambdaZip.output_path)
  handler = "main.lambda_handler"
  runtime = "python3.12"
  role = aws_iam_role.LambdaRole.arn
  layers = ["arn:aws:lambda:${data.aws_region.current.name}:017000801446:layer:AWSLambdaPowertoolsPythonV2:59"]
}

# Allow the EventBridge rule to invoke the Lambda function just created above
# - source arn = EventBridgeRule also created above
resource "aws_lambda_permission" "EventBridgeInvokeLambdaPermission" {
  statement_id = "AllowEventBridgeInvokeLambda"
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.DemoLambdaFunction.function_name
  principal = "events.amazonaws.com"
  source_arn = aws_cloudwatch_event_rule.EventBridgeRule.arn
}

# Create an IAM role for Lambda
resource "aws_iam_role" "LambdaRole" {
  assume_role_policy = <<POLICY3
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Service": "lambda.amazonaws.com"
        },
          "Action": "sts:AssumeRole"
      }
    ]
  }
  POLICY3
}


# Create an IAM policy for Lambda to write to CloudWatch logs to the log-group:/aws/lambda
resource "aws_iam_policy" "LambdaPolicy" {
  policy = <<POLICY4
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        "Resource": "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/*"
      }
    ]
  }
  POLICY4
}

# Attach the IAM policy to the IAM role
resource "aws_iam_role_policy_attachment" "LambdaPolicyAttachment" {
  role = aws_iam_role.LambdaRole.name
  policy_arn = aws_iam_policy.LambdaPolicy.arn
}

# Create a CloudWatch log group for the Lambda function
resource "aws_cloudwatch_log_group" "DemoLogGroup" {
  name = "/aws/lambda/${aws_lambda_function.DemoLambdaFunction.function_name}"
  retention_in_days = 10
}


# --- OUTPUT STATEMENTS after Terraform creates the above resources

output "APIGW-URL" {
  value = aws_apigatewayv2_stage.DemoHTTPApiStage.invoke_url
  description = "The API Gateway Invocation URL Queue URL"
}

output "LambdaFunctionName" {
  value = aws_lambda_function.DemoLambdaFunction.function_name
  description = "The Lambda Function Name"
}

output "CloudWatchLogName" {
  value = aws_cloudwatch_log_group.DemoLogGroup.name
  description = "The Lambda Function CloudWatch Log Group Name"
}
