import * as path from 'path';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import { Duration } from 'aws-cdk-lib';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import {
  NodejsFunction,
  NodejsFunctionProps,
} from 'aws-cdk-lib/aws-lambda-nodejs';
import * as apigwv2 from 'aws-cdk-lib/aws-apigatewayv2';
import * as apigwAuthorizers from 'aws-cdk-lib/aws-apigatewayv2-authorizers';
import * as apigwIntegrations from 'aws-cdk-lib/aws-apigatewayv2-integrations';
import * as scheduler from 'aws-cdk-lib/aws-scheduler';
import * as sqs from 'aws-cdk-lib/aws-sqs';
import * as iam from 'aws-cdk-lib/aws-iam';

export class InfrastructureStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    const enableJwtAuth = this.node.tryGetContext('enableJwtAuth') === 'true';
    let jwtAuthorizer: apigwAuthorizers.HttpJwtAuthorizer | undefined;
    if (enableJwtAuth) {
      const userPoolId = new cdk.CfnParameter(this, 'CognitoUserPoolId', {
        type: 'String',
        description:
          'User pool ID that issues JWTs for the WalkWorthy mobile app.',
      });

      const userPoolClientId = new cdk.CfnParameter(
        this,
        'CognitoUserPoolClientId',
        {
          type: 'String',
          description:
            'App client ID whose tokens authorize access to protected routes.',
        },
      );

      jwtAuthorizer = new apigwAuthorizers.HttpJwtAuthorizer(
        'WalkWorthyJwtAuthorizer',
        cdk.Fn.join('', [
          'https://cognito-idp.',
          this.region,
          '.amazonaws.com/',
          userPoolId.valueAsString,
        ]),
        {
          jwtAudience: [userPoolClientId.valueAsString],
        },
      );
    }

    const table = dynamodb.TableV2.fromTableName(
      this,
      'WalkWorthyTable',
      'walkworthy',
    );

    const canvasSecret = secretsmanager.Secret.fromSecretNameV2(
      this,
      'CanvasClientSecret',
      'walkworthy/canvas/client',
    );

    const schedulerDlq = new sqs.Queue(this, 'ScanSchedulerDlq', {
      queueName: 'walkworthy-scan-scheduler-dlq',
      retentionPeriod: Duration.days(14),
      visibilityTimeout: Duration.seconds(120),
      encryption: sqs.QueueEncryption.KMS_MANAGED,
    });

    const sharedLambdaProps: Omit<NodejsFunctionProps, 'entry'> = {
      runtime: lambda.Runtime.NODEJS_20_X,
      architecture: lambda.Architecture.ARM_64,
      handler: 'handler',
      memorySize: 256,
      timeout: Duration.seconds(10),
      bundling: {
        target: 'node20',
        minify: true,
      },
      environment: {
        TABLE_NAME: table.tableName,
        CANVAS_CLIENT_SECRET_NAME: canvasSecret.secretName,
      },
    };

    const createHandler = (
      id: string,
      fileName: string,
      overrides?: Partial<NodejsFunctionProps>,
    ) => {
      const entry = path.join(__dirname, '../src/handlers', fileName);
      const baseEnvironment = sharedLambdaProps.environment ?? {};
      const overrideEnv = overrides?.environment ?? {};

      return new NodejsFunction(this, id, {
        ...sharedLambdaProps,
        ...overrides,
        entry,
        environment: {
          ...baseEnvironment,
          ...overrideEnv,
        },
        bundling: {
          ...sharedLambdaProps.bundling,
          ...(overrides?.bundling ?? {}),
        },
      });
    };

    const canvasCallbackFn = createHandler(
      'CanvasCallbackFunction',
      'canvas-callback.ts',
      {
        timeout: Duration.seconds(30),
      },
    );
    const scanUserFn = createHandler('ScanUserFunction', 'scan-user.ts', {
      timeout: Duration.seconds(60),
    });
    const notifyUserFn = createHandler('NotifyUserFunction', 'notify-user.ts');
    const registerDeviceFn = createHandler(
      'RegisterDeviceFunction',
      'register-device.ts',
    );
    const userProfileFn = createHandler(
      'UserProfileFunction',
      'user-profile.ts',
    );
    const encouragementNextFn = createHandler(
      'EncouragementNextFunction',
      'encouragement-next.ts',
    );

    table.grantReadWriteData(canvasCallbackFn);
    table.grantReadWriteData(scanUserFn);
    table.grantReadWriteData(notifyUserFn);
    table.grantReadWriteData(registerDeviceFn);
    table.grantReadWriteData(userProfileFn);
    table.grantReadWriteData(encouragementNextFn);

    canvasSecret.grantRead(canvasCallbackFn);
    canvasSecret.grantRead(scanUserFn);

    const canvasTokensStatement = new iam.PolicyStatement({
      sid: 'CanvasTokenManagement',
      effect: iam.Effect.ALLOW,
      actions: [
        'secretsmanager:CreateSecret',
        'secretsmanager:DescribeSecret',
        'secretsmanager:PutSecretValue',
        'secretsmanager:UpdateSecret',
        'secretsmanager:GetSecretValue',
        'secretsmanager:TagResource',
      ],
      resources: [
        `arn:aws:secretsmanager:${this.region}:${this.account}:secret:walkworthy/canvas/*`,
      ],
    });

    canvasCallbackFn.addToRolePolicy(canvasTokensStatement);
    scanUserFn.addToRolePolicy(canvasTokensStatement);

    const httpApi = new apigwv2.HttpApi(this, 'WalkWorthyHttpApi', {
      apiName: 'walkworthy-api',
      corsPreflight: {
        allowOrigins: ['*'],
        allowMethods: [
          apigwv2.CorsHttpMethod.GET,
          apigwv2.CorsHttpMethod.POST,
        ],
        allowHeaders: ['Authorization', 'Content-Type'],
      },
    });

    httpApi.addRoutes({
      path: '/auth/canvas/callback',
      methods: [apigwv2.HttpMethod.POST],
      integration: new apigwIntegrations.HttpLambdaIntegration(
        'CanvasCallbackIntegration',
        canvasCallbackFn,
      ),
    });

    httpApi.addRoutes({
      path: '/user/profile',
      methods: [apigwv2.HttpMethod.POST],
      authorizer: jwtAuthorizer,
      integration: new apigwIntegrations.HttpLambdaIntegration(
        'UserProfileIntegration',
        userProfileFn,
      ),
    });

    httpApi.addRoutes({
      path: '/scan/now',
      methods: [apigwv2.HttpMethod.POST],
      authorizer: jwtAuthorizer,
      integration: new apigwIntegrations.HttpLambdaIntegration(
        'ScanNowIntegration',
        scanUserFn,
      ),
    });

    httpApi.addRoutes({
      path: '/encouragement/next',
      methods: [apigwv2.HttpMethod.GET],
      authorizer: jwtAuthorizer,
      integration: new apigwIntegrations.HttpLambdaIntegration(
        'EncouragementNextIntegration',
        encouragementNextFn,
      ),
    });

    httpApi.addRoutes({
      path: '/device/register',
      methods: [apigwv2.HttpMethod.POST],
      authorizer: jwtAuthorizer,
      integration: new apigwIntegrations.HttpLambdaIntegration(
        'RegisterDeviceIntegration',
        registerDeviceFn,
      ),
    });

    httpApi.addRoutes({
      path: '/encouragement/notify',
      methods: [apigwv2.HttpMethod.POST],
      authorizer: jwtAuthorizer,
      integration: new apigwIntegrations.HttpLambdaIntegration(
        'NotifyUserIntegration',
        notifyUserFn,
      ),
    });

    const schedulerRole = new iam.Role(this, 'ScanSchedulerRole', {
      assumedBy: new iam.ServicePrincipal('scheduler.amazonaws.com'),
      description:
        'Role assumed by EventBridge Scheduler to invoke the scanUser function.',
    });

    scanUserFn.grantInvoke(schedulerRole);
    schedulerDlq.grantSendMessages(schedulerRole);

    new scheduler.CfnSchedule(this, 'WeekdayScanSchedule', {
      name: 'walkworthy-weekday-scan',
      description:
        'Weekday 9am America/Chicago scan to refresh Canvas data and prepare encouragements.',
      flexibleTimeWindow: {
        mode: 'FLEXIBLE',
        maximumWindowInMinutes: 10,
      },
      scheduleExpression: 'cron(0 9 ? * MON-FRI *)',
      scheduleExpressionTimezone: 'America/Chicago',
      target: {
        arn: scanUserFn.functionArn,
        roleArn: schedulerRole.roleArn,
        deadLetterConfig: {
          arn: schedulerDlq.queueArn,
        },
        retryPolicy: {
          maximumEventAgeInSeconds: 3600,
          maximumRetryAttempts: 2,
        },
      },
    });

    new cdk.CfnOutput(this, 'TableName', {
      value: table.tableName,
    });

    new cdk.CfnOutput(this, 'HttpApiUrl', {
      value: httpApi.apiEndpoint,
    });

    new cdk.CfnOutput(this, 'CanvasClientSecretArn', {
      value: canvasSecret.secretArn,
    });
  }
}
