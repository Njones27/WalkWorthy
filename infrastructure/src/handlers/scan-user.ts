import type { APIGatewayProxyEventV2 } from 'aws-lambda';
import { GetCommand, PutCommand, QueryCommand, UpdateCommand } from '@aws-sdk/lib-dynamodb';
import { randomUUID } from 'crypto';
import { TABLE_NAME, CANVAS_CLIENT_SECRET_NAME } from '../shared/env';
import { dynamo } from '../shared/dynamo';
import { getUserSub } from '../shared/auth';
import {
  json,
  internalError,
  unauthorized,
} from '../shared/http';
import { futureEpochSeconds, nowIso } from '../shared/time';
import { getUserProfileOnce } from '../shared/profile';
import { bibleMcpFromEnv } from '../lib/bibleMcp';
import { pickVerseWithAgentKit } from '../lib/agentkit';
import { fetchPlannerItems } from '../lib/canvas-client';
import type { CanvasPlannerItem } from '../lib/canvas-client';
import { mapPlannerToStressfulItems, buildVerseCandidates } from '../lib/stress-heuristics';
import type { Translation, StressfulItem, VerseCandidate, UserProfilePayload } from '../lib/walkworthy-agent';

export async function handler(event: APIGatewayProxyEventV2) {
  const sub = getUserSub(event);
  if (!sub) {
    return unauthorized();
  }

  try {
    const [canvasLinkRaw, profile] = await Promise.all([
      loadCanvasLink(sub),
      getUserProfileOnce(sub),
    ]);
    const canvasLink = toCanvasLinkRecord(canvasLinkRaw);
    if (!canvasLink) {
      return json(409, { message: 'Canvas account not linked' });
    }

    await clearPendingEncouragements(sub);

    const translationPref = normalizeTranslation(profile?.translationPreference ?? 'ESV');
    const result = await executeScanPipeline({
      sub,
      canvasLink,
      profile: (profile ?? null) as UserProfilePayload | null,
      translation: translationPref,
    });

    await persistEncouragement(sub, result.encouragement);
    await recordScan(sub, result.log);

    return json(202, {
      message: 'Scan accepted',
      encouragementId: result.encouragement.id,
      status: result.log.status,
    });
  } catch (error) {
    console.error('scanUser failed', error);
    return internalError();
  }
}

async function loadCanvasLink(sub: string) {
  const result = await dynamo.send(
    new GetCommand({
      TableName: TABLE_NAME,
      Key: {
        pk: `USER#${sub}`,
        sk: 'CANVAS_LINK',
      },
    }),
  );

  return result.Item ?? null;
}

function toCanvasLinkRecord(raw: any): CanvasLinkRecord | null {
  if (!raw) return null;
  const baseUrl = typeof raw.canvasBaseUrl === 'string' ? raw.canvasBaseUrl : undefined;
  const refreshArn = typeof raw.refreshSecretArn === 'string' ? raw.refreshSecretArn : undefined;
  if (!baseUrl || !refreshArn) {
    return null;
  }
  return {
    canvasBaseUrl: baseUrl,
    refreshSecretArn: refreshArn,
  };
}

// Profile helper moved to shared/profile.ts and cached per invocation

async function clearPendingEncouragements(sub: string) {
  const result = await dynamo.send(
    new QueryCommand({
      TableName: TABLE_NAME,
      KeyConditionExpression: 'pk = :pk AND begins_with(sk, :prefix)',
      ExpressionAttributeValues: {
        ':pk': `USER#${sub}`,
        ':prefix': 'PENDING#',
      },
    }),
  );

  const now = nowIso();

  const items =
    (result.Items ?? []) as Array<{ pk: string; sk: string }>;

  await Promise.all(
    items.map(({ pk, sk }) =>
      dynamo.send(
        new UpdateCommand({
          TableName: TABLE_NAME,
          Key: {
            pk,
            sk,
          },
          UpdateExpression:
            'SET delivered = :true, deliveredAt = :at',
          ExpressionAttributeValues: {
            ':true': true,
            ':at': now,
          },
        }),
      ),
    ),
  );
}

async function persistEncouragement(
  sub: string,
  encouragement: ReturnType<typeof finalizeEncouragement>,
) {
  await dynamo.send(
    new PutCommand({
      TableName: TABLE_NAME,
      Item: {
        pk: `USER#${sub}`,
        sk: `PENDING#${encouragement.id}`,
        id: encouragement.id,
        ref: encouragement.ref,
        text: encouragement.text,
        encouragement: encouragement.encouragement,
        translation: encouragement.translation,
        createdAt: encouragement.createdAt,
        expiresAt: encouragement.expiresAtEpoch,
        expiresAtIso: encouragement.expiresAtIso,
        delivered: false,
      },
    }),
  );
}

async function recordScan(sub: string, log: ScanLog) {
  const createdAt = nowIso();

  await dynamo.send(
    new PutCommand({
      TableName: TABLE_NAME,
      Item: {
        pk: `USER#${sub}`,
        sk: `SCAN#${createdAt}`,
        createdAt,
        ...log,
      },
    }),
  );
}

function normalizeTranslation(
  t: string,
): Translation {
  const upper = (t || 'ESV').toUpperCase();
  const allowed = ['ESV', 'KJV', 'NIV', 'NKJV', 'NASB', 'CSB', 'NLT'] as const;
  return (allowed.includes(upper as any) ? (upper as any) : 'ESV');
}

function finalizeEncouragement(ref: string, text: string, encouragement: string, translation: string) {
  const createdAt = nowIso();
  const expiresAtEpoch = futureEpochSeconds(12);
  const expiresAtIso = new Date(expiresAtEpoch * 1000).toISOString();

  return {
    id: randomUUID(),
    ref,
    text,
    encouragement,
    translation,
    createdAt,
    expiresAtEpoch,
    expiresAtIso,
  };
}
interface ScanLog {
  encouragementId: string;
  status: 'SUCCESS' | 'FALLBACK';
  plannerCount: number;
  stressfulCount: number;
  candidateCount: number;
  translation: Translation;
  tags: string[];
  errorMessage?: string;
}

interface CanvasLinkRecord {
  canvasBaseUrl: string;
  refreshSecretArn: string;
}

async function executeScanPipeline(params: {
  sub: string;
  canvasLink: CanvasLinkRecord;
  profile: UserProfilePayload | null;
  translation: Translation;
}): Promise<{ encouragement: ReturnType<typeof finalizeEncouragement>; log: ScanLog }> {
  const { canvasLink, profile, translation } = params;
  const mcp = bibleMcpFromEnv();
  let plannerItems: CanvasPlannerItem[] = [];
  let stressfulItems: StressfulItem[] = [];
  let verseCandidates: VerseCandidate[] = [];

  try {
    if (!canvasLink.refreshSecretArn) {
      throw new Error('Canvas refresh secret missing');
    }

    plannerItems = await fetchPlannerItems({
      baseUrl: canvasLink.canvasBaseUrl,
      refreshSecretArn: canvasLink.refreshSecretArn,
      clientSecretName: CANVAS_CLIENT_SECRET_NAME,
    });

    stressfulItems = mapPlannerToStressfulItems(plannerItems, {
      translation,
      maxItems: 25,
    });

    verseCandidates = await buildVerseCandidates(mcp, stressfulItems, translation);

    const uniqueTags = Array.from(
      new Set(
        stressfulItems.flatMap((item) => item.stressTags ?? []).map((tag) => tag.toLowerCase()),
      ),
    );

    if (verseCandidates.length === 0) {
      return buildFallbackResult({
        translation,
        plannerCount: plannerItems.length,
        stressfulCount: stressfulItems.length,
        candidateCount: 0,
        tags: uniqueTags,
        reason: 'No verse candidates from MCP',
      });
    }

    const agentResult = await pickVerseWithAgentKit({
      profile,
      stressfulItems,
      verseCandidates,
      translationPreference: translation,
    });

    const encouragement = finalizeEncouragement(
      agentResult.ref,
      agentResult.text,
      agentResult.encouragement,
      agentResult.translation,
    );

    return {
      encouragement,
      log: {
        encouragementId: encouragement.id,
        status: 'SUCCESS',
        plannerCount: plannerItems.length,
        stressfulCount: stressfulItems.length,
        candidateCount: verseCandidates.length,
        translation,
        tags: uniqueTags,
      },
    };
  } catch (error) {
    console.error('Scan pipeline error', error);
    const uniqueTags = Array.from(
      new Set(
        stressfulItems.flatMap((item) => item.stressTags ?? []).map((tag) => tag.toLowerCase()),
      ),
    );

    return buildFallbackResult({
      translation,
      plannerCount: plannerItems.length,
      stressfulCount: stressfulItems.length,
      candidateCount: verseCandidates.length,
      tags: uniqueTags,
      reason: error instanceof Error ? error.message : 'Unknown error',
    });
  }
}

function buildFallbackResult(args: {
  translation: Translation;
  plannerCount: number;
  stressfulCount: number;
  candidateCount: number;
  tags: string[];
  reason?: string;
}): { encouragement: ReturnType<typeof finalizeEncouragement>; log: ScanLog } {
  const encouragement = finalizeEncouragement(
    'Philippians 4:6-7',
    'Do not be anxious about anything, but in everything by prayer and supplication with thanksgiving let your requests be made known to God.',
    'God invites you to bring today’s stress to Him—take a pause, breathe, and ask for His peace.',
    args.translation,
  );

  return {
    encouragement,
    log: {
      encouragementId: encouragement.id,
      status: 'FALLBACK',
      plannerCount: args.plannerCount,
      stressfulCount: args.stressfulCount,
      candidateCount: args.candidateCount,
      translation: args.translation,
      tags: args.tags,
      errorMessage: args.reason,
    },
  };
}
