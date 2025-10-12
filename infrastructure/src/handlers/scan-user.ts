import type { APIGatewayProxyEventV2 } from 'aws-lambda';

import { getUserSub } from '../shared/auth';
import { json, internalError, unauthorized } from '../shared/http';
import { runScanForUser, CanvasLinkMissingError } from '../services/scan-runner';

export async function handler(event: APIGatewayProxyEventV2) {
  const sub = getUserSub(event);
  if (!sub) {
    return unauthorized();
  }

  try {
    const result = await runScanForUser(sub);

    return json(202, {
      message: 'Scan accepted',
      encouragementId: result.encouragementId,
      status: result.status,
    });
  } catch (error) {
    if (error instanceof CanvasLinkMissingError) {
      return json(409, { message: 'Canvas account not linked' });
    }

    console.error('scanUser failed', error);
    return internalError();
  }
}
