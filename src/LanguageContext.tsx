import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { forgeFetch } from './apiClient';
import { translate, translateError, type LanguageCode, type Translator } from './i18n';
import { LANGUAGE_CODES, LANGUAGE_LABELS, normalizeLanguage } from './locales/registry';

const STORAGE_KEY = 'mythreon-language';
const LEGACY_STORAGE_KEY = 'forge-village-language';

type LanguageContextValue = {
  language: LanguageCode;
  /** True once the persisted (backend or local) language has been resolved. */
  ready: boolean;
  /** Saves the manual choice: instant UI switch + backend persistence per user. */
  setLanguage: (code: LanguageCode) => Promise<void>;
  /** Applies a server/Telegram suggestion without overriding a manual choice. */
  applyRemoteLanguage: (code: string | null | undefined, locked?: boolean) => void;
  t: Translator;
  /** Translates a backend error code into localized, player-safe copy. */
  tError: (error: unknown) => string;
};

const LanguageContext = createContext<LanguageContextValue | null>(null);

const readStored = (): { code: LanguageCode | null; locked: boolean } => {
  try {
    const stored = localStorage.getItem(STORAGE_KEY);
    if (stored) {
      const parsed = JSON.parse(stored) as { code?: string; locked?: boolean };
      if (parsed?.code && LANGUAGE_CODES.includes(normalizeLanguage(parsed.code))) {
        return { code: normalizeLanguage(parsed.code), locked: Boolean(parsed.locked) };
      }
    }
    const legacy = localStorage.getItem(LEGACY_STORAGE_KEY);
    if (legacy) return { code: normalizeLanguage(legacy), locked: true };
  } catch {
    /* storage unavailable (private mode) — fall back to Telegram/browser locale */
  }
  return { code: null, locked: false };
};

const telegramLanguage = (): LanguageCode => {
  const tg = (window as unknown as { Telegram?: { WebApp?: { initDataUnsafe?: { user?: { language_code?: string } } } } }).Telegram;
  return normalizeLanguage(tg?.WebApp?.initDataUnsafe?.user?.language_code ?? navigator.language);
};

/**
 * Single global source of truth for the MYTHREON interface language.
 *
 * Resolution order on boot: manual local choice -> stored suggestion ->
 * Telegram `language_code` -> English. Once the player picks a language
 * manually it is locked and never overridden by Telegram again; the backend
 * (`game_players.language`) is the persistent per-user source.
 */
export function LanguageProvider({ children, initData }: { children: ReactNode; initData?: string }) {
  const stored = useRef(readStored());
  const [language, setLanguageState] = useState<LanguageCode>(() => stored.current.code ?? telegramLanguage());
  const [locked, setLocked] = useState<boolean>(() => stored.current.locked);
  const [ready, setReady] = useState<boolean>(() => stored.current.code !== null);

  useEffect(() => {
    // No stored preference: resolve immediately from Telegram to avoid a flash.
    if (!ready) {
      setLanguageState((current) => current ?? telegramLanguage());
      setReady(true);
    }
  }, [ready]);

  const persistLocal = useCallback((code: LanguageCode, isLocked: boolean) => {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify({ code, locked: isLocked }));
      localStorage.setItem(LEGACY_STORAGE_KEY, code);
    } catch {
      /* ignore storage failures */
    }
  }, []);

  const applyRemoteLanguage = useCallback(
    (code: string | null | undefined, remoteLocked?: boolean) => {
      if (!code) return;
      const normalized = normalizeLanguage(code);
      // A manual local choice always wins over server suggestions.
      if (locked && !remoteLocked) return;
      setLanguageState(normalized);
      if (remoteLocked) setLocked(true);
      persistLocal(normalized, Boolean(remoteLocked) || locked);
      setReady(true);
    },
    [locked, persistLocal],
  );

  const setLanguage = useCallback(
    async (code: LanguageCode) => {
      const normalized = normalizeLanguage(code);
      setLanguageState(normalized);
      setLocked(true);
      setReady(true);
      persistLocal(normalized, true);
      const session = initData || (window as unknown as { Telegram?: { WebApp?: { initData?: string } } }).Telegram?.WebApp?.initData || '';
      if (!session) return;
      try {
        const response = await forgeFetch('language', { initData: session, language: normalized });
        if (!response.ok) throw new Error('LANGUAGE_SAVE_FAILED');
      } catch (error) {
        console.error('[LANGUAGE SAVE FAILED]', error);
        throw error instanceof Error ? error : new Error('LANGUAGE_SAVE_FAILED');
      }
    },
    [initData, persistLocal],
  );

  const value = useMemo<LanguageContextValue>(
    () => ({
      language,
      ready,
      setLanguage,
      applyRemoteLanguage,
      t: (key: string, vars?: Record<string, string | number>) => translate(language, key, vars),
      tError: (error: unknown) => translateError(language, error),
    }),
    [language, ready, setLanguage, applyRemoteLanguage],
  );

  return <LanguageContext.Provider value={value}>{children}</LanguageContext.Provider>;
}

export function useLanguage(): LanguageContextValue {
  const context = useContext(LanguageContext);
  if (!context) throw new Error('useLanguage must be used inside <LanguageProvider>');
  return context;
}

/** Convenience hook: `const t = useT();` */
export function useT(): Translator {
  return useLanguage().t;
}

export { LANGUAGE_CODES, LANGUAGE_LABELS };
export type { LanguageCode };
