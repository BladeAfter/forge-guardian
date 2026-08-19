import { useQuery } from '@tanstack/react-query';
import { supabase } from './services';


export type PremiumTitleEntry = { userId: string; telegramId: string; username: string; title: string };
export type PremiumTitleMap = Record<string, string>;

/** Titles are a public cosmetic that replaces the @username everywhere (profile + every ranking). */
export function usePremiumTitles() {
  const query = useQuery({
    queryKey: ['premium-titles'],
    staleTime: 5 * 60 * 1000,
    queryFn: async (): Promise<PremiumTitleMap> => {
      if (!supabase) return {};
      const { data, error } = await supabase.rpc('list_premium_titles');
      if (error) throw error;
      const rows = (Array.isArray(data) ? data : []) as PremiumTitleEntry[];

      const map: PremiumTitleMap = {};
      for (const row of rows) {
        if (!row?.title) continue;
        if (row.userId) map[row.userId] = row.title;
        if (row.telegramId) map[row.telegramId] = row.title;
        if (row.username) map[`@${row.username.toLowerCase()}`] = row.title;
      }
      return map;
    }
  });
  return query.data ?? {};
}

export function resolvePremiumTitle(
  titles: PremiumTitleMap,
  ids: { userId?: string | null; telegramId?: string | null; username?: string | null }
): string | null {
  if (ids.userId && titles[ids.userId]) return titles[ids.userId];
  if (ids.telegramId && titles[ids.telegramId]) return titles[ids.telegramId];
  if (ids.username && titles[`@${ids.username.toLowerCase()}`]) return titles[`@${ids.username.toLowerCase()}`];
  return null;
}

/** Renders the premium title when the player owns one, otherwise the plain @username. */
export function PlayerHandle({
  titles,
  userId,
  telegramId,
  username,
  fallback,
  className = ''
}: {
  titles: PremiumTitleMap;
  userId?: string | null;
  telegramId?: string | null;
  username?: string | null;
  fallback?: string | null;
  className?: string;
}) {
  const title = resolvePremiumTitle(titles, { userId, telegramId, username });
  if (title) return <span className={`premium-title ${className}`.trim()}>👑 {title}</span>;
  if (username) return <span className={className}>@{username}</span>;
  return <span className={className}>{fallback ?? ''}</span>;
}

/** Self-contained tag: fetches the (cached) title map itself so any ranking row can use it. */
export function PlayerTag({
  userId,
  telegramId,
  username,
  fallback,
  className = ''
}: {
  userId?: string | null;
  telegramId?: string | null;
  username?: string | null;
  fallback?: string | null;
  className?: string;
}) {
  const titles = usePremiumTitles();
  const title = resolvePremiumTitle(titles, { userId, telegramId, username });
  if (title) return <span className={`premium-title block truncate ${className}`.trim()}>👑 {title}</span>;
  if (username) return <span className={`block truncate ${className}`.trim()}>@{username}</span>;
  if (fallback) return <span className={`block truncate ${className}`.trim()}>{fallback}</span>;
  return null;
}
