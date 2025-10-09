import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ssm from 'aws-cdk-lib/aws-ssm';

export class InfrastructureStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    new ssm.StringParameter(this, 'SmokeParam', {
      parameterName: '/walkworthy/smoke',
      stringValue: 'ready',
      description: 'Placeholder parameter created by the base infrastructure stack.',
    });
  }
}
