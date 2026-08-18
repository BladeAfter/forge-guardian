/**
 * NFT MINING — active currency (TON or MYTH).
 *
 * The server is the single source of truth: `hero_mining_settings.mining_currency`
 * plus `myth_per_day`. The client only READS this config to render the DAILY MINING
 * card in the right currency — it never decides the currency nor the reward.
 *
 * Eligibility never changes here: an NFT/hero that mines nothing (TON rate 0) keeps
 * mining nothing, and its mining block stays hidden.
 */
import { useEffect } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';

export type MiningCurrency = 'ton' | 'myth';

export type MiningConfig = {
  enabled: boolean;
  currency: MiningCurrency;
  /** Admin-defined daily amount used when the active currency is MYTH. */
  mythPerDay: number;
  updatedAt: string | null;
  currencyChangedAt: string | null;
};

export const DEFAULT_MINING_CONFIG: MiningConfig = {
  enabled: true, currency: 'ton', mythPerDay: 0, updatedAt: null, currencyChangedAt: null,
};

export const MINING_QUERY_KEY = ['mining-config'] as const;

async function fetchMiningConfig(): Promise<MiningConfig> {
  const { data, error } = await supabase
    .from('hero_mining_settings')
    .select('enabled, mining_currency, myth_per_day, updated_at, currency_changed_at')
    .maybeSingle();
  if (error || !data) return DEFAULT_MINING_CONFIG;
  const row = data as Record<string, unknown>;
  return {
    enabled: Boolean(row.enabled ?? true),
    currency: String(row.mining_currency ?? 'ton') === 'myth' ? 'myth' : 'ton',
    mythPerDay: Number(row.myth_per_day ?? 0),
    updatedAt: (row.updated_at as string) ?? null,
    currencyChangedAt: (row.currency_changed_at as string) ?? null,
  };
}

/**
 * Live mining config. A Realtime subscription pushes the admin currency switch to
 * every open screen, so TON → MYTH (and back) applies without a deploy.
 */
export function useMiningConfig(): MiningConfig {
  const client = useQueryClient();
  const { data } = useQuery({
    queryKey: MINING_QUERY_KEY,
    queryFn: fetchMiningConfig,
    staleTime: 15_000,
    refetchInterval: 60_000,
  });

  useEffect(() => {
    const channel = supabase
      .channel('mining-config')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'hero_mining_settings' }, () => {
        void client.invalidateQueries({ queryKey: MINING_QUERY_KEY });
        // Player-facing mining state (rate + claimable) is recomputed by the server.
        void client.invalidateQueries({ queryKey: ['hero-mining'] });
        void client.invalidateQueries({ queryKey: ['nft-hero-shop'] });
        void client.invalidateQueries({ queryKey: ['nft-shop'] });
      })
      .subscribe();
    return () => { void supabase.removeChannel(channel); };
  }, [client]);

  return data ?? DEFAULT_MINING_CONFIG;
}

/** Ticker shown next to the amount: 💎 TON or 🪙 MYTH. */
export function miningSymbol(currency: MiningCurrency): string {
  return currency === 'myth' ? 'MYTH' : 'TON';
}

/**
 * Daily mining of an item in the ACTIVE currency.
 * `tonPerDay` is only used as the eligibility gate (0 => no mining at all):
 * MYTH amounts are never derived from a TON price, they come from the admin value.
 */
export function effectiveDailyMining(tonPerDay: number | null | undefined, config: MiningConfig): number {
  const base = Number(tonPerDay ?? 0);
  if (!(base > 0)) return 0;
  return config.currency === 'myth' ? Math.max(0, Number(config.mythPerDay ?? 0)) : base;
}

/** Amount formatting per currency: MYTH is a whole-ish token, TON keeps small decimals. */
export function formatMiningAmount(value: number | null | undefined, currency: MiningCurrency, digits = 4): string {
  const amount = Number(value ?? 0);
  if (currency === 'myth') return amount.toLocaleString('en-US', { maximumFractionDigits: 2 });
  if (amount === 0) return '0';
  if (amount < 0.0001) return amount.toFixed(6).replace(/0+$/, '').replace(/\.$/, '');
  return amount.toFixed(digits).replace(/0+$/, '').replace(/\.$/, '');
}

/** `500 MYTH` / `0.2 TON` — one single label used by every mining card. */
export function formatMiningWithSymbol(value: number | null | undefined, currency: MiningCurrency, digits = 4): string {
  return `${formatMiningAmount(value, currency, digits)} ${miningSymbol(currency)}`;
}
