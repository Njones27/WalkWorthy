import type { APIGatewayProxyEventV2 } from 'aws-lambda';
import { PutCommand } from '@aws-sdk/lib-dynamodb';
import { TABLE_NAME } from '../shared/env';
import { parseJsonBody, unauthorized, badRequest, noContent, internalError } from '../shared/http';
import { getUserSub } from '../shared/auth';
import { dynamo } from '../shared/dynamo';
import { nowIso } from '../shared/time';

interface UserProfileRequest {
  ageRange?: string;
  major?: string;
  gender?: string;
  hobbies?: string[];
  optInTailored?: boolean;
}

export async function handler(event: APIGatewayProxyEventV2) {
  const sub = getUserSub(event);
  if (!sub) {
    return unauthorized();
  }

  try {
    const body = parseJsonBody<UserProfileRequest>(
      event.body,
      event.isBase64Encoded,
    );

    if (body.hobbies && !Array.isArray(body.hobbies)) {
      return badRequest('hobbies must be an array of strings');
    }

    await dynamo.send(
      new PutCommand({
        TableName: TABLE_NAME,
        Item: {
          pk: `USER#${sub}`,
          sk: 'PROFILE',
          ageRange: body.ageRange,
          major: body.major,
          gender: body.gender,
          hobbies: body.hobbies,
          optInTailored: Boolean(body.optInTailored),
          updatedAt: nowIso(),
        },
      }),
    );

    return noContent();
  } catch (error) {
    if (error instanceof SyntaxError) {
      return badRequest('Invalid JSON payload');
    }

    console.error('userProfile failed', error);
    return internalError();
  }
}
