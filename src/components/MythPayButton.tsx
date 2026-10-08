import { Flame } from 'lucide-react';
import { formatMyth, mythDiscountLabel, mythPrice, type MythFeatureCode, type MythUtilityState } from '../mythUtility';

/**
 * Shared MYTH payment button.
 *
 * It is always an EXTRA option next to the existing BERRIES/TON buttons: the price comes from the
 * backend rate/discount and the amount is burned on success. Never rendered when the backend
 * has MYTH (globally or per feature) turned off.
 */
export function MythPayButton({
  state,
  feature,
  fc = 0,
  ton = 0,
  quantity = 1,
  disabled,
  onPay,
  className = '',
}: {
  state: MythUtilityState | null | undefined;
  feature: MythFeatureCode;
  fc?: number;
  ton?: number;
  quantity?: number;
  disabled?: boolean;
  onPay: (mythAmount: number) => void;
  className?: string;
}) {
  const unit = mythPrice(state, feature, { fc, ton });
  if (unit === null) return null;
  const total = unit * Math.max(1, quantity);
  const balance = Number(state?.available ?? 0);
  const missing = balance < total;
  const discount = mythDiscountLabel(state);
  return (
    <button
      type="button"
      disabled={disabled || missing}
      onClick={() => onPay(total)}
      className={`flex w-full items-center justify-center gap-1.5 rounded-xl border border-fuchsia-300/40 bg-fuchsia-500/15 py-2 text-[9px] font-black uppercase tracking-wide text-fuchsia-100 disabled:grayscale disabled:opacity-40 ${className}`}
    >
      <Flame className="h-3 w-3" />
      {missing ? `MYTH insuficiente (${formatMyth(total)})` : `Pagar ${formatMyth(total)} MYTH`}
      {!missing && discount ? <span className="rounded bg-fuchsia-300/20 px-1 text-[8px]">{discount}</span> : null}
    </button>
  );
}

/** Small helper line: available balance + total burned by this player. */
export function MythBalanceHint({ state }: { state: MythUtilityState | null | undefined }) {
  if (!state?.enabled) return null;
  return (
    <p className="mt-1 text-center text-[8px] uppercase tracking-wide text-fuchsia-200/70">
      MYTH disponível: {formatMyth(state.available)} · queimado por você: {formatMyth(state.mySpentMyth)}
      {Number(state.staked) > 0 ? ` · em staking (não gastável): ${formatMyth(state.staked)}` : ''}
    </p>
  );
}
