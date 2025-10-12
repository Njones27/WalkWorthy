import { getSecretJson, putSecretJson } from '../shared/secrets';

interface CanvasClientSecret {
  clientId: string;
  clientSecret: string;
}

interface CanvasTokenSecret {
  refreshToken: string;
  accessToken: string;
  obtainedAt: string;
  expiresInSeconds: number;
}

export interface CanvasPlannerItem {
  id: string;
  contextType?: string;
  courseId?: string;
  title?: string;
  todoDate?: string;
  dueAt?: string;
  pointsPossible?: number;
  plannableType?: string;
  htmlUrl?: string;
}

interface FetchPlannerOptions {
  baseUrl: string;
  refreshSecretArn: string;
  clientSecretName: string;
  lookaheadDays?: number;
}

const DEFAULT_LOOKAHEAD_DAYS = 14;

export interface CanvasContext {
  accessToken: string;
  baseUrl: string;
}

export async function fetchPlannerItems(options: FetchPlannerOptions): Promise<CanvasPlannerItem[]> {
  const { baseUrl } = options;
  const ctx = await ensureAccessToken(options);

  const start = new Date().toISOString();
  const end = new Date(Date.now() + (options.lookaheadDays ?? DEFAULT_LOOKAHEAD_DAYS) * 24 * 60 * 60 * 1000).toISOString();

  const items: CanvasPlannerItem[] = [];
  let url = new URL('/api/v1/planner/items', baseUrl);
  url.searchParams.set('start_date', start);
  url.searchParams.set('end_date', end);
  url.searchParams.set('per_page', '50');

  while (url) {
    const res = await fetch(url.toString(), {
      headers: {
        Authorization: `Bearer ${ctx.accessToken}`,
      },
    });

    if (res.status === 401) {
      // Access token expired unexpectedly; force refresh and retry once.
      const refreshed = await refreshAccessToken(options);
      if (!refreshed) {
        throw new Error('Unable to refresh Canvas access token');
      }
      return fetchPlannerItems(options);
    }

    if (!res.ok) {
      const text = await res.text();
      throw new Error(`Canvas planner request failed: ${res.status} ${text}`);
    }

    const data = (await res.json()) as any[];
    for (const item of data) {
      if (!item) continue;
      const plannable = item.plannable ?? {};
      items.push({
        id: String(item.id ?? plannable.id ?? Date.now()),
        contextType: item.context_type,
        courseId: item.course_id ? String(item.course_id) : undefined,
        title: plannable.title ?? item.title,
        todoDate: item.todo_date ?? plannable.todo_date,
        dueAt: item.due_at ?? plannable.due_at,
        pointsPossible: plannable.points_possible,
        plannableType: plannable?.plannable_type ?? item.plannable_type,
        htmlUrl: plannable.html_url ?? item.html_url,
      });
    }

    const nextLink = parseNextLink(res.headers.get('link'));
    url = nextLink ? new URL(nextLink) : undefined as any;
  }

  return items;
}

async function ensureAccessToken(options: FetchPlannerOptions): Promise<CanvasContext> {
  const rawToken = await getSecretJson<CanvasTokenSecret>(options.refreshSecretArn);
  const { value: token, changed } = normalizeTokenSecret(rawToken);

  if (changed) {
    await putSecretJson(options.refreshSecretArn, token);
  }
  const now = new Date();
  const obtainedAt = new Date(token.obtainedAt);
  const expiresAt = new Date(obtainedAt.getTime() + token.expiresInSeconds * 1000);

  if (expiresAt.getTime() - 60_000 > now.getTime()) {
    return { accessToken: token.accessToken, baseUrl: options.baseUrl };
  }

  const refreshed = await refreshAccessToken(options);
  if (!refreshed) {
    throw new Error('Failed to refresh Canvas access token');
  }
  return { accessToken: refreshed.accessToken, baseUrl: options.baseUrl };
}

async function refreshAccessToken(options: FetchPlannerOptions): Promise<CanvasTokenSecret | undefined> {
  const { clientId, clientSecret } = await getSecretJson<CanvasClientSecret>(options.clientSecretName);
  const rawTokenSecret = await getSecretJson<CanvasTokenSecret>(options.refreshSecretArn);
  const { value: tokenSecret, changed: tokenSecretChanged } = normalizeTokenSecret(rawTokenSecret);

  if (tokenSecretChanged) {
    await putSecretJson(options.refreshSecretArn, tokenSecret);
  }

  const endpoint = new URL('/login/oauth2/token', options.baseUrl);
  const res = await fetch(endpoint.toString(), {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'refresh_token',
      client_id: clientId,
      client_secret: clientSecret,
      refresh_token: tokenSecret.refreshToken,
    }).toString(),
  });

  if (!res.ok) {
    const text = await res.text();
    console.error('Canvas token refresh failed', res.status, text);
    return undefined;
  }

  const json = (await res.json()) as {
    access_token: string;
    refresh_token?: string;
    expires_in?: number;
  };

  const updated: CanvasTokenSecret = {
    refreshToken: (json.refresh_token ?? tokenSecret.refreshToken).trim(),
    accessToken: (json.access_token ?? '').trim(),
    obtainedAt: new Date().toISOString(),
    expiresInSeconds: json.expires_in ?? tokenSecret.expiresInSeconds ?? 3600,
  };

  const { value: normalizedUpdated } = normalizeTokenSecret(updated);

  await putSecretJson(options.refreshSecretArn, normalizedUpdated);
  return normalizedUpdated;
}

function parseNextLink(header: string | null): string | undefined {
  if (!header) return undefined;
  const links = header.split(',');
  for (const link of links) {
    const match = link.match(/<([^>]+)>;\s*rel="next"/);
    if (match) return match[1];
  }
  return undefined;
}

function normalizeTokenSecret(secret: CanvasTokenSecret): {
  value: CanvasTokenSecret;
  changed: boolean;
} {
  const trimmedAccessToken = (secret.accessToken ?? '').trim();
  const trimmedRefreshToken = (secret.refreshToken ?? '').trim();
  const changed =
    trimmedAccessToken !== secret.accessToken ||
    trimmedRefreshToken !== secret.refreshToken;

  if (!changed) {
    return { value: secret, changed: false };
  }

  return {
    value: {
      ...secret,
      accessToken: trimmedAccessToken,
      refreshToken: trimmedRefreshToken,
    },
    changed: true,
  };
}
