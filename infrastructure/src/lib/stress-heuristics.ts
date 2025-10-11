import { Translation, StressfulItem, VerseCandidate } from './walkworthy-agent';
import { CanvasPlannerItem } from './canvas-client';
import { BibleMcpProvider } from './bibleMcp';

interface HeuristicOptions {
  translation: Translation;
  maxItems?: number;
  maxTags?: number;
}

const DEFAULT_TAGS = ['anxiety', 'stress', 'rest', 'peace'];

export function mapPlannerToStressfulItems(
  items: CanvasPlannerItem[],
  options: HeuristicOptions,
): StressfulItem[] {
  const mapped = items
    .map((item) => plannerToStressItem(item))
    .filter((item): item is StressfulItem => Boolean(item));
  return mapped.slice(0, options.maxItems ?? 20);
}

export async function buildVerseCandidates(
  mcp: BibleMcpProvider,
  stressfulItems: StressfulItem[],
  translation: Translation,
): Promise<VerseCandidate[]> {

  const tagCounts = new Map<string, number>();
  for (const item of stressfulItems) {
    for (const tag of item.stressTags ?? []) {
      const normalized = tag.toLowerCase();
      tagCounts.set(normalized, (tagCounts.get(normalized) ?? 0) + 1);
    }
  }

  for (const fallback of DEFAULT_TAGS) {
    if (!tagCounts.has(fallback)) {
      tagCounts.set(fallback, 1);
    }
  }

  const rankedTags = Array.from(tagCounts.entries())
    .sort((a, b) => b[1] - a[1])
    .slice(0, 4)
    .map(([tag]) => tag);

  const verses: VerseCandidate[] = [];
  const seen = new Set<string>();

  for (const tag of rankedTags) {
    try {
      const found = await mcp.searchByKeywords([tag], translation, 5);
      for (const candidate of found) {
        const key = candidate.ref.toLowerCase();
        if (seen.has(key)) continue;
        seen.add(key);
        verses.push({
          ref: candidate.ref,
          text: candidate.text,
          translation: candidate.translation,
        });
      }
    } catch (error) {
      console.warn('MCP search failed for tag', tag, error);
    }
    if (verses.length >= 8) break;
  }

  return verses.slice(0, 8);
}

function plannerToStressItem(item: CanvasPlannerItem): StressfulItem | null {
  const type = normalizeType(item.plannableType ?? item.contextType);
  const title = item.title?.trim();
  if (!title) return null;

  const dueAt = item.dueAt ?? item.todoDate ?? null;
  const dueDate = dueAt ? new Date(dueAt) : null;
  const now = new Date();

  const hoursUntilDue = dueDate ? (dueDate.getTime() - now.getTime()) / (1000 * 60 * 60) : undefined;
  const tags = new Set<string>();

  tags.add('encouragement');
  if (type === 'exam') {
    tags.add('exam');
    tags.add('courage');
  }
  if (type === 'assignment') {
    tags.add('assignment');
  }
  if (typeof item.pointsPossible === 'number' && item.pointsPossible >= 20) {
    tags.add('weight');
    tags.add('pressure');
  }
  if (hoursUntilDue !== undefined) {
    if (hoursUntilDue <= 48) tags.add('deadline');
    if (hoursUntilDue <= 6) tags.add('urgency');
    if (hoursUntilDue < 0) tags.add('overdue');
  }

  const stressTags = Array.from(tags).slice(0, 6);

  return {
    type,
    title,
    course: item.courseId,
    dueAt: dueDate ? dueDate.toISOString() : undefined,
    stressTags,
    weight: typeof item.pointsPossible === 'number' ? item.pointsPossible : undefined,
  };
}

function normalizeType(plannableType?: string): StressfulItem['type'] {
  const value = (plannableType ?? '').toLowerCase();
  if (value.includes('quiz') || value.includes('exam') || value.includes('test')) return 'exam';
  if (value.includes('discussion') || value.includes('assignment') || value.includes('essay')) return 'assignment';
  return 'event';
}
