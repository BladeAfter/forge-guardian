import { describe, expect, it, vi } from 'vitest';
import { LAUNCH_AT, launchAccess, launchInviter, launchStatus, mobileTelegramClient } from '../supabase/functions/_shared/launch';
import { launchSeconds, sampleLaunchClock } from './launchClock';
describe('launch access rules', () => {
  it('allows only verified admin 8490010993 before launch without public release', () => {
    const now = Date.parse('2026-10-10T01:27:00Z');
    expect(launchAccess(8490010993, now)).toMatchObject({ canEnter: true, released: false });
    for (const id of [8118569391, 8490010992, 42, 0]) expect(launchAccess(id, now).canEnter).toBe(false);
    expect(launchStatus(now).released).toBe(false);
  });
  it('releases only at October 12 18:00 UTC', () => {
    expect(LAUNCH_AT).toBe('2026-10-12T18:00:00Z');
    expect(launchStatus(Date.parse(LAUNCH_AT) - 1).released).toBe(false);
    expect(launchStatus(Date.parse(LAUNCH_AT)).released).toBe(true);
  });
  it('does not use the device wall clock for countdown', () => {
    const clock = sampleLaunchClock(LAUNCH_AT, '2026-10-12T17:59:00Z', 1000);
    const spy = vi.spyOn(Date, 'now').mockReturnValue(Date.parse('2030-01-01T00:00:00Z'));
    expect(launchSeconds(clock, 11000)).toBe(50);
    spy.mockReturnValue(0);
    expect(launchSeconds(clock, 11000)).toBe(50);
    spy.mockRestore();
  });
  it('accepts only mobile Telegram platforms with mobile user agents', () => {
    expect(mobileTelegramClient('android', 'Android')).toBe(true);
    expect(mobileTelegramClient('ios', 'iPhone')).toBe(true);
    expect(mobileTelegramClient('tdesktop', 'Android')).toBe(false);
    expect(mobileTelegramClient('android', 'Windows')).toBe(false);
  });
  it('accepts unique bot invitation IDs but rejects arbitrary and unsafe IDs', () => {
    expect(launchInviter('ref_8490010993')).toBe(8490010993);
    expect(launchInviter('ref_0')).toBeNull();
    expect(launchInviter('ref_9999999999999999')).toBeNull();
    expect(launchInviter('url')).toBeNull();
  });
});