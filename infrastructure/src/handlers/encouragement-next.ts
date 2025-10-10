export async function handler(event: unknown): Promise<{
  statusCode: number;
  headers?: Record<string, string>;
  body: string;
}> {
  console.log('encouragementNext received event', JSON.stringify(event));
  return {
    statusCode: 200,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      shouldNotify: false,
      message: 'encouragementNext placeholder — fetch pending encouragement later.',
    }),
  };
}
