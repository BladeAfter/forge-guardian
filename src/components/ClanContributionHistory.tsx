import { useCallback, useEffect, useState } from 'react';
import { Coins, Gem, Loader2, Shield, X } from 'lucide-react';
import { toast } from 'sonner';
import { clanRequest } from '../clans';
import { clanErrorMessage } from '../lib/clanErrors';

/**
 * TREASURY → CONTRIBUTION HISTORY.
 * Everything here is read-only: BERRIES donated, MYTH donated and clan contribution points
 * are three separate numbers, aggregated server-side from the real treasury ledger.
 * No conversion between BERRIES and MYTH is ever performed.
 */

type Period = 'today' | 'week' | 'total';
type Totals = { fc: number; myth: number; points: number };
type MemberRow = {
  userId: string; username: string; role: string;
  fc: number; myth: number; points: number;
  donationCount: number; lastDonationAt: string | null;
};
type Summary = {
  inClan: boolean; period: Period; gameDay: string; nextResetAt: string;
  members: MemberRow[]; me: { today: Totals; week: Totals; total: Totals };
};
type Detail = {
  userId: string; username: string;
  totals: { today: Totals; week: Totals; total: Totals };
  donationCount: number; lastDonationAt: string | null;
};
type Entry = { id: string; asset: string; amount: number; reason: string; createdAt: string; reversed: boolean };

type SortKey = 'points' | 'fc' | 'myth';

const PERIOD_LABEL: Record<Period, string> = { today: 'Hoje', week: 'Semana', total: 'Total' };

/** 1.200 → 1.2K · 1.200.000 → 1.2M (full value stays visible in the detail modal). */
const short = (v: number) => {
  const n = Math.abs(v);
  if (n >= 1_000_000_000) return `${(v / 1_000_000_000).toFixed(v % 1_000_000_000 === 0 ? 0 : 1)}B`;
  if (n >= 1_000_000) return `${(v / 1_000_000).toFixed(v % 1_000_000 === 0 ? 0 : 1)}M`;
  if (n >= 1_000) return `${(v / 1_000).toFixed(v % 1_000 === 0 ? 0 : 1)}K`;
  return v.toLocaleString('pt-BR');
};
const full = (v: number) => Math.round(v).toLocaleString('pt-BR');
const stamp = (iso: string) =>
  new Date(iso).toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' });

/** Only assets actually contributed are rendered — never "0 BERRIES" or "0 MYTH". */
function AssetLine({ fc, myth, dense = false }: { fc: number; myth: number; dense?: boolean }) {
  const parts: React.ReactNode[] = [];
  if (fc > 0) parts.push(<span key="fc" className="inline-flex items-center gap-0.5 text-amber-200"><Coins className="h-3 w-3" />{short(fc)} BERRIES</span>);
  if (!parts.length) return <span className={`${dense ? 'text-[9px]' : 'text-[10px]'} text-slate-600`}>sem doações</span>;
  return (
    <span className={`inline-flex flex-wrap items-center gap-x-1.5 ${dense ? 'text-[9px]' : 'text-[10px]'} font-bold`}>
      {parts.map((p, i) => (
        <span key={i} className="inline-flex items-center gap-1.5">{i > 0 ? <span className="text-slate-600">•</span> : null}{p}</span>
      ))}
    </span>
  );
}

function MyCard({ label, totals, highlight }: { label: string; totals: Totals; highlight?: boolean }) {
  return (
    <div className={`rounded-xl border bg-black/45 px-2 py-1.5 ${highlight ? 'border-amber-400/40' : 'border-white/10'}`}>
      <div className="text-[8px] uppercase tracking-widest text-slate-500">{label}</div>
      <div className="mt-0.5 space-y-0.5 leading-tight">
        {totals.fc > 0 ? <div className="text-[11px] font-black text-amber-200">{short(totals.fc)} BERRIES</div> : null}
        {totals.fc <= 0 ? <div className="text-[11px] font-black text-slate-600">—</div> : null}
        {totals.points > 0 ? <div className="text-[8px] font-bold text-slate-500">{full(totals.points)} pts</div> : null}
      </div>
    </div>
  );
}

export function ClanContributionHistory({ telegramInitData, refreshKey = 0 }: { telegramInitData: string; refreshKey?: number }) {
  const [period, setPeriod] = useState<Period>('today');
  const [sort, setSort] = useState<SortKey>('points');
  const [data, setData] = useState<Summary | null>(null);
  const [loading, setLoading] = useState(true);
  const [detail, setDetail] = useState<Detail | null>(null);
  const [entries, setEntries] = useState<Entry[] | null>(null);
  const [detailBusy, setDetailBusy] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const res = await clanRequest<Summary>(telegramInitData, { action: 'contribution-summary', period });
      if (res?.inClan) setData(res);
    } catch (error) {
      toast.error(clanErrorMessage(error));
    } finally {
      setLoading(false);
    }
  }, [telegramInitData, period]);

  // Reloads on period change and whenever a donation happens (realtime refresh, no restart).
  useEffect(() => { void load(); }, [load, refreshKey]);

  const openDetail = async (userId: string) => {
    setDetailBusy(true);
    setEntries(null);
    try {
      const res = await clanRequest<Detail & { inClan: boolean }>(telegramInitData, { action: 'contribution-detail', userId });
      setDetail(res);
    } catch (error) {
      toast.error(clanErrorMessage(error));
    } finally {
      setDetailBusy(false);
    }
  };

  const loadEntries = async (userId: string) => {
    setDetailBusy(true);
    try {
      const res = await clanRequest<{ entries: Entry[] }>(telegramInitData, { action: 'contribution-history', userId, limit: 50 });
      setEntries((res.entries ?? []).filter(entry => entry.asset.toUpperCase() !== 'MYTH'));
    } catch (error) {
      toast.error(clanErrorMessage(error));
    } finally {
      setDetailBusy(false);
    }
  };

  const members = [...(data?.members ?? [])]
    .sort((a, b) => (sort === 'fc' ? b.fc - a.fc : sort === 'myth' ? b.myth - a.myth : b.points - a.points))
    .filter((m) => m.fc > 0 || m.myth > 0 || m.points > 0);

  return (
    <div className="space-y-2">
      {/* MY OWN SUMMARY — real BERRIES / MYTH values, points as a secondary line */}
      <div className="grid grid-cols-3 gap-1.5">
        <MyCard label="Hoje" totals={data?.me?.today ?? { fc: 0, myth: 0, points: 0 }} />
        <MyCard label="Semana" totals={data?.me?.week ?? { fc: 0, myth: 0, points: 0 }} highlight />
        <MyCard label="Total" totals={data?.me?.total ?? { fc: 0, myth: 0, points: 0 }} />
      </div>

      {/* PERIOD FILTER — drives the ledger aggregation window server-side */}
      <div className="grid grid-cols-3 gap-1.5">
        {(['today', 'week', 'total'] as Period[]).map((p) => (
          <button key={p} onClick={() => setPeriod(p)}
            className={`rounded-lg border py-1 text-[9px] font-black uppercase tracking-widest transition ${
              period === p ? 'border-amber-300/60 bg-amber-400/15 text-amber-200' : 'border-white/10 bg-black/45 text-slate-400'}`}>
            {PERIOD_LABEL[p]}
          </button>
        ))}
      </div>

      {/* SORT — assets are never summed together */}
      <div className="flex items-center gap-1.5">
        <span className="text-[8px] uppercase tracking-widest text-slate-500">Ordenar</span>
        {([['points', 'PTS'], ['fc', 'BERRIES']] as [SortKey, string][]).map(([k, label]) => (
          <button key={k} onClick={() => setSort(k)}
            className={`rounded-full border px-2 py-0.5 text-[9px] font-black transition ${
              sort === k ? 'border-amber-300/60 bg-amber-400/15 text-amber-200' : 'border-white/10 bg-black/45 text-slate-400'}`}>
            {label}
          </button>
        ))}
      </div>

      {loading ? (
        <div className="flex justify-center py-4"><Loader2 className="h-4 w-4 animate-spin text-amber-400" /></div>
      ) : members.length ? (
        <div className="space-y-1">
          {members.map((m, i) => (
            <button key={m.userId} onClick={() => void openDetail(m.userId)}
              className="flex w-full items-center gap-2 rounded-xl bg-black/40 px-2 py-1.5 text-left transition active:scale-[.99]">
              <span className="w-4 shrink-0 text-[10px] font-black text-slate-500">{i + 1}</span>
              <span className="min-w-0 flex-1">
                <span className="block truncate text-[11px] font-black text-slate-100">{m.username}</span>
                <AssetLine fc={m.fc} myth={m.myth} />
              </span>
              <span className="shrink-0 text-right">
                <span className="block text-[10px] font-black text-amber-300">{full(m.points)} pts</span>
                {m.donationCount > 0 ? <span className="block text-[8px] text-slate-500">{m.donationCount} doações</span> : null}
              </span>
            </button>
          ))}
        </div>
      ) : (
        <p className="py-2 text-center text-[10px] text-slate-500">Nenhuma contribuição registrada neste período.</p>
      )}

      {/* DETAIL MODAL — full values, three periods, real ledger history */}
      {detail ? (
        <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/80 p-3 pb-8 backdrop-blur-sm">
          <div className="w-full max-w-sm rounded-2xl border border-amber-400/30 bg-gradient-to-b from-[#111d33] to-black p-3 shadow-2xl">
            <div className="mb-2 flex items-center justify-between">
              <span className="flex items-center gap-1.5 text-[10px] font-black uppercase tracking-widest text-amber-300">
                <Shield className="h-3.5 w-3.5" />Detalhes da contribuição
              </span>
              <button onClick={() => { setDetail(null); setEntries(null); }} className="rounded-lg bg-white/10 p-1 text-slate-300"><X className="h-3.5 w-3.5" /></button>
            </div>
            <p className="mb-2 truncate text-sm font-black text-slate-100">@{detail.username}</p>

            <div className="space-y-1.5">
              {([['Hoje', detail.totals.today], ['Esta semana', detail.totals.week], ['Histórico total', detail.totals.total]] as [string, Totals][]).map(([label, t]) => (
                <div key={label} className="rounded-xl bg-black/45 px-2 py-1.5">
                  <div className="text-[8px] uppercase tracking-widest text-slate-500">{label}</div>
                  <div className="mt-0.5 flex flex-wrap gap-x-3 text-[11px] font-bold">
                    {t.fc > 0 ? <span className="text-amber-200">BERRIES: {full(t.fc)}</span> : null}
                    {t.fc <= 0 ? <span className="text-slate-600">sem doações</span> : null}
                    {t.points > 0 ? <span className="text-slate-400">{full(t.points)} pts</span> : null}
                  </div>
                </div>
              ))}
            </div>

            {entries === null ? (
              <button disabled={detailBusy} onClick={() => void loadEntries(detail.userId)}
                className="mt-2 w-full rounded-xl bg-gradient-to-r from-amber-500 to-amber-700 py-2 text-[10px] font-black uppercase tracking-widest text-black disabled:opacity-40">
                {detailBusy ? 'Carregando…' : 'Ver histórico'}
              </button>
            ) : (
              <div className="mt-2 max-h-52 space-y-1 overflow-y-auto">
                {entries.length ? entries.map((e) => (
                  <div key={e.id} className="flex items-center justify-between gap-2 rounded-lg bg-black/40 px-2 py-1">
                    <span className="text-[9px] text-slate-500">{stamp(e.createdAt)}</span>
                    <span className={`text-[10px] font-black ${e.reversed ? 'text-rose-300 line-through' : e.asset === 'MYTH' ? 'text-violet-200' : 'text-amber-200'}`}>
                      {e.amount > 0 ? '+' : ''}{full(e.amount)} {e.asset === 'FC' ? 'BERRIES' : e.asset}
                    </span>
                  </div>
                )) : <p className="py-2 text-center text-[10px] text-slate-500">Sem doações registradas.</p>}
              </div>
            )}
          </div>
        </div>
      ) : null}
    </div>
  );
}
