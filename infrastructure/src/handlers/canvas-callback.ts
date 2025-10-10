import type { APIGatewayProxyEventV2 } from 'aws-lambda';
import { PutCommand } from '@aws-sdk/lib-dynamodb';
import {
  CANVAS_CLIENT_SECRET_NAME,
  TABLE_NAME,
} from '../shared/env';
import { parseJsonBody, badRequest, internalError, json } from '../shared/http';
import { getSecretJson, upsertSecretJson } from '../shared/secrets';
import { dynamo } from '../shared/dynamo';
import { nowIso } from '../shared/time';

interface CanvasCallbackRequest {
  code: string;
  state: string;
  redirectUri?: string;
}

interface CanvasStatePayload {
  userSub: string;
  canvasBaseUrl: string;
  redirectUri?: string;
}

interface CanvasTokenResponse {
  access_token: string;
  refresh_token: string;
  expires_in?: number;
  user?: { id?: number | string };
}

interface CanvasClientSecret {
  clientId: string;
  clientSecret: string;
}

const USER_SECRET_PREFIX = 'walkworthy/canvas/user/';

export async function handler(event: APIGatewayProxyEventV2) {
  try {
    const body = parseJsonBody<CanvasCallbackRequest>(
      event.body,
      event.isBase64Encoded,
    );

    if (!body.code || !body.state) {
      return badRequest('Missing code or state');
    }

    const state = decodeState(body.state);
    if (!state.userSub || !state.canvasBaseUrl) {
      return badRequest('Invalid state payload');
    }

    const redirectUri = body.redirectUri ?? state.redirectUri;
    if (!redirectUri) {
      return badRequest('Missing redirect URI');
    }

    const clientSecret = await getSecretJson<CanvasClientSecret>(
      CANVAS_CLIENT_SECRET_NAME,
    );

    const token = await exchangeCanvasCode({
      baseUrl: state.canvasBaseUrl,
      code: body.code,
      client: clientSecret,
      redirectUri,
    });

    if (!token.refresh_token) {
      console.error('Canvas response missing refresh token', token);
      return json(502, { message: 'Canvas token response missing refresh token' });
    }

    const userSecretName = `${USER_SECRET_PREFIX}${state.userSub}`;
    const secretArn = await upsertSecretJson(userSecretName, {
      refreshToken: token.refresh_token,
      accessToken: token.access_token,
      obtainedAt: nowIso(),
      expiresInSeconds: token.expires_in ?? 3600,
    });

    const linkedAt = nowIso();

    await dynamo.send(
      new PutCommand({
        TableName: TABLE_NAME,
        Item: {
          pk: `USER#${state.userSub}`,
          sk: 'CANVAS_LINK',
          canvasBaseUrl: state.canvasBaseUrl,
          canvasUserId: token.user?.id ? String(token.user.id) : undefined,
          refreshSecretArn: secretArn,
          linkedAt,
          updatedAt: linkedAt,
        },
      }),
    );

    return json(200, { linked: true });
  } catch (error) {
    if (error instanceof SyntaxError) {
      return badRequest('Invalid JSON payload');
    }

    console.error('canvasCallback failed', error);
    return internalError();
  }
}

function decodeState(raw: string): CanvasStatePayload {
  try {
    const decoded = Buffer.from(raw, 'base64').toString('utf8');
    const parsed = JSON.parse(decoded);
    return parsed as CanvasStatePayload;
  } catch {
    return { userSub: '', canvasBaseUrl: '' };
  }
}

async function exchangeCanvasCode(params: {
  baseUrl: string;
  code: string;
  client: CanvasClientSecret;
  redirectUri: string;
}): Promise<CanvasTokenResponse> {
  const { baseUrl, code, client, redirectUri } = params;

  const tokenEndpoint = new URL('/login/oauth2/token', baseUrl).toString();
  const searchParams = new URLSearchParams({
    grant_type: 'authorization_code',
    client_id: client.clientId,
    client_secret: client.clientSecret,
    redirect_uri: redirectUri,
    code,
  });

  const response = await fetch(tokenEndpoint, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: searchParams.toString(),
  });

  if (!response.ok) {
    const text = await response.text();
    console.error('Canvas token exchange failed', response.status, text);
    throw new Error('Canvas token exchange failed');
  }

  return (await response.json()) as CanvasTokenResponse;
}
