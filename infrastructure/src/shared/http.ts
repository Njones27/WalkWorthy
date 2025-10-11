export function json(statusCode: number, body: unknown) {
  return {
    statusCode,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  };
}

export function noContent() {
  return { statusCode: 204, headers: {}, body: '' };
}

export function badRequest(message: string) {
  return json(400, { message });
}

export function unauthorized(message = 'Unauthorized') {
  return json(401, { message });
}

export function internalError() {
  return json(500, { message: 'Internal server error' });
}

export function parseJsonBody<T>(
  body: string | null | undefined,
  isBase64Encoded: boolean | undefined,
): T {
  if (!body) {
    throw new Error('Missing request body');
  }

  const decoded = isBase64Encoded
    ? Buffer.from(body, 'base64').toString('utf8')
    : body;

  return JSON.parse(decoded) as T;
}
