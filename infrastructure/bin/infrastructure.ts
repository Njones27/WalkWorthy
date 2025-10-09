#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { InfrastructureStack } from '../lib/infrastructure-stack';

const app = new cdk.App();

const env = {
  account: process.env.CDK_DEFAULT_ACCOUNT,
  region: process.env.CDK_DEFAULT_REGION,
};

if (!env.account || !env.region) {
  throw new Error('Set CDK_DEFAULT_ACCOUNT and CDK_DEFAULT_REGION before synthesizing the stack.');
}

new InfrastructureStack(app, 'InfrastructureStack', { env });
