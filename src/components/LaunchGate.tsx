import { lazy, Suspense, useCallback, useEffect, useRef, useState } from 'react';
import { Copy, MessageCircle, Share2, Trophy, RefreshCw } from 'lucide-react';
import { backgrounds, logo } from '../gameAssets';
import { forgeFetch, fetchWithTimeout, forgeBackendUrl } from '../apiClient';
import { supabaseAnonKey } from '../supabaseEnv';
import { waitForTelegramInitData } from '../telegram';
import { buildTelegramShareUrl } from '../referrals';
import { launchSeconds, sampleLaunchClock, type LaunchClock } from '../launchClock';

const Game = lazy(() => import('../App'));
type Board = { launchAt: string; serverNow: string; released: boolean; referralLink?: string; invites?: number; position?: number; ranking?: Array<{ position: number; name: string; invites: number; isYou: boolean }> };
export function LaunchGate() {
  const [board, setBoard] = useState<Board | null>(null);
  const [clock, setClock] = useState<LaunchClock | null>(null);
  const [seconds, setSeconds] = useState<number | null>(null);
  const [access, setAccess] = useState<'checking' | 'mobile' | 'denied' | 'offline' | 'released'>('checking');
  const [copied, setCopied] = useState(false);
  const busy = useRef(false);
  const sync = useCallback(async () => {
    if (busy.current) return;
    busy.current = true;
    try {
      const response = await fetchWithTimeout(`${forgeBackendUrl}/launch-time`, { headers: { apikey: supabaseAnonKey }, cache: 'no-store' });
      if (!response.ok) throw new Error('Clock unavailable');
      const time = await response.json() as Board;
      setClock(sampleLaunchClock(time.launchAt, time.serverNow, performance.now()));
      const app = await waitForTelegramInitData();
      if (!app?.initData || !['android', 'ios'].includes(app.platform ?? '')) { setAccess('denied'); return; }
      const result = await forgeFetch('launch', { initData: app.initData });
      if (!result.ok) { setAccess(result.status === 401 || result.status === 403 ? 'denied' : 'offline'); return; }
      const data = await result.json() as Board;
      setClock(sampleLaunchClock(data.launchAt, data.serverNow, performance.now()));
      setBoard(data);
      setAccess(data.released === true ? 'released' : 'mobile');
    } catch { setAccess('offline'); }
    finally { busy.current = false; }
  }, []);
  useEffect(() => {
    void sync();
    const timer = window.setInterval(() => void sync(), 30000);
    const focus = () => { if (document.visibilityState === 'visible') void sync(); };
    document.addEventListener('visibilitychange', focus);
    window.addEventListener('online', sync);
    return () => { clearInterval(timer); document.removeEventListener('visibilitychange', focus); window.removeEventListener('online', sync); };
  }, [sync]);
  useEffect(() => {
    if (!clock) return;
    const tick = () => setSeconds(launchSeconds(clock, performance.now()));
    tick();
    const interval = window.setInterval(tick, 1000);
    return () => clearInterval(interval);
  }, [clock]);
  useEffect(() => { if (seconds === 0 && access === 'mobile') void sync(); }, [seconds, access, sync]);
  if (access === 'released') return <Suspense fallback={<div className="launch-screen" />}><Game /></Suspense>;
  const parts = seconds === null ? ['—', '—', '—', '—'] : [Math.floor(seconds / 86400), Math.floor(seconds / 3600) % 24, Math.floor(seconds / 60) % 60, seconds % 60].map(v => String(v).padStart(2, '0'));
  const open = (url: string) => { const app = window.Telegram?.WebApp; if (app?.openTelegramLink) app.openTelegramLink(url); else window.open(url, '_blank', 'noopener,noreferrer'); };
  return <main className="launch-screen" lang="en">
    <img className="launch-ocean" src={backgrounds.loading} alt="" fetchPriority="high" />
    <div className="launch-shade" />
    <div className="launch-content">
      <img className="launch-logo" src={logo.horizontal} alt="Mythic Seas — The Grand Adventure" />
      <section className="launch-countdown" aria-label="Launch countdown">
        <p className="launch-eyebrow">THE GRAND ADVENTURE BEGINS IN</p>
        <div className="launch-digits">{parts.map((part, i) => <div key={i}><strong>{part}</strong><span>{['DAYS', 'HOURS', 'MINUTES', 'SECONDS'][i]}</span></div>)}</div>
        <p className="launch-date">OCTOBER 12, 2026 · 18:00 UTC</p>
        <div className="launch-wait"><span />{access === 'checking' ? 'Connecting to the harbor…' : access === 'offline' ? 'Connection lost · waiting for server' : access === 'denied' ? 'Open in Telegram on your phone' : 'The fleet is gathering'}</div>
      </section>
      <nav className="launch-actions" aria-label="Community links">
        <a className="launch-control" href="https://t.me/MythicSeasChat" target="_blank" rel="noreferrer" onClick={e => { e.preventDefault(); open('https://t.me/MythicSeasChat'); }}><MessageCircle size={18} />Join the chat</a>
        {access === 'denied' && <a className="launch-control launch-primary" href="https://t.me/MythicSeasbot">Open Telegram</a>}
        {access === 'offline' && <button type="button" className="launch-control" onClick={() => void sync()}><RefreshCw size={18} />Reconnect</button>}
      </nav>
      {access === 'mobile' && board?.referralLink && <section className="launch-referrals" aria-label="Your invitation">
        <div className="launch-section-title"><h2>Invite your crew</h2><span>{board.invites ?? 0} joined</span></div>
        <div className="launch-link"><input readOnly aria-label="Your unique invitation link" value={board.referralLink} /><button className="launch-icon" aria-label={copied ? 'Copied' : 'Copy invitation link'} title={copied ? 'Copied' : 'Copy invitation link'} onClick={async () => { try { await navigator.clipboard.writeText(board.referralLink ?? ''); setCopied(true); } catch { setCopied(false); } }}><Copy size={18} /></button><button className="launch-icon" aria-label="Share invitation" title="Share invitation" onClick={() => open(buildTelegramShareUrl(board.referralLink ?? '', 'Join my crew in Mythic Seas! Launch: October 12 at 18:00 UTC.'))}><Share2 size={18} /></button></div>
        {copied && <small className="launch-feedback">Invitation copied</small>}
      </section>}
      {access === 'mobile' && <section className="launch-ranking" aria-label="Referral leaderboard">
        <div className="launch-section-title"><h2><Trophy size={17} />Crew leaderboard</h2><span>{board?.position ? `Your rank #${board.position}` : 'Live standings'}</span></div>
        {board?.ranking?.length ? <ol>{board.ranking.map(row => <li key={row.position} className={row.isYou ? 'launch-you' : ''}><b>{String(row.position).padStart(2, '0')}</b><span>{row.name}{row.isYou ? ' · You' : ''}</span><strong>{row.invites}<small> crew</small></strong></li>)}</ol> : <p className="launch-empty">No crews on the leaderboard yet.</p>}
      </section>}
      <footer className="launch-footer">{access === 'mobile' ? 'Only verified arrivals count. One captain, one invitation.' : 'Available exclusively in the Telegram mobile Mini App.'}</footer>
    </div>
  </main>;
}