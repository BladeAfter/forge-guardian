import { Coins, Megaphone, TrendingDown, Wallet } from 'lucide-react';
import { useMarketingPool } from '../hooks';
import { useT, useLanguage } from '../LanguageContext';
import { formatTon } from '../economy';

const ton = (value: number) => `${formatTon(Number(value) || 0)} TON`;

const CATEGORY_TONE: Record<string, string> = {
  MARKETING: 'border-amber-300/40 text-amber-200',
  DEVELOPMENT: 'border-cyan-300/40 text-cyan-200',
  INFLUENCERS: 'border-fuchsia-300/40 text-fuchsia-200',
  DESIGN: 'border-violet-300/40 text-violet-200',
  COMMUNITY: 'border-emerald-300/40 text-emerald-200',
  MODERATION: 'border-sky-300/40 text-sky-200',
  SERVER: 'border-slate-300/40 text-slate-200',
  OTHER: 'border-white/20 text-slate-300',
};

/**
 * POOL MARKETING tab: 100% read-only for players. Total, spent, remaining, entries
 * and the expense history all come from the backend, edited live by the admin bot.
 */
export function MarketingPoolPanel({ telegramInitData }: { telegramInitData: string }) {
  const t = useT();
  const { language } = useLanguage();
  const { data, isLoading, error, refetch } = useMarketingPool(telegramInitData, true);

  const date = (value: string | null) => {
    if (!value) return '--';
    const d = new Date(value);
    return Number.isNaN(d.getTime()) ? '--' : d.toLocaleString(language === 'en' ? 'en-GB' : language, { dateStyle: 'short', timeStyle: 'short' });
  };
  const day = (value: string) => {
    const d = new Date(`${value}T00:00:00`);
    return Number.isNaN(d.getTime()) ? value : d.toLocaleDateString(language === 'en' ? 'en-GB' : language);
  };

  if (isLoading) {
    return <div className="space-y-3 pt-4">{[1, 2, 3].map((x) => <div key={x} className="h-28 animate-pulse rounded-3xl bg-white/5" />)}</div>;
  }
  if (error || !data) {
    return (
      <div className="py-20 text-center">
        <p className="text-rose-300">{t('mkpool.loadError')}</p>
        <button onClick={() => void refetch()} className="mt-4 rounded-xl border border-amber-300/30 px-5 py-3 text-xs font-black">{t('mkpool.retry')}</button>
      </div>
    );
  }

  const pct = data.totalTon > 0 ? Math.min(100, (data.spentTon / data.totalTon) * 100) : 0;

  return (
    <div className="pb-10">
      <section className="relative overflow-hidden rounded-[2rem] border border-amber-300/40 bg-gradient-to-br from-amber-950/60 via-[#0c1425] to-black p-5 shadow-[0_0_45px_rgba(245,158,11,.15)]">
        <div className="flex items-center gap-2">
          <Megaphone className="h-5 w-5 text-amber-300" />
          <h2 className="text-sm font-black tracking-[.2em] text-amber-200">{t('mkpool.title')}</h2>
        </div>
        <p className="mt-4 text-[9px] font-bold uppercase tracking-[.35em] text-amber-300/80">{t('mkpool.total')}</p>
        <h3 className="text-4xl font-black text-amber-100">{ton(data.totalTon)}</h3>
        <div className="mt-4 h-2.5 overflow-hidden rounded-full bg-white/10">
          <div className="h-full bg-gradient-to-r from-amber-600 to-yellow-200" style={{ width: `${pct}%` }} />
        </div>
        <div className="mt-4 grid grid-cols-2 gap-2">
          <Stat icon={<TrendingDown className="h-4 w-4" />} label={t('mkpool.spent')} value={ton(data.spentTon)} tone="text-rose-300" />
          <Stat icon={<Wallet className="h-4 w-4" />} label={t('mkpool.remaining')} value={ton(data.remainingTon)} tone="text-emerald-300" />
          <Stat icon={<Coins className="h-4 w-4" />} label={t('mkpool.entries')} value={String(data.entries)} />
          <Stat icon={<Coins className="h-4 w-4" />} label={t('mkpool.status')} value={data.enabled ? t('mkpool.statusActive') : t('mkpool.statusPaused')} tone={data.enabled ? 'text-emerald-300' : 'text-slate-400'} />
        </div>
        <p className="mt-3 text-center text-[9px] uppercase tracking-[.2em] text-slate-400">{t('mkpool.lastUpdate')}: {date(data.updatedAt)}</p>
      </section>

      <p className="mt-3 rounded-2xl border border-white/10 bg-black/45 p-3 text-[10px] leading-5 text-slate-400">{t('mkpool.info')}</p>

      <h3 className="mb-2 mt-5 text-xs font-black tracking-[.2em] text-amber-200">{t('mkpool.history')}</h3>
      {data.expenses.length === 0
        ? <p className="rounded-2xl border border-white/10 bg-black/50 p-4 text-center text-[11px] text-slate-400">{t('mkpool.empty')}</p>
        : (
          <div className="space-y-2">
            {data.expenses.map((e) => (
              <div key={e.id} className="rounded-2xl border border-white/10 bg-black/55 p-3">
                <div className="flex items-start justify-between gap-2">
                  <div className="min-w-0">
                    <span className={`inline-block rounded-lg border px-2 py-0.5 text-[8px] font-black uppercase tracking-[.15em] ${CATEGORY_TONE[e.category] ?? CATEGORY_TONE.OTHER}`}>
                      {t(`mkpool.cat.${e.category}`) || e.category}
                    </span>
                    <p className="mt-1 truncate text-xs font-bold text-white">{e.description}</p>
                    {e.note && <p className="mt-0.5 truncate text-[9px] text-slate-500">{e.note}</p>}
                  </div>
                  <div className="shrink-0 text-right">
                    <b className="text-xs text-rose-300">-{ton(e.amountTon)}</b>
                    <p className="mt-0.5 text-[9px] text-slate-400">{day(e.spentAt)}</p>
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}
    </div>
  );
}

function Stat({ label, value, icon, tone }: { label: string; value: string; icon: React.ReactNode; tone?: string }) {
  return (
    <div className="rounded-2xl border border-white/10 bg-black/55 p-3">
      <span className={`float-right ${tone ?? 'text-amber-300'}`}>{icon}</span>
      <p className="text-[9px] uppercase tracking-[.15em] text-slate-400">{label}</p>
      <b className={tone ?? 'text-white'}>{value}</b>
    </div>
  );
}
