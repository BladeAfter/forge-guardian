import { useEffect, useState } from 'react';
import { forgeBackendUrl, forgeFetch, forgeHealth, type ForgeHealth } from '../apiClient';

const FEATURES = ['profile', 'pets', 'pvp', 'referral', 'season-pass', 'pool', 'boss', 'wallet', 'calendar'] as const;

type Probe = { feature: string; status: number; ok: boolean; error?: string | null };

const Badge = ({ ok, label }: { ok: boolean; label: string }) => (
  <span
    className={`rounded-full px-2 py-0.5 text-[11px] font-bold uppercase tracking-wide ${
      ok ? 'bg-emerald-500/20 text-emerald-300' : 'bg-red-500/20 text-red-300'
    }`}
  >
    {label}
  </span>
);

export function DiagnosticsPage({
  telegramInitData,
  telegramId,
  onClose,
}: {
  telegramInitData: string;
  telegramId: number | null;
  onClose: () => void;
}) {
  const [health, setHealth] = useState<ForgeHealth | null>(null);
  const [probes, setProbes] = useState<Probe[]>([]);
  const [running, setRunning] = useState(false);

  const run = async () => {
    setRunning(true);
    setHealth(await forgeHealth());
    const results: Probe[] = [];
    for (const feature of FEATURES) {
      try {
        const response = await forgeFetch(feature, { initData: telegramInitData });
        const payload = (await response.json()) as { error?: string } | null;
        results.push({ feature, status: response.status, ok: response.ok, error: payload?.error ?? null });
      } catch (error) {
        results.push({ feature, status: 0, ok: false, error: error instanceof Error ? error.message : 'falha de rede' });
      }
      setProbes([...results]);
    }
    setRunning(false);
  };

  useEffect(() => {
    void run();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <div className="forge-safe-page min-h-screen bg-forge-black px-4 pb-16 text-white">
      <header className="mb-4 flex items-center justify-between">
        <h1 className="text-lg font-black uppercase tracking-wide text-amber-300">Diagnóstico</h1>
        <button onClick={onClose} className="rounded-lg border border-white/15 px-3 py-1 text-xs uppercase">
          Fechar
        </button>
      </header>

      <section className="mb-4 space-y-2 rounded-xl border border-white/10 bg-white/5 p-3 text-sm">
        <div className="flex items-center justify-between">
          <span>Frontend</span>
          <Badge ok label="online" />
        </div>
        <div className="flex items-center justify-between">
          <span>Backend</span>
          <Badge ok={health?.backend === 'online'} label={health?.backend ?? '...'} />
        </div>
        <div className="flex items-center justify-between">
          <span>Banco de dados</span>
          <Badge ok={health?.database === 'online'} label={health?.database ?? '...'} />
        </div>
        <div className="flex items-center justify-between">
          <span>Telegram initData</span>
          <Badge ok={Boolean(telegramInitData)} label={telegramInitData ? 'ok' : 'falha'} />
        </div>
        <div className="flex items-center justify-between">
          <span>Telegram ID</span>
          <span className="font-mono text-xs text-white/70">{telegramId ?? '—'}</span>
        </div>
        <div className="flex items-center justify-between gap-2">
          <span>API URL</span>
          <span className="truncate font-mono text-[10px] text-white/60">{forgeBackendUrl || 'não configurada'}</span>
        </div>
        <div className="flex items-center justify-between">
          <span>Environment</span>
          <span className="font-mono text-xs text-white/70">{import.meta.env.PROD ? 'production' : 'development'}</span>
        </div>
      </section>

      <section className="space-y-1">
        {FEATURES.map((feature) => {
          const probe = probes.find((item) => item.feature === feature);
          return (
            <div
              key={feature}
              className="flex items-center justify-between rounded-lg border border-white/10 bg-white/5 px-3 py-2 text-sm"
            >
              <span className="uppercase tracking-wide">{feature} API</span>
              <div className="flex items-center gap-2">
                {probe?.error ? <span className="max-w-[45vw] truncate text-[10px] text-red-300">{probe.error}</span> : null}
                <Badge ok={Boolean(probe?.ok)} label={probe ? `HTTP ${probe.status}` : '...'} />
              </div>
            </div>
          );
        })}
      </section>

      <button
        onClick={() => void run()}
        disabled={running}
        className="mt-5 w-full rounded-xl bg-amber-500 py-3 text-sm font-black uppercase text-black disabled:opacity-50"
      >
        {running ? 'Testando...' : 'Testar novamente'}
      </button>
    </div>
  );
}
