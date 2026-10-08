import { MythSaleMilestones } from './MythSaleMilestones';
import { MythTokenSalePanel } from './MythTokenSalePanel';

/**
 * MYTH TOKEN SALE screen: the original sale panel plus the milestone/chest ladder.
 * The SPENDING EVENT lives in its own tab and is never affected by this section.
 */
export function MythSaleSection({ telegramInitData }: { telegramInitData: string; onGoToWallet?: () => void }) {
  return (
    <>
      <MythTokenSalePanel telegramInitData={telegramInitData} />
      <MythSaleMilestones telegramInitData={telegramInitData} />
    </>
  );
}
