export async function handler(event: unknown): Promise<void> {
  console.log('scanUser invoked', JSON.stringify(event));
  console.log('TODO: refresh Canvas token, fetch assignments, call Bedrock.');
}
