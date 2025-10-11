import type { APIGatewayProxyEventV2 } from 'aws-lambda';
import { PutCommand } from '@aws-sdk/lib-dynamodb';
import { TABLE_NAME } from '../shared/env';
import { getUserSub } from '../shared/auth';
import {
  parseJsonBody,
  unauthorized,
  badRequest,
  json,
  internalError,
} from '../shared/http';
import { dynamo } from '../shared/dynamo';
import { nowIso } from '../shared/time';

interface DeviceRegistrationRequest {
  deviceId: string;
  appVersion?: string;
  notificationToken?: string;
}

export async function handler(event: APIGatewayProxyEventV2) {
  const sub = getUserSub(event);
  if (!sub) {
    return unauthorized();
  }

  try {
    const body = parseJsonBody<DeviceRegistrationRequest>(
      event.body,
      event.isBase64Encoded,
    );

    if (!body.deviceId) {
      return badRequest('deviceId is required');
    }

    await dynamo.send(
      new PutCommand({
        TableName: TABLE_NAME,
        Item: {
          pk: `USER#${sub}`,
          sk: `DEVICE#${body.deviceId}`,
          platform: 'ios',
          appVersion: body.appVersion,
          notificationToken: body.notificationToken,
          updatedAt: nowIso(),
        },
      }),
    );

    return json(200, { registered: true });
  } catch (error) {
    if (error instanceof SyntaxError) {
      return badRequest('Invalid JSON payload');
    }

    console.error('registerDevice failed', error);
    return internalError();
  }
}
