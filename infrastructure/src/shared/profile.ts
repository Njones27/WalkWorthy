import { GetCommand } from '@aws-sdk/lib-dynamodb';
import { TABLE_NAME } from './env';
import { dynamo } from './dynamo';

export interface UserProfile {
  ageRange?: string;
  major?: string;
  gender?: string;
  hobbies?: string[];
  optInTailored?: boolean;
  translationPreference?: 'ESV' | 'KJV' | 'NIV' | 'NKJV' | 'NASB' | 'CSB' | 'NLT';
  updatedAt?: string;
}

const cache = new Map<string, UserProfile | undefined>();

export async function getUserProfileOnce(sub: string): Promise<UserProfile | undefined> {
  if (cache.has(sub)) return cache.get(sub);

  const res = await dynamo.send(
    new GetCommand({
      TableName: TABLE_NAME,
      Key: { pk: `USER#${sub}`, sk: 'PROFILE' },
    }),
  );
  const item = (res.Item as UserProfile | undefined) ?? undefined;
  cache.set(sub, item);
  return item;
}

export function clearUserProfileCache(sub?: string) {
  if (sub) cache.delete(sub);
  else cache.clear();
}

