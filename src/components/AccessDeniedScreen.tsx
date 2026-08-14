import { useState } from 'react';
import { ShieldAlert, LifeBuoy, Loader2, CheckCircle2 } from 'lucide-react';
import accessDeniedArt from '../assets/access-denied.jpg';
import { requestDeviceReview, type DeviceIdentity } from '../antiFake';

/**
 * ANTI-FAKE fullscreen gate. Rendered only when the BACKEND answered
 * `{ access: 'blocked' }`. No game screen, query or asset behind it is loaded.
 * Nothing technical (device hash, IP, other Telegram IDs) is ever shown.
 */

type Copy = {
  title: string;
  message: string;
  sub: string;
  code: string;
  fair: string;
  cta: string;
  sent: string;
  pending: string;
  failed: string;
  keep: string;
};

const COPY: Record<string, Copy> = {
  en: {
    title: 'ACCESS DENIED',
    message: 'Multiple accounts detected on this device.',
    sub: 'For security and fair play, Mythreon allows up to 3 accounts per device.',
    code: 'Security Code',
    fair: 'FAIR PLAY PROTECTION',
    cta: 'REQUEST REVIEW',
    sent: 'Review requested. Our team will analyse this device.',
    pending: 'Review already pending.',
    failed: 'Could not send the request. Try again later.',
    keep: 'Your account, heroes, pets and balances remain untouched.',
  },
  pt: {
    title: 'ACESSO NEGADO',
    message: 'Detectamos várias contas associadas a este dispositivo.',
    sub: 'Por segurança e jogo justo, o Mythreon permite no máximo 3 contas por dispositivo.',
    code: 'Código de Segurança',
    fair: 'PROTEÇÃO DE JOGO JUSTO',
    cta: 'SOLICITAR REVISÃO',
    sent: 'Revisão solicitada. Nossa equipe vai analisar este dispositivo.',
    pending: 'Já existe uma revisão em análise.',
    failed: 'Não foi possível enviar o pedido. Tente mais tarde.',
    keep: 'Sua conta, heróis, pets e saldos permanecem intactos.',
  },
  es: {
    title: 'ACCESO DENEGADO',
    message: 'Detectamos varias cuentas asociadas a este dispositivo.',
    sub: 'Por seguridad y juego limpio, Mythreon permite hasta 3 cuentas por dispositivo.',
    code: 'Código de seguridad',
    fair: 'PROTECCIÓN DE JUEGO LIMPIO',
    cta: 'SOLICITAR REVISIÓN',
    sent: 'Revisión solicitada. Nuestro equipo analizará este dispositivo.',
    pending: 'Ya hay una revisión pendiente.',
    failed: 'No se pudo enviar la solicitud. Inténtalo más tarde.',
    keep: 'Tu cuenta, héroes, mascotas y saldos permanecen intactos.',
  },
  ru: {
    title: 'ДОСТУП ЗАПРЕЩЁН',
    message: 'На этом устройстве обнаружено несколько аккаунтов.',
    sub: 'Для безопасности и честной игры Mythreon разрешает до 3 аккаунтов на устройство.',
    code: 'Код безопасности',
    fair: 'ЗАЩИТА ЧЕСТНОЙ ИГРЫ',
    cta: 'ЗАПРОСИТЬ ПРОВЕРКУ',
    sent: 'Запрос отправлен. Наша команда проверит это устройство.',
    pending: 'Проверка уже выполняется.',
    failed: 'Не удалось отправить запрос. Попробуйте позже.',
    keep: 'Аккаунт, герои, питомцы и балансы остаются нетронутыми.',
  },
  tr: {
    title: 'ERİŞİM REDDEDİLDİ',
    message: 'Bu cihazda birden fazla hesap tespit edildi.',
    sub: 'Güvenlik ve adil oyun için Mythreon cihaz başına en fazla 3 hesaba izin verir.',
    code: 'Güvenlik Kodu',
    fair: 'ADİL OYUN KORUMASI',
    cta: 'İNCELEME TALEP ET',
    sent: 'İnceleme talep edildi. Ekibimiz bu cihazı inceleyecek.',
    pending: 'Zaten bekleyen bir inceleme var.',
    failed: 'Talep gönderilemedi. Daha sonra tekrar deneyin.',
    keep: 'Hesabınız, kahramanlarınız, evcil hayvanlarınız ve bakiyeniz korunur.',
  },
};

export default function AccessDeniedScreen({
  language = 'en',
  initData,
  identity,
  pendingReview = false,
}: {
  language?: string;
  initData: string;
  identity: DeviceIdentity | null;
  pendingReview?: boolean;
}) {
  const copy = COPY[language] ?? COPY.en;
  const [state, setState] = useState<'idle' | 'sending' | 'sent' | 'error'>(pendingReview ? 'sent' : 'idle');

  const submit = async () => {
    if (state === 'sending' || state === 'sent') return;
    setState('sending');
    try {
      await requestDeviceReview(initData, identity, 'player review request');
      setState('sent');
    } catch {
      setState('error');
    }
  };

  return (
    <div className="relative flex min-h-screen items-center justify-center overflow-hidden bg-[#04060c] px-6 py-10 text-white">
      <img
        src={accessDeniedArt}
        alt=""
        width={832}
        height={1216}
        className="absolute inset-0 h-full w-full object-cover opacity-80"
      />
      <div className="absolute inset-0 bg-gradient-to-b from-[#04060c]/70 via-[#04060c]/85 to-[#04060c]/97" />
      <div className="pointer-events-none absolute inset-x-0 top-1/3 h-56 bg-red-600/10 blur-3xl" />

      <main className="relative w-full max-w-sm text-center">
        <span className="inline-flex items-center gap-2 rounded-full border border-amber-300/40 bg-black/50 px-4 py-1.5 text-[10px] font-black uppercase tracking-[.2em] text-amber-200">
          <ShieldAlert className="h-3.5 w-3.5" /> {copy.fair}
        </span>

        <h1 className="mt-6 text-3xl font-black uppercase tracking-[.14em] text-red-300 drop-shadow-[0_6px_18px_rgba(220,38,38,.5)]">
          🛡️ {copy.title}
        </h1>

        <p className="mt-4 text-sm font-semibold leading-6 text-slate-100">{copy.message}</p>
        <p className="mt-2 text-xs leading-5 text-slate-400">{copy.sub}</p>

        <div className="mt-6 rounded-2xl border border-amber-300/20 bg-black/55 p-4 backdrop-blur-sm">
          <p className="text-[10px] font-black uppercase tracking-[.2em] text-slate-400">{copy.code}</p>
          <p className="mt-1 font-mono text-sm font-black tracking-[.12em] text-amber-200">MULTI_ACCOUNT_LIMIT</p>
        </div>

        <p className="mt-4 text-[11px] leading-5 text-slate-500">{copy.keep}</p>

        {state === 'sent' ? (
          <p className="mt-6 inline-flex items-center gap-2 rounded-2xl border border-emerald-400/40 bg-emerald-500/10 px-4 py-3 text-xs font-bold text-emerald-200">
            <CheckCircle2 className="h-4 w-4" /> {pendingReview && state === 'sent' ? copy.pending : copy.sent}
          </p>
        ) : (
          <button
            type="button"
            onClick={submit}
            disabled={state === 'sending'}
            className="mt-6 inline-flex w-full items-center justify-center gap-2 rounded-2xl border border-amber-300/50 bg-gradient-to-b from-amber-400 to-amber-600 px-6 py-4 text-sm font-black uppercase tracking-[.14em] text-[#120a02] shadow-[0_14px_30px_rgba(0,0,0,.6)] transition active:scale-95 disabled:opacity-60"
          >
            {state === 'sending' ? <Loader2 className="h-4 w-4 animate-spin" /> : <LifeBuoy className="h-4 w-4" />}
            {copy.cta}
          </button>
        )}
        {state === 'error' ? <p className="mt-3 text-xs font-semibold text-red-300">{copy.failed}</p> : null}
      </main>
    </div>
  );
}
