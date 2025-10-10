# Welcome to your CDK TypeScript project

This is a blank project for CDK development with TypeScript.

The `cdk.json` file tells the CDK Toolkit how to execute your app.

## Useful commands

* `npm run build`   compile typescript to js
* `npm run watch`   watch for changes and compile
* `npm run test`    perform the jest unit tests
* `npx cdk deploy`  deploy this stack to your default AWS account/region
* `npx cdk diff`    compare deployed stack with current state
* `npx cdk synth`   emits the synthesized CloudFormation template

## Project notes

Before running the commands above, export your deployment scope so the stack synthesizes with the right AWS account and region:

```bash
cp cdk-env.example.sh cdk-env.sh
source cdk-env.sh
```

Update `cdk-env.sh` with your actual account/region; the script is ignored by Git.

The current stack ships a placeholder Systems Manager parameter (`/walkworthy/smoke`). Replace it with the real WalkWorthy resources (DynamoDB table, Secrets Manager references, HTTP API, EventBridge Scheduler, Lambdas) as you iterate.

## CI/CD role requirements

The GitHub Actions deploy role (`AWS_ROLE_ARN`) must include these permissions in addition to CloudFormation/IAM/S3/Lambda/etc.:
* `ssm:GetParameter` on `arn:aws:ssm:<region>:<account>:parameter/cdk-bootstrap/hnb659fds/version`
* `cloudformation:DescribeStacks` for the bootstrap stack (so CDK can reuse existing assets)

Without the SSM permission, CDK will fail with `AccessDeniedException` during bootstrap version checks.
