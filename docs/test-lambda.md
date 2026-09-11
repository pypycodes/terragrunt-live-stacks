
# NON PROD

```bash

aws lambda invoke   --function-name stateful-lambda-service-dev   --payload '{
    "requestContext": {
      "http": {
        "method": "GET"
      }
    }
  }'   get.json   --cli-binary-format raw-in-base64-out   --profile floci-nonprod && jq . get.json 


aws lambda invoke   --function-name stateful-lambda-service-dev   --payload '{
    "requestContext": {
      "http": {
        "method": "POST"
      }
    }
  }'   post.json   --cli-binary-format raw-in-base64-out   --profile floci-nonprod && jq . post.json 


```

# PROD

```bash

aws lambda invoke   --function-name stateful-lambda-service   --payload '{
    "requestContext": {
      "http": {
        "method": "GET"
      }
    }
  }'   get.json   --cli-binary-format raw-in-base64-out   --profile floci-prod && jq . get.json 


aws lambda invoke   --function-name stateful-lambda-service   --payload '{
    "requestContext": {
      "http": {
        "method": "POST"
      }
    }
  }'   post.json   --cli-binary-format raw-in-base64-out   --profile floci-prod && jq . post.json 


```