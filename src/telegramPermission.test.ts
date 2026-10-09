import { beforeEach, describe, expect, it, vi } from 'vitest';
vi.mock('./apiClient', () => ({ forgeAuthProbe: vi.fn() }));
describe('Telegram message consent', () => {
  beforeEach(() => vi.resetModules());
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
});