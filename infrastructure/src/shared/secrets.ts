import {
  SecretsManagerClient,
  CreateSecretCommand,
  PutSecretValueCommand,
  GetSecretValueCommand,
} from '@aws-sdk/client-secrets-manager';

const client = new SecretsManagerClient({});

export async function getSecretJson<T>(secretId: string): Promise<T> {
  const { SecretString } = await client.send(
    new GetSecretValueCommand({ SecretId: secretId }),
  );

  if (!SecretString) {
    throw new Error(`Secret ${secretId} has no string value`);
  }

  return JSON.parse(SecretString) as T;
}

export async function getSecretString(secretId: string): Promise<string> {
  const { SecretString } = await client.send(
    new GetSecretValueCommand({ SecretId: secretId }),
  );
  if (!SecretString) {
    throw new Error(`Secret ${secretId} has no string value`);
  }
  return SecretString;
}

export async function putSecretJson(secretId: string, value: unknown) {
  const payload = JSON.stringify(value);
  await client.send(
    new PutSecretValueCommand({
      SecretId: secretId,
      SecretString: payload,
    }),
  );
}

export async function upsertSecretJson(
  secretId: string,
  value: unknown,
): Promise<string> {
  const payload = JSON.stringify(value);

  try {
    const response = await client.send(
      new CreateSecretCommand({
        Name: secretId,
        SecretString: payload,
      }),
    );
    return response.ARN ?? secretId;
  } catch (error) {
    if (
      error &&
      typeof error === 'object' &&
      (error as { name?: string }).name === 'ResourceExistsException'
    ) {
      const response = await client.send(
        new PutSecretValueCommand({
          SecretId: secretId,
          SecretString: payload,
        }),
      );
      return response.ARN ?? secretId;
    }

    throw error;
  }

  return secretId;
}
