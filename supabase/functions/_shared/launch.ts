export const LAUNCH_AT = '2026-10-12T18:00:00Z';
// Only pass an identity validated from signed Telegram initData, never a body ID.
export function launchAccess(verifiedTelegramId: number, now = Date.now()) {
  const status = launchStatus(now);
  return { ...status, canEnter: status.released || verifiedTelegramId === 8490010993 };
}
export function launchStatus(now = Date.now()) {
  return { launchAt: LAUNCH_AT, serverNow: new Date(now).toISOString(), released: now >= Date.parse(LAUNCH_AT) };
}
export function mobileTelegramClient(platform: unknown, agent: string) {
  return (platform === 'android' || platform === 'ios') && /Android|iPhone|iPad|iPod/i.test(agent);
}
export function launchInviter(value: unknown): number | null {
  if (typeof value !== 'string' || !/^ref_[1-9]\d{0,15}$/.test(value)) return null;
  const id = Number(value.slice(4));
  return Number.isSafeInteger(id) ? id : null;
}