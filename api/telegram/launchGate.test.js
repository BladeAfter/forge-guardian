import { describe, expect, it } from 'vitest';
import { legacyLaunchGate } from './launchGate.js';
describe('legacy game admission', () => {
  function response() { return { code: 0, body: null, status(code) { this.code = code; return this; }, json(body) { this.body = body; return this; } }; }
  it('blocks every legacy request before launch', () => {
    const res = response();
    expect(legacyLaunchGate({ body: { platform: 'android' }, headers: { 'user-agent': 'Android' } }, res, Date.parse('2026-10-12T17:59:59Z'))).toBe(true);
    expect(res.code).toBe(423);
  });
  it('continues denying desktop at launch', () => {
    const res = response();
    expect(legacyLaunchGate({ body: { platform: 'tdesktop' }, headers: { 'user-agent': 'Windows' } }, res, Date.parse('2026-10-12T18:00:00Z'))).toBe(true);
    expect(res.code).toBe(403);
  });
  it('allows mobile requests to reach their existing signed authentication after launch', () => {
    expect(legacyLaunchGate({ body: { platform: 'ios' }, headers: { 'user-agent': 'iPhone' } }, response(), Date.parse('2026-10-12T18:00:00Z'))).toBe(false);
  });
});