import { randomUUID } from 'crypto';

import {
  GetCommand,
  PutCommand,
  QueryCommand,
  UpdateCommand,
} from '@aws-sdk/lib-dynamodb';

import { TABLE_NAME, CANVAS_CLIENT_SECRET_NAME } from '../shared/env';
import { dynamo } from '../shared/dynamo';
import { nowIso, futureEpochSeconds } from '../shared/time';
import { getUserProfileOnce } from '../shared/profile';
import { bibleMcpFromEnv } from '../lib/bibleMcp';
import { runVerseSelectionAgent } from '../lib/walkworthy-agent';
import { fetchPlannerItems } from '../lib/canvas-client';
import type { CanvasPlannerItem } from '../lib/canvas-client';
import { mapPlannerToStressfulItems, buildVerseCandidates } from '../lib/stress-heuristics';
import type {
  StressfulItem,
  VerseCandidate,
  Translation,
  UserProfilePayload,
} from '../lib/walkworthy-agent';

export type ScanStatus = 'SUCCESS' | 'FALLBACK';

export interface RunScanResult {
  encouragementId: string;
  status: ScanStatus;
  log: ScanLog;
}

export class CanvasLinkMissingError extends Error {
  constructor(sub: string) {
    super(`Canvas account not linked for ${sub}`);
    this.name = 'CanvasLinkMissingError';
  }
}

export async function runScanForUser(sub: string): Promise<RunScanResult> {
  const [canvasLinkRaw, profile] = await Promise.all([
    loadCanvasLink(sub),
    getUserProfileOnce(sub),
  ]);

  const canvasLink = toCanvasLinkRecord(canvasLinkRaw);
  if (!canvasLink) {
    throw new CanvasLinkMissingError(sub);
  }

  await clearPendingEncouragements(sub);

  const translationPref = normalizeTranslation(
    (profile?.translationPreference as string | undefined) ?? 'ESV',
  );

  const result = await executeScanPipeline({
    sub,
    canvasLink,
    profile: (profile ?? null) as UserProfilePayload | null,
    translation: translationPref,
  });

  await persistEncouragement(sub, result.encouragement);
  await recordScan(sub, result.log);

  return {
    encouragementId: result.encouragement.id,
    status: result.log.status,
    log: result.log,
  };
}

interface CanvasLinkRecord {
  canvasBaseUrl: string;
  refreshSecretArn: string;
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

  const items = (result.Items ?? []) as Array<{ pk: string; sk: string }>;

  await Promise.all(
    items.map(({ pk, sk }) =>
      dynamo.send(
        new UpdateCommand({
          TableName: TABLE_NAME,
          Key: { pk, sk },
          UpdateExpression: 'SET delivered = :true, deliveredAt = :at',
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

function normalizeTranslation(value: string): Translation {
  const upper = (value || 'ESV').toUpperCase();
  const allowed: Translation[] = ['ESV', 'KJV', 'NIV', 'NKJV', 'NASB', 'CSB', 'NLT'];
  return allowed.includes(upper as Translation) ? (upper as Translation) : 'ESV';
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

interface ScanPipelineParams {
  sub: string;
  canvasLink: CanvasLinkRecord;
  profile: UserProfilePayload | null;
  translation: Translation;
}

export interface ScanLog {
  encouragementId: string;
  status: ScanStatus;
  plannerCount: number;
  stressfulCount: number;
  candidateCount: number;
  translation: Translation;
  tags: string[];
  errorMessage?: string;
}

const BASE_FALLBACK_OPTIONS = [
  {
    ref: 'Philippians 4:6-7',
    text:
      'Do not be anxious about anything, but in everything by prayer and supplication with thanksgiving let your requests be made known to God.',
    encouragement:
      'God invites you to bring today’s stress to Him—take a pause, breathe, and ask for His peace.',
  },
  {
    ref: 'Isaiah 41:10',
    text:
      'Fear not, for I am with you; be not dismayed, for I am your God; I will strengthen you, I will help you, I will uphold you with my righteous right hand.',
    encouragement:
      'You are not facing today alone—lean on God’s strength and let Him hold you steady.',
  },
  {
    ref: 'Psalm 55:22',
    text:
      'Cast your burden on the Lord, and he will sustain you; he will never permit the righteous to be moved.',
    encouragement:
      'Lay every burden down in prayer and trust that God will carry what feels too heavy.',
  },
  {
    ref: 'Matthew 11:28-29',
    text:
      'Come to me, all who labor and are heavy laden, and I will give you rest. Take my yoke upon you, and learn from me, for I am gentle and lowly in heart, and you will find rest for your souls.',
    encouragement:
      'When your schedule feels relentless, rest in Jesus—He is gentle and ready to refresh your soul.',
  },
  {
    ref: '2 Timothy 1:7',
    text:
      'For God gave us a spirit not of fear but of power and love and self-control.',
    encouragement:
      'Step into today with courage—God equips you with a spirit of power, love, and a clear mind.',
  },
];

const DEFAULT_EXCLUDED_REFS = ['Philippians 4:6-7'];

function normalizeReference(ref: string | undefined): string {
  return (ref ?? '').replace(/\s+/g, ' ').trim().toLowerCase();
}

function parseExcludedRefs(): Set<string> {
  const raw = process.env.SCAN_EXCLUDED_VERSES;
  let values: string[] = DEFAULT_EXCLUDED_REFS;

  if (raw && raw.length > 0) {
    try {
      const parsed = JSON.parse(raw);
      if (Array.isArray(parsed)) {
        values = parsed.filter((entry): entry is string => typeof entry === 'string');
      } else if (typeof parsed === 'string') {
        values = [parsed];
      }
    } catch {
      values = raw.split(',').map((part) => part.trim()).filter(Boolean);
    }
  }

  const normalized = values
    .map((entry) => normalizeReference(entry))
    .filter((entry) => entry.length > 0);

  return new Set(normalized);
}

function excludeVerses<T extends { ref: string }>(items: T[], excluded: Set<string>): T[] {
  if (excluded.size === 0) {
    return items;
  }

  return items.filter((item) => !excluded.has(normalizeReference(item.ref)));
}

const EXCLUDED_REFS = parseExcludedRefs();

async function executeScanPipeline(
  params: ScanPipelineParams,
): Promise<{ encouragement: ReturnType<typeof finalizeEncouragement>; log: ScanLog }> {
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
    verseCandidates = excludeVerses(verseCandidates, EXCLUDED_REFS);

    const uniqueTags = Array.from(
      new Set(
        stressfulItems
          .flatMap((item) => item.stressTags ?? [])
          .map((tag) => tag.toLowerCase()),
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

    const agentResult = await runVerseSelectionAgent({
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
        stressfulItems
          .flatMap((item) => item.stressTags ?? [])
          .map((tag) => tag.toLowerCase()),
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

function pickFallbackEncouragement(translation: Translation) {
  const options = excludeVerses(BASE_FALLBACK_OPTIONS, EXCLUDED_REFS);
  const pool = options.length > 0 ? options : BASE_FALLBACK_OPTIONS;
  const choice = pool[Math.floor(Math.random() * pool.length)];
  return finalizeEncouragement(choice.ref, choice.text, choice.encouragement, translation);
}

function buildFallbackResult(args: {
  translation: Translation;
  plannerCount: number;
  stressfulCount: number;
  candidateCount: number;
  tags: string[];
  reason?: string;
}): { encouragement: ReturnType<typeof finalizeEncouragement>; log: ScanLog } {
  const encouragement = pickFallbackEncouragement(args.translation);

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
