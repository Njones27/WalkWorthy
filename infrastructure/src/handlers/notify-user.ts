import type { APIGatewayProxyEventV2 } from 'aws-lambda';
import { UpdateCommand, GetCommand } from '@aws-sdk/lib-dynamodb';
import { TABLE_NAME } from '../shared/env';
import { getUserSub } from '../shared/auth';
import {
  json,
  parseJsonBody,
  unauthorized,
  badRequest,
  internalError,
} from '../shared/http';
import { dynamo } from '../shared/dynamo';
import { nowIso } from '../shared/time';

interface NotifyRequest {
  encouragementId: string;
}

export async function handler(event: APIGatewayProxyEventV2) {
  const sub = getUserSub(event);
  if (!sub) {
    return unauthorized();
  }

  try {
    const body = parseJsonBody<NotifyRequest>(
      event.body,
      event.isBase64Encoded,
    );

    if (!body.encouragementId) {
      return badRequest('encouragementId is required');
    }

    const sortKey = `PENDING#${body.encouragementId}`;

    const record = await dynamo.send(
      new GetCommand({
        TableName: TABLE_NAME,
        Key: {
          pk: `USER#${sub}`,
          sk: sortKey,
        },
      }),
    );

    if (!record.Item) {
      return json(404, { message: 'Encouragement not found' });
    }

    await dynamo.send(
      new UpdateCommand({
        TableName: TABLE_NAME,
        Key: {
          pk: `USER#${sub}`,
          sk: sortKey,
        },
        UpdateExpression:
          'SET delivered = :true, deliveredAt = :at',
        ExpressionAttributeValues: {
          ':true': true,
          ':at': nowIso(),
        },
      }),
    );

    return json(200, { acknowledged: true });
  } catch (error) {
    if (error instanceof SyntaxError) {
      return badRequest('Invalid JSON payload');
    }

    console.error('notifyUser failed', error);
    return internalError();
  }
}
