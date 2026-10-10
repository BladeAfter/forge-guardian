export type LaunchClock = { remaining: number; sampledAt: number };
export function sampleLaunchClock(launchAt: string, serverNow: string, monotonicNow: number): LaunchClock {
  const launch = Date.parse(launchAt), server = Date.parse(serverNow);
  if (!Number.isFinite(launch) || !Number.isFinite(server)) throw new Error('Invalid server clock');
  return { remaining: Math.max(0, launch - server), sampledAt: monotonicNow };
}
export function launchSeconds(clock: LaunchClock, monotonicNow: number) {
  return Math.max(0, Math.ceil((clock.remaining - Math.max(0, monotonicNow - clock.sampledAt)) / 1000));
}