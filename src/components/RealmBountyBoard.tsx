import { useLocalizedText } from '../LanguageContext';
import { useMemo } from 'react';
import type { RealmBounty } from '../realm';
import { useT } from '../LanguageContext';
import type { Translator } from '../i18n';
import { coin } from '../gameAssets';

const BOARD_BG = '/assets/game/realm/bounty-board-bg.jpg';
const FC_ICON = coin;
const FRAG_ICON = '/assets/game/realm/mat-crystal-shard.png';

const TYPE_ART: Record<string, { icon: string; hintKey: string }> = {
  expedition: { icon: '/assets/game/realm/bounty-icon-expedition.png', hintKey: 'realm.bounty.hint.expedition' },
  ruin: { icon: '/assets/game/realm/bounty-icon-ruin.png', hintKey: 'realm.bounty.hint.ruin' },
  craft: { icon: '/assets/game/realm/bounty-icon-craft.png', hintKey: 'realm.bounty.hint.craft' },
  upgrade: { icon: '/assets/game/realm/bounty-icon-upgrade.png', hintKey: 'realm.bounty.hint.upgrade' },
};

const fmt = (n: number) => new Intl.NumberFormat('pt-BR').format(Math.floor(n || 0));

type State = 'claimable' | 'progress' | 'claimed';

const stateOf = (b: RealmBounty): State => {
  if (b.status === 'claimed') return 'claimed';
  return b.progress >= b.target ? 'claimable' : 'progress';
};

const STATE_KEY: Record<State, string> = {
  claimable: 'realm.bounty.state.claimable',
  progress: 'realm.bounty.state.progress',
  claimed: 'realm.bounty.state.claimed',
};

function resetIn(now: number) {
  const d = new Date(now);
  const next = Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate() + 1, 0, 0, 0);
  const s = Math.max(0, Math.floor((next - now) / 1000));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  return `${h}h ${String(m).padStart(2, '0')}m`;
}

function RewardChips({ b }: { b: RealmBounty }) {
  const localizeText = useLocalizedText();

  const fc = b.reward.fc ?? 0;
  const frags = b.reward.fragments ?? 0;
  return (
    <div className="flex flex-wrap items-center gap-1.5">
      {fc > 0 && (
        <span className="bounty-chip">
          <img src={FC_ICON} alt="BERRIES" loading="lazy" className="h-4 w-4 object-contain" />
          <b>{fmt(fc)}</b> BERRIES
        </span>
      )}
      {frags > 0 && (
        <span className="bounty-chip bounty-chip--blue">
          <img src={FRAG_ICON} alt="" loading="lazy" className="h-4 w-4 object-contain" />
          <b>{frags}</b> {localizeText("frag. ")}</span>
      )}
    </div>
  );
}

function ProgressBar({ pct, state }: { pct: number; state: State }) {
  return (
    <div className={`bounty-track bounty-track--${state}`}>
      <div className="bounty-fill" style={{ width: `${pct}%` }} />
    </div>
  );
}

function BountyCard({
  b, featured, busy, onClaim, index,
}: { b: RealmBounty; featured?: boolean; busy: boolean; onClaim: () => void; index: number }) {
  const t: Translator = useT();
  const art = TYPE_ART[b.bounty_type] ?? TYPE_ART.expedition;
  const state = stateOf(b);
  const cur = Math.min(b.progress, b.target);
  const pct = Math.min(100, (cur / Math.max(1, b.target)) * 100);

  return (
    <article
      className={`bounty-card bounty-card--${state} ${featured ? 'bounty-card--featured' : ''}`}
      style={{ animationDelay: `${Math.min(index, 8) * 55}ms` }}
    >
      {featured && <span className="bounty-featured-tag">{t('realm.bounty.featured')}</span>}
      <div className="flex items-start gap-3">
        <div className={`bounty-icon ${featured ? 'bounty-icon--lg' : ''}`}>
          <img src={art.icon} alt="" loading="lazy" className="h-full w-full object-contain" />
        </div>
        <div className="min-w-0 flex-1">
          <div className="flex items-start justify-between gap-2">
            <b className={`block ${featured ? 'text-[14px]' : 'text-[12px]'} font-black leading-tight text-amber-50`}>{b.title}</b>
            <span className={`bounty-status bounty-status--${state}`}>{t(STATE_KEY[state])}</span>
          </div>
          <p className="mt-1 text-[9.5px] leading-snug text-slate-400">{t(art.hintKey)}</p>
        </div>
      </div>

      <div className="mt-3 space-y-1.5">
        <div className="flex items-center justify-between text-[9px] font-bold uppercase tracking-[.14em] text-slate-500">
          <span>{t('realm.bounty.progress')}</span>
          <span className="tabular-nums text-amber-200/90">{cur}/{b.target}</span>
        </div>
        <ProgressBar pct={pct} state={state} />
      </div>

      <div className="mt-3 flex items-end justify-between gap-3">
        <div className="space-y-1">
          <span className="text-[9px] font-bold uppercase tracking-[.14em] text-slate-500">{t('realm.bounty.rewards')}</span>
          <RewardChips b={b} />
        </div>
        {state === 'claimed' && <span className="bounty-seal">✓</span>}
      </div>

      {state === 'claimable' && (
        <button disabled={busy} onClick={onClaim} className="bounty-claim mt-3" type="button">
          {t('realm.bounty.claim')}
        </button>
      )}
    </article>
  );
}

/**
 * Bounty board AAA — apresentação apenas.
 * Todo progresso, elegibilidade e claim continuam vindo do backend (realm_bounties / realm_bounty_claim).
 */
export default function RealmBountyBoard({
  bounties, busy, now, onClaim,
}: { bounties: RealmBounty[]; busy: boolean; now: number; onClaim: (id: string) => void }) {
  const t: Translator = useT();
  const { ordered, featured, active, completed, totalFc, totalFrags } = useMemo(() => {
    const rank: Record<State, number> = { claimable: 0, progress: 1, claimed: 2 };
    const list = [...bounties].sort((a, b) => rank[stateOf(a)] - rank[stateOf(b)]);
    const feat = list.find((b) => stateOf(b) === 'claimable') ?? list.find((b) => stateOf(b) === 'progress') ?? list[0];
    return {
      ordered: list.filter((b) => b.id !== feat?.id),
      featured: feat,
      active: bounties.filter((b) => stateOf(b) !== 'claimed').length,
      completed: bounties.filter((b) => stateOf(b) === 'claimed').length,
      totalFc: bounties.reduce((s, b) => s + (b.reward.fc ?? 0), 0),
      totalFrags: bounties.reduce((s, b) => s + (b.reward.fragments ?? 0), 0),
    };
  }, [bounties]);

  return (
    <section className="bounty-board" style={{ backgroundImage: `url(${BOARD_BG})` }}>
      <div className="bounty-board__veil" />
      <div className="bounty-board__dust" aria-hidden />

      <header className="relative space-y-1 text-center">
        <span className="bounty-crest">⚜</span>
        <h2 className="text-[16px] font-black uppercase tracking-[.18em] text-amber-100 drop-shadow-[0_0_18px_rgba(251,191,36,.35)]">
          {t('realm.bounty.dailyTitle')}
        </h2>
        <p className="mx-auto max-w-[16rem] text-[9.5px] leading-snug text-slate-400">
          {t('realm.bounty.dailySub')}
        </p>
      </header>

      <div className="relative mt-4 grid grid-cols-4 gap-1.5">
        {[
          { k: t('realm.bounty.active'), v: String(active) },
          { k: t('realm.bounty.done'), v: `${completed}/${bounties.length}` },
          { k: t('realm.bounty.reset'), v: resetIn(now) },
          { k: t('realm.bounty.today'), v: `${fmt(totalFc)} BERRIES` },
        ].map((s) => (
          <div key={s.k} className="bounty-stat">
            <b className="block truncate text-[10.5px] font-black tabular-nums text-amber-100">{s.v}</b>
            <span className="text-[8px] font-bold uppercase tracking-[.1em] text-slate-500">{s.k}</span>
          </div>
        ))}
      </div>

      {bounties.length === 0 ? (
        <p className="relative py-10 text-center text-[10px] text-slate-500">{t('realm.bounty.empty')}</p>
      ) : (
        <div className="relative mt-4 space-y-3">
          {featured && (
            <BountyCard b={featured} featured busy={busy} index={0} onClaim={() => onClaim(featured.id)} />
          )}
          {ordered.map((b, i) => (
            <BountyCard key={b.id} b={b} busy={busy} index={i + 1} onClaim={() => onClaim(b.id)} />
          ))}
        </div>
      )}

      <footer className="relative mt-5 space-y-2 border-t border-amber-200/10 pt-3 text-center">
        <p className="text-[9px] leading-snug text-slate-500">
          {t('realm.bounty.footer')}
        </p>
        <p className="text-[9px] font-bold uppercase tracking-[.14em] text-amber-200/70">
          {t('realm.bounty.total', { fc: fmt(totalFc), frags: totalFrags })}
        </p>
      </footer>
    </section>
  );
}
