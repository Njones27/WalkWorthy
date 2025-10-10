export async function handler(event: unknown): Promise<void> {
  console.log('notifyUser invoked', JSON.stringify(event));
  console.log('TODO: deliver encouragement via local notification plumbing.');
}
