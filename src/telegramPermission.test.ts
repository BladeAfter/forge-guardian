import { beforeEach, describe, expect, it, vi } from 'vitest';
vi.mock('./apiClient', () => ({ forgeAuthProbe: vi.fn() }));
describe('Telegram message consent', () => {
  beforeEach(() => { vi.resetModules(); });
  it('requests once and respects refusal', async () => {
    const { requestTelegramMessages } = await import('./telegram');
    const request = vi.fn((callback?: (allowed: boolean) => void) => callback?.(false));
    const app = { initData: 'test', ready: vi.fn(), expand: vi.fn(), requestWriteAccess: request };
    requestTelegramMessages(app);
    requestTelegramMessages(app);
    expect(request).toHaveBeenCalledTimes(1);
  });
  it('skips granted permission and unsupported clients', async () => {
    const { requestTelegramMessages } = await import('./telegram');
    const request = vi.fn();
    requestTelegramMessages({ initData: 'test', initDataUnsafe: { user: { id: 42, first_name: 'Test', allows_write_to_pm: true } }, ready: vi.fn(), expand: vi.fn(), requestWriteAccess: request });
    requestTelegramMessages({ initData: 'test', ready: vi.fn(), expand: vi.fn() });
    expect(request).not.toHaveBeenCalled();
  });
  it('captures native swipes during gameplay and restores them on exit', async () => {
    const { captureTelegramGameGestures } = await import('./telegram');
    const disableVerticalSwipes = vi.fn(), enableVerticalSwipes = vi.fn();
    const cleanup = captureTelegramGameGestures({ initData: 'test', ready: vi.fn(), expand: vi.fn(), disableVerticalSwipes, enableVerticalSwipes });
    expect(disableVerticalSwipes).toHaveBeenCalledOnce();
    expect(enableVerticalSwipes).not.toHaveBeenCalled();
    cleanup();
    expect(enableVerticalSwipes).toHaveBeenCalledOnce();
  });
  it('preserves disabled swipes and tolerates old clients', async () => {
    const { captureTelegramGameGestures } = await import('./telegram');
    const enableVerticalSwipes = vi.fn();
    captureTelegramGameGestures({ initData: 'test', ready: vi.fn(), expand: vi.fn(), isVerticalSwipesEnabled: false, disableVerticalSwipes: vi.fn(), enableVerticalSwipes })();
    expect(enableVerticalSwipes).not.toHaveBeenCalled();
    expect(() => captureTelegramGameGestures(undefined)()).not.toThrow();
  });
});