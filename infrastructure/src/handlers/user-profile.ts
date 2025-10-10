export async function handler(event: unknown): Promise<{
  statusCode: number;
  headers?: Record<string, string>;
  body: string;
}> {
  console.log('userProfile received event', JSON.stringify(event));
  return {
    statusCode: 202,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      message: 'userProfile placeholder — persist profile details in DynamoDB.',
    }),
  };
}
