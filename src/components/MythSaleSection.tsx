import { MythTokenSalePanel } from './MythTokenSalePanel';

/**
 * MYTH TOKEN SALE screen: the original sale panel, untouched. The SPENDING EVENT
 * now lives in its own tab and never replaces the token sale.
 */
export function MythSaleSection({ telegramInitData }: { telegramInitData: string; onGoToWallet?: () => void }) {
  return <MythTokenSalePanel telegramInitData={telegramInitData} />;
}
