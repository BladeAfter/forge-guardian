import { useLocalizedText } from '../LanguageContext';
import { Ban, ShieldX } from 'lucide-react';
import bannedArt from '../assets/account-banned.jpg';

/**
 * Fullscreen BAN gate. Rendered only when the BACKEND answered
 * `{ access: 'banned' }` (game_players.banned = true). No game screen,
 * query or asset behind it is ever loaded.
 */

type Copy = { badge: string; title: string; message: string; reason: string; sub: string; code: string; appeal: string };

const COPY: Record<string, Copy> = {
  en: {
    badge: 'FAIR PLAY ENFORCEMENT',
    title: 'ACCOUNT BANNED',
    message: 'This account was permanently suspended by the Mythic Seas team.',
    reason: 'Reason',
    sub: 'NFT heroes, pets and items linked to this account were revoked and returned to the shop.',
    code: 'Ban Code',
    appeal: 'Appeals: contact the official Mythic Seas support channel.',
  },
  pt: {
    badge: 'APLICAÇÃO DE JOGO JUSTO',
    title: 'CONTA BANIDA',
    message: 'Esta conta foi suspensa permanentemente pela equipe do Mythic Seas.',
    reason: 'Motivo',
    sub: 'Heróis NFT, pets e itens ligados a esta conta foram revogados e devolvidos à loja.',
    code: 'Código do Banimento',
    appeal: 'Recursos: fale com o canal oficial de suporte do Mythic Seas.',
  },
  es: {
    badge: 'APLICACIÓN DE JUEGO LIMPIO',
    title: 'CUENTA BANEADA',
    message: 'Esta cuenta fue suspendida permanentemente por el equipo de Mythic Seas.',
    reason: 'Motivo',
    sub: 'Los héroes NFT, mascotas e ítems de esta cuenta fueron revocados y devueltos a la tienda.',
    code: 'Código de baneo',
    appeal: 'Apelaciones: contacta el canal oficial de soporte de Mythic Seas.',
  },
  ru: {
    badge: 'ЗАЩИТА ЧЕСТНОЙ ИГРЫ',
    title: 'АККАУНТ ЗАБЛОКИРОВАН',
    message: 'Этот аккаунт навсегда заблокирован командой Mythic Seas.',
    reason: 'Причина',
    sub: 'NFT-герои, питомцы и предметы аккаунта отозваны и возвращены в магазин.',
    code: 'Код блокировки',
    appeal: 'Апелляции: напишите в официальную поддержку Mythic Seas.',
  },
  tr: {
    badge: 'ADİL OYUN UYGULAMASI',
    title: 'HESAP YASAKLANDI',
    message: 'Bu hesap Mythic Seas ekibi tarafından kalıcı olarak askıya alındı.',
    reason: 'Sebep',
    sub: 'Bu hesaba bağlı NFT kahramanlar, evcil hayvanlar ve eşyalar geri alındı ve mağazaya döndü.',
    code: 'Yasak Kodu',
    appeal: 'İtirazlar: resmi Mythic Seas destek kanalıyla iletişime geçin.',
  },
};

export default function BannedScreen({
  language = 'en',
  reason,
  bannedAt,
}: {
  language?: string;
  reason?: string | null;
  bannedAt?: string | null;
}) {
  const localizeText = useLocalizedText();

  const copy = COPY[language] ?? COPY.en;
  const date = bannedAt ? new Date(bannedAt) : null;

  return (
    <div className="relative flex min-h-screen items-center justify-center overflow-hidden bg-[#07030a] px-6 py-10 text-white">
      <img
        src={bannedArt}
        alt=""
        width={832}
        height={1216}
        className="absolute inset-0 h-full w-full object-cover opacity-70"
      />
      <div className="absolute inset-0 bg-gradient-to-b from-[#07030a]/70 via-[#07030a]/88 to-[#07030a]/98" />
      <div className="pointer-events-none absolute inset-x-0 top-1/3 h-64 bg-red-600/20 blur-3xl" />

      <main className="relative w-full max-w-sm text-center">
        <span className="inline-flex items-center gap-2 rounded-full border border-red-400/40 bg-black/60 px-4 py-1.5 text-[10px] font-black uppercase tracking-[.2em] text-red-200">
          <ShieldX className="h-3.5 w-3.5" /> {copy.badge}
        </span>

        <div className="mt-6 rounded-3xl border-2 border-red-500/45 bg-black/60 p-6 shadow-[0_20px_60px_rgba(0,0,0,.75)] backdrop-blur-sm">
          <div className="mx-auto flex h-16 w-16 items-center justify-center rounded-full border-2 border-red-400/60 bg-red-600/20 shadow-[0_0_36px_rgba(220,38,38,.55)]">
            <Ban className="h-8 w-8 text-red-300" />
          </div>

          <h1 className="mt-5 text-3xl font-black uppercase leading-8 tracking-[.12em] text-red-300 drop-shadow-[0_6px_18px_rgba(220,38,38,.55)]">
            {copy.title}
          </h1>

          <p className="mt-4 text-sm font-semibold leading-6 text-slate-100">{copy.message}</p>

          {reason ? (
            <div className="mt-5 rounded-2xl border border-red-400/25 bg-red-950/40 p-3">
              <p className="text-[10px] font-black uppercase tracking-[.2em] text-red-300/80">{copy.reason}</p>
              <p className="mt-1 text-sm font-bold text-red-100">{reason}</p>
            </div>
          ) : null}

          <div className="mt-4 rounded-2xl border border-white/10 bg-black/50 p-3">
            <p className="text-[10px] font-black uppercase tracking-[.2em] text-slate-400">{copy.code}</p>
            <p className="mt-1 font-mono text-sm font-black tracking-[.12em] text-amber-200">{localizeText("ACCOUNT_BANNED")}</p>
            {date ? (
              <p className="mt-1 font-mono text-[11px] text-slate-400">{date.toISOString().slice(0, 16).replace('T', ' ')} {localizeText("UTC")}</p>
            ) : null}
          </div>

          <p className="mt-4 text-[11px] leading-5 text-slate-400">{copy.sub}</p>
        </div>

        <p className="mt-5 text-[11px] leading-5 text-slate-500">{copy.appeal}</p>
      </main>
    </div>
  );
}
