/** Presentation only: never delete ownership or alter settlement records. */
export function isHiddenVeteranItem(item: unknown): boolean {
  if (!item || typeof item !== 'object') return false;
  const fields = item as Record<string, unknown>;
  return ['premiumSource', 'premium_source', 'code', 'itemId', 'heroKey', 'key', 'name', 'title', 'source', 'templateKey', 'template_key'].some(key => /veteran|veterano/i.test(String(fields[key] ?? '')));
}