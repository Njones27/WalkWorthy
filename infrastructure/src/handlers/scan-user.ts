import type { APIGatewayProxyEventV2 } from 'aws-lambda';
import { GetCommand, PutCommand, QueryCommand, UpdateCommand } from '@aws-sdk/lib-dynamodb';
import { randomUUID } from 'crypto';
import { TABLE_NAME } from '../shared/env';
import { dynamo } from '../shared/dynamo';
import { getUserSub } from '../shared/auth';
import {
  json,
  internalError,
  unauthorized,
} from '../shared/http';
import { futureEpochSeconds, nowIso } from '../shared/time';

export async function handler(event: APIGatewayProxyEventV2) {
  const sub = getUserSub(event);
  if (!sub) {
    return unauthorized();
  }

  try {
    const canvasLink = await loadCanvasLink(sub);
    if (!canvasLink) {
      return json(409, { message: 'Canvas account not linked' });
    }

    await clearPendingEncouragements(sub);

    const encouragement = buildPlaceholderEncouragement();
    await persistEncouragement(sub, encouragement);
    await recordScan(sub, encouragement.id);

    return json(202, {
      message: 'Scan accepted',
      encouragementId: encouragement.id,
      placeholder: true,
    });
  } catch (error) {
    console.error('scanUser failed', error);
    return internalError();
  }
}

async function loadCanvasLink(sub: string) {
  const result = await dynamo.send(
    new GetCommand({
      TableName: TABLE_NAME,
      Key: {
        pk: `USER#${sub}`,
        sk: 'CANVAS_LINK',
      },
    }),
  );

  return result.Item ?? null;
}

async function clearPendingEncouragements(sub: string) {
  const result = await dynamo.send(
    new QueryCommand({
      TableName: TABLE_NAME,
      KeyConditionExpression: 'pk = :pk AND begins_with(sk, :prefix)',
      ExpressionAttributeValues: {
        ':pk': `USER#${sub}`,
        ':prefix': 'PENDING#',
      },
    }),
  );

  const now = nowIso();

  const items =
    (result.Items ?? []) as Array<{ pk: string; sk: string }>;

  await Promise.all(
    items.map(({ pk, sk }) =>
      dynamo.send(
        new UpdateCommand({
          TableName: TABLE_NAME,
          Key: {
            pk,
            sk,
          },
          UpdateExpression:
            'SET delivered = :true, deliveredAt = :at',
          ExpressionAttributeValues: {
            ':true': true,
            ':at': now,
          },
        }),
      ),
    ),
  );
}

async function persistEncouragement(
  sub: string,
  encouragement: ReturnType<typeof buildPlaceholderEncouragement>,
) {
  await dynamo.send(
    new PutCommand({
      TableName: TABLE_NAME,
      Item: {
        pk: `USER#${sub}`,
        sk: `PENDING#${encouragement.id}`,
        id: encouragement.id,
        ref: encouragement.ref,
        text: encouragement.text,
        encouragement: encouragement.encouragement,
        translation: encouragement.translation,
        createdAt: encouragement.createdAt,
        expiresAt: encouragement.expiresAtEpoch,
        expiresAtIso: encouragement.expiresAtIso,
        delivered: false,
      },
    }),
  );
}

async function recordScan(sub: string, encouragementId: string) {
  const createdAt = nowIso();

  await dynamo.send(
    new PutCommand({
      TableName: TABLE_NAME,
      Item: {
        pk: `USER#${sub}`,
        sk: `SCAN#${createdAt}`,
        encouragementId,
        createdAt,
        status: 'PLACEHOLDER',
      },
    }),
  );
}

function buildPlaceholderEncouragement() {
  const createdAt = nowIso();
  const expiresAtEpoch = futureEpochSeconds(12);
  const expiresAtIso = new Date(expiresAtEpoch * 1000).toISOString();

  return {
    id: randomUUID(),
    ref: 'Philippians 4:6-7',
    text: 'Do not be anxious about anything, but in everything by prayer and supplication with thanksgiving let your requests be made known to God.',
    encouragement:
      'God invites you to bring today’s stress to Him—take a pause, breathe, and ask for His peace.',
    translation: 'ESV',
    createdAt,
    expiresAtEpoch,
    expiresAtIso,
  };
}
