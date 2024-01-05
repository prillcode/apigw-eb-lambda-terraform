## API Gateway -> EventBridge -> Lambda Function with Terraform

Learn how to deploy a serverless architecture made from AWS API Gateway, EventBridge, and Lambda with Terraform.  
This is the source code I created after following this step by step video: https://www.youtube.com/watch?v=wAXR7LOqKHc

Since the video creator didn't upload his source code, I figured I'd upload mine to help others. You will notice minor changes between my source code and the video such as:
- An entire directory for my Lambda function (in case you wanted multiple script files other than the main handler function).
- Lambda handler function is in main.py inside /src/DemoLambdaFunction
- Where the video author used "My_" prefix I typically used "Demo*" for all of the aws rources (Ex: DemoHTTPApi, DemoLambdaFunction, etc)
- I updated the lambda layer arn refernce to the latest, which can be found here: https://docs.powertools.aws.dev/lambda/python/latest/


