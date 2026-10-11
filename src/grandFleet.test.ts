import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { translate } from './i18n';

const source = (path: string) => readFileSync(new URL(path, import.meta.url), 'utf8');
const initial = source('../drizzle/migrations/0122_grand_fleet_leader_gameplay_bonus.sql');
const stable = source('../drizzle/migrations/0123_grand_fleet_stable_reward_sources.sql');

describe('Grand Fleet server-owned captain bonus', () => {
  it('brands the supported languages and explains additive rewards', () => {
    for (const lang of ['pt', 'en', 'es', 'ru', 'tr'] as const) {
      expect(translate(lang, 'clan.title')).toBe('Grand Fleet');
      expect(translate(lang, 'fleet.bonusDescription')).toContain('100%');
      expect(translate(lang, 'fleet.bonusExclusions')).toContain('TON');
    }
  });
  it('keeps the ledger private with explicit grants and RLS', () => {
    expect(initial.indexOf('GRANT ALL ON public.grand_fleet_bonus_ledger')).toBeLessThan(initial.indexOf('ENABLE ROW LEVEL SECURITY'));
    expect(initial).toContain('REVOKE ALL ON FUNCTION public.grand_fleet_credit_bonus(uuid,text,numeric,text,text) FROM PUBLIC,anon,authenticated');
    expect(initial).toContain('UNIQUE(member_id,asset,source_type,source_id)');
    expect(initial).toContain('ON CONFLICT DO NOTHING RETURNING id INTO record_id');
    expect(initial).toContain('IF record_id IS NULL THEN RETURN');
  });
  it('credits the actual captain and never deducts from crew', () => {
    expect(initial).toContain("role='leader'");
    expect(initial).toContain('c.leader_user_id=p_member');
    expect(initial).toContain('forge_coins=forge_coins+bonus');
    expect(initial).not.toContain('forge_coins=forge_coins-bonus');
    expect(stable).toContain('bonus_amount=reward_amount*0.05');
  });
  it('uses permanent settlement keys and separate asset allowlists', () => {
    expect(stable).toContain('p.id::text');
    expect(stable).toContain('p_run::text');
    expect(stable).toContain('cyc.id::text');
    expect(stable).toContain("p_asset=''BERRIES'' THEN");
    expect(stable).toContain("''explore_extracted'',''explore_cleared''");
    expect(stable).toContain('btrim(p_source)');
  });
  it('only attaches boss bonuses to eligible settlement, not generic delivery', () => {
    expect(stable).toContain("proname='clan_boss_settle'");
    expect(stable).toContain('COALESCE((v_reward->>');
    expect(stable).toContain("regexp_replace(d,' PERFORM public.grand_fleet_credit_bonus");
  });
  it('does not add bonuses to paid passes, deposits, purchases or transfers', () => {
    const allowed = stable.split("IF p_asset=''BERRIES'' THEN")[1].split('END IF;')[0];
    for (const forbidden of ['claim_season_pass_reward', 'deposit', 'purchase', 'transfer', 'gift', 'naval', 'grand_fleet_bonus']) expect(allowed).not.toContain(forbidden);
    expect(initial).not.toContain('AFTER UPDATE ON public.game_players');
  });
  it('reads the bonus from the authenticated dashboard and preserves clan actions', () => {
    expect(source('../supabase/functions/game-api/index.ts')).toContain("rpc(db, 'grand_fleet_bonus_state', { p_telegram_id: user.id })");
    const ui = source('./pages/ClanHubPage.tsx');
    expect(ui).toContain('data.leaderBonus');
    expect(ui).toContain('data.antiAbuse?.cooldown?.active');
    expect(ui).toContain('grandFleetArt.deck');
    expect(ui).not.toContain('grand_fleet_credit_bonus');
  });
});