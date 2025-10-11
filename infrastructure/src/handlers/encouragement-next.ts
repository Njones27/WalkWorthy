import type { APIGatewayProxyEventV2 } from 'aws-lambda';
import {
  QueryCommand,
  UpdateCommand,
} from '@aws-sdk/lib-dynamodb';
import { TABLE_NAME } from '../shared/env';
import { getUserSub } from '../shared/auth';
import {
  json,
  unauthorized,
  internalError,
} from '../shared/http';
import { dynamo } from '../shared/dynamo';
import { nowIso } from '../shared/time';

export async function handler(event: APIGatewayProxyEventV2) {
  const sub = getUserSub(event);
  if (!sub) {
    return unauthorized();
  }

  try {
    const pending = await loadLatestPending(sub);

    if (!pending) {
      return json(200, { shouldNotify: false });
    }

    const expiresAtEpoch = pending.expiresAt as number | undefined;
    if (typeof expiresAtEpoch === 'number') {
      const nowEpoch = Math.floor(Date.now() / 1000);
      if (expiresAtEpoch < nowEpoch) {
        return json(200, { shouldNotify: false });
      }
    }

    await markDelivered(sub, pending.sk as string);

    return json(200, {
      shouldNotify: true,
      payload: {
        id: pending.id,
        ref: pending.ref,
        text: pending.text,
        encouragement: pending.encouragement,
        translation: pending.translation,
        expiresAt:
          typeof pending.expiresAtIso === 'string'
            ? pending.expiresAtIso
            : expiresAtEpoch
              ? new Date(expiresAtEpoch * 1000).toISOString()
              : undefined,
      },
    });
  } catch (error) {
    console.error('encouragementNext failed', error);
    return internalError();
  }
}

async function loadLatestPending(sub: string) {
  const response = await dynamo.send(
    new QueryCommand({
      TableName: TABLE_NAME,
      KeyConditionExpression: 'pk = :pk AND begins_with(sk, :prefix)',
      ExpressionAttributeValues: {
        ':pk': `USER#${sub}`,
        ':prefix': 'PENDING#',
      },
      ScanIndexForward: false,
      Limit: 1,
    }),
  );

  return response.Items?.[0];
}

async function markDelivered(sub: string, sortKey: string) {
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
}
