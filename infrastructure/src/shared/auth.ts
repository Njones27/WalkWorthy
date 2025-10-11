import type { APIGatewayProxyEventV2 } from 'aws-lambda';

export function getUserSub(
  event: APIGatewayProxyEventV2,
): string | undefined {
  const claims =
    (event.requestContext as { authorizer?: { jwt?: { claims?: unknown } } })
      ?.authorizer?.jwt?.claims ?? {};

  if (typeof claims !== 'object' || !claims) {
    return undefined;
  }

  const sub = (claims as Record<string, unknown>).sub;
  return typeof sub === 'string' ? sub : undefined;
}
