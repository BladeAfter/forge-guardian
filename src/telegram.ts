export type TelegramUser = {
  id: number;
  first_name: string;
  last_name?: string;
  username?: string;
  photo_url?: string;
};

export type TelegramWebApp = {
  initData: string;
  initDataUnsafe?: { user?: TelegramUser; start_param?: string };
  ready: () => void;
  expand: () => void;
  openTelegramLink?: (url:string) => void;
  launchParams?: {startParam?:string};
  BackButton?:{show:()=>void;hide:()=>void;onClick:(callback:()=>void)=>void;offClick:(callback:()=>void)=>void};
};

export const normalizeTelegramStartParam=(value:unknown):string|null=>{
  const normalized=String(value??'').trim();
  return normalized&&normalized.length<=128&&/^[A-Za-z0-9_-]+$/.test(normalized)?normalized:null;
};

export const getTelegramStartParam=(webApp:TelegramWebApp|null)=>{
  const url=typeof window==='undefined'?null:new URL(window.location.href);
  const hashParams=url?new URLSearchParams(url.hash.replace(/^#/,'')):null;
  const candidates=[webApp?.initDataUnsafe?.start_param,webApp?.launchParams?.startParam,new URLSearchParams(webApp?.initData??'').get('start_param'),url?.searchParams.get('start_param'),url?.searchParams.get('startapp'),url?.searchParams.get('tgWebAppStartParam'),hashParams?.get('tgWebAppStartParam'),hashParams?.get('startapp')];
  for(const candidate of candidates){const result=normalizeTelegramStartParam(candidate);if(result)return result;}
  return null;
};

export const getTelegramUser = (webApp: TelegramWebApp | null) => {
  if (webApp?.initDataUnsafe?.user) return webApp.initDataUnsafe.user;
  try {
    const encodedUser = new URLSearchParams(webApp?.initData ?? '').get('user');
    return encodedUser ? JSON.parse(encodedUser) as TelegramUser : null;
  } catch {
    return null;
  }
};

declare global {
  interface Window {
    Telegram?: { WebApp?: TelegramWebApp };
  }
}

export const initializeTelegram = () => {
  const webApp = window.Telegram?.WebApp;
  webApp?.ready();
  webApp?.expand();
  return webApp ?? null;
};

export const validateTelegramSession = async (initData: string) => {
  const response = await fetch('/api/telegram/validate', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ initData })
  });

  if (!response.ok) {
    const payload = await response.json().catch(() => null) as { error?: string } | null;
    throw new Error(payload?.error || 'Telegram authentication failed.');
  }
};
