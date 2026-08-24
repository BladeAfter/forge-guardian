import { useT } from '../LanguageContext';
import GIVEAWAY_ART from '../assets/giveaway/giveaway-art.webp';

type Props = {
  /** Opens the Telegram group and records `clicked_join_at` server-side. */
  onJoin: () => void;
  /** Closes and records `dismissed_at` server-side. */
  onClose: () => void;
};

type Prize = { medal: string; place: string; lines: string[] };

/**
 * MYTHREON GIVEAWAY promotional popup. Purely informative: it NEVER grants any
 * reward. Winners are picked separately. The "show once per campaign" rule is
 * fully owned by the backend (user_campaign_popup + campaign_id).
 */
export function GiveawayPopup({ onJoin, onClose }: Props) {
  const t = useT();
  const fc = (v: number) => v.toLocaleString('en-US');

  const prizes: Prize[] = [
    { medal: '🥇', place: '1st', lines: ['0.700 TON', `${fc(150000)} FC`, t('giveaway.legendaryChest'), `30 ${t('giveaway.fragments')}`] },
    { medal: '🥈', place: '2nd', lines: ['0.400 TON', `${fc(100000)} FC`, t('giveaway.epicChest'), `20 ${t('giveaway.fragments')}`] },
    { medal: '🥉', place: '3rd', lines: ['0.250 TON', `${fc(75000)} FC`, t('giveaway.rareChest'), `15 ${t('giveaway.fragments')}`] },
    { medal: '4️⃣', place: t('giveaway.place4'), lines: ['0.100 TON', `${fc(50000)} FC`, `10 ${t('giveaway.fragments')}`, `2 ${t('giveaway.tickets')}`] },
    { medal: '5️⃣', place: t('giveaway.place5'), lines: ['0.050 TON', `${fc(25000)} FC`, `5 ${t('giveaway.fragments')}`, `1 ${t('giveaway.tickets')}`] },
  ];

  return (
    <div className="fixed inset-0 z-[95] flex items-center justify-center bg-black/85 px-3 py-6 backdrop-blur-sm">
      <div className="relative flex max-h-[92dvh] w-full max-w-[380px] flex-col overflow-hidden rounded-3xl border border-amber-300/45 bg-gradient-to-b from-[#0a1224] via-[#070a12] to-[#0d0803] shadow-[0_25px_70px_rgba(0,0,0,.9)]">
        <div className="pointer-events-none absolute -right-20 -top-24 h-56 w-56 rounded-full bg-amber-400/20 blur-3xl" />
        <div className="pointer-events-none absolute -left-24 bottom-0 h-56 w-56 rounded-full bg-sky-500/15 blur-3xl" />

        <button
          type="button"
          aria-label={t('giveaway.close')}
          onClick={onClose}
          className="absolute right-3 top-3 z-10 flex h-9 w-9 items-center justify-center rounded-full border border-amber-300/45 bg-black/60 text-lg font-bold text-amber-100 transition active:scale-95"
        >
          ✕
        </button>

        <div className="relative flex-1 overflow-y-auto px-4 pb-4 pt-4">
          <p className="text-center text-[10px] font-black tracking-[0.42em] text-amber-200/80">MYTHREON</p>
          <h2 className="mt-1 text-center text-[22px] font-black leading-tight text-transparent [background:linear-gradient(180deg,#fff5cf,#f0b32a)] [-webkit-background-clip:text] [background-clip:text] drop-shadow-[0_2px_10px_rgba(240,179,42,.45)]">
            🎁 {t('giveaway.title')}
          </h2>
          <p className="mt-1 text-center text-[12px] font-bold tracking-[0.2em] text-sky-200">{t('giveaway.subtitle')}</p>

          <div className="mt-2 flex items-center justify-center">
            <img src={GIVEAWAY_ART} alt="" width={1024} height={768} loading="lazy" className="h-28 w-auto drop-shadow-[0_10px_25px_rgba(0,0,0,.7)]" />
          </div>

          <p className="mt-1 text-center text-[11px] leading-snug text-white/75">{t('giveaway.body')}</p>

          <div className="mt-3 space-y-1.5">
            {prizes.map((prize) => (
              <div key={prize.place} className="flex items-center gap-2 rounded-xl border border-amber-300/25 bg-black/45 px-2.5 py-1.5">
                <span className="w-9 shrink-0 text-center text-base">{prize.medal}</span>
                <div className="min-w-0 flex-1">
                  <p className="text-[10px] font-black tracking-widest text-amber-200/85">{prize.place}</p>
                  <p className="truncate text-[10.5px] font-semibold text-white/85">{prize.lines.join(' · ')}</p>
                </div>
              </div>
            ))}
          </div>

          <p className="mt-3 text-center text-[10px] italic text-white/50">{t('giveaway.footer')}</p>
        </div>

        <div className="relative border-t border-amber-300/25 bg-black/50 px-4 py-3">
          <button
            type="button"
            onClick={onJoin}
            className="w-full rounded-2xl border border-amber-200/70 bg-gradient-to-r from-amber-500 via-amber-400 to-orange-500 py-3 text-[15px] font-black tracking-wider text-[#2a1603] shadow-[0_0_25px_rgba(245,180,50,.5)] transition active:scale-[.98]"
          >
            ✈ {t('giveaway.button')}
          </button>
        </div>
      </div>
    </div>
  );
}
