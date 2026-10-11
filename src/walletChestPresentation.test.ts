import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const wallet = readFileSync(new URL('./pages/WalletPage.tsx', import.meta.url), 'utf8');
const pets = readFileSync(new URL('./pages/PetsPage.tsx', import.meta.url), 'utf8');

describe('wallet chest presentation', () => {
  it('does not render the mystery chest panel or its recovery button in the wallet', () => {
    expect(wallet).not.toContain('<MascotChestCard');
    expect(wallet).not.toContain("t('wallet.premiumEggs')");
    expect(wallet).not.toContain("t('wallet.receiveEgg')");
  });

  it('preserves paid purchase recovery and the mascot chest shop', () => {
    expect(wallet).toContain('reconcilePendingEggPurchases(telegramInitData)');
    expect(wallet).toContain('<PetEggOpeningOverlay');
    expect(pets).toContain('<MascotChestCard');
  });
});