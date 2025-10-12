import { ScanCommand } from '@aws-sdk/lib-dynamodb';
import type { ScheduledHandler } from 'aws-lambda';

import { TABLE_NAME } from '../shared/env';
import { dynamo } from '../shared/dynamo';
import { runScanForUser, CanvasLinkMissingError } from '../services/scan-runner';

const USER_PK_PREFIX = 'USER#';

export const handler: ScheduledHandler = async () => {
  const subs = await listLinkedUserSubs();

  console.log('weekday-scan starting', { userCount: subs.length });

  const results: Array<{ sub: string; outcome: 'SUCCESS' | 'FALLBACK' | 'ERROR'; message?: string }> = [];

  for (const sub of subs) {
    try {
      const result = await runScanForUser(sub);
      results.push({ sub, outcome: result.status, message: result.encouragementId });
      console.log('weekday-scan success', { sub, status: result.status, encouragementId: result.encouragementId });
    } catch (error) {
      if (error instanceof CanvasLinkMissingError) {
        results.push({ sub, outcome: 'ERROR', message: 'Canvas not linked' });
        console.warn('weekday-scan skipped user without Canvas link', { sub });
        continue;
      }

      const message = error instanceof Error ? error.message : 'Unknown error';
      results.push({ sub, outcome: 'ERROR', message });
      console.error('weekday-scan failed', { sub, message, error });
    }
  }

  console.log('weekday-scan finished', {
    totals: {
      users: subs.length,
      successes: results.filter((r) => r.outcome !== 'ERROR').length,
      errors: results.filter((r) => r.outcome === 'ERROR').length,
    },
  });
};

async function listLinkedUserSubs(): Promise<string[]> {
  const subs: string[] = [];
  let lastEvaluatedKey: Record<string, any> | undefined;

  do {
    const response = await dynamo.send(
      new ScanCommand({
        TableName: TABLE_NAME,
        FilterExpression: 'sk = :link',
        ExpressionAttributeValues: {
          ':link': 'CANVAS_LINK',
        },
        ProjectionExpression: 'pk',
        ExclusiveStartKey: lastEvaluatedKey,
      }),
    );

    for (const item of response.Items ?? []) {
      const pk = typeof item.pk === 'string' ? item.pk : item.pk?.S;
      if (!pk || !pk.startsWith(USER_PK_PREFIX)) continue;
      subs.push(pk.slice(USER_PK_PREFIX.length));
    }

    lastEvaluatedKey = response.LastEvaluatedKey;
  } while (lastEvaluatedKey);

  return subs;
}
