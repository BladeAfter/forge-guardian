import { Anchor, ArrowLeft, Copy, RefreshCw, Share2, Users } from 'lucide-react';
import { crewArt, logo } from '../gameAssets';
import type { ReferralDashboard, ReferralInvite } from '../referrals';
import { formatTon } from '../economy';
import { OceanControl } from './OceanControl';

type Translator = (key: string, vars?: Record<string, unknown>) => string;
type Props = {
  data?: ReferralDashboard; invites: ReferralInvite[]; isLoading: boolean; failed: boolean;
  level: 1 | 2 | 3 | undefined; t: Translator; languageCode: string;
  onClose: () => void; onRetry: () => void; onCopy: (value: string, message?: string) => void;
  onShare: () => void; onLevel: (value: 1 | 2 | 3 | undefined) => void; onMore: () => void;
};

/** Nautical presentation only: all referral totals, rates and links come from the server. */
export function ReferralDeckView({ data, invites, isLoading, failed, level, t, languageCode, onClose, onRetry, onCopy, onShare, onLevel, onMore }: Props) {
  return <div className="seas-invites">
    <header className="invite-topbar">
      <OceanControl onClick={onClose} aria-label={t('close')} title={t('close')}><ArrowLeft /></OceanControl>
      <img src={logo.horizontal} alt="Mythic Seas" />
      <Anchor aria-hidden="true" />
    </header>
    <div className="invite-cover">
      <img src={crewArt.deck} alt="" />
      <div className="invite-cover-shade" />
      <div className="invite-cover-title"><span>MYTHIC SEAS</span><h1>{t('profile.invite.title')}</h1></div>
    </div>
    <main className="invite-content">
      {failed ? <section className="invite-state" role="alert"><p>{t('profile.invite.loadError')}</p><OceanControl onClick={onRetry}><RefreshCw />{t('profile.invite.retry')}</OceanControl></section>
        : !data ? <section className="invite-state" role="status"><Anchor className={isLoading ? 'animate-pulse' : ''} /><p>{t('profile.invite.loading')}</p></section>
        : <>
          <section className="invite-link-band">
            <h2>{t('profile.invite.myLink')}</h2>
            <p className="invite-link">{data.link}</p>
            <div className="invite-link-actions"><OceanControl onClick={() => onCopy(data.link)}><Copy />{t('profile.invite.copyLink')}</OceanControl><OceanControl className="invite-share" onClick={onShare}><Share2 />{t('profile.invite.share')}</OceanControl></div>
            <OceanControl className="invite-id" onClick={() => onCopy(String(data.telegramId), t('profile.invite.idCopied'))}>{t('profile.invite.myInviteId', { id: data.telegramId })}</OceanControl>
          </section>
          <dl className="invite-totals"><div><dt>{t('profile.invite.totalInvited')}</dt><dd>{data.counts.total}</dd></div><div><dt>{t('profile.invite.commissionsReceived')}</dt><dd>{formatTon(data.earningsTon?.total ?? 0)} <small>TON</small></dd></div></dl>
          <section className="invite-commission-band"><h2><Anchor />{t('profile.invite.commissionLevels')}</h2>
            <div className="invite-routes">{data.commissionLevels?.map(row => <div key={row.level}><span>0{row.level}</span><strong>{row.percent}%</strong><small>{t('profile.invite.invitedCount', { count: row.invitedCount })}</small><b>{formatTon(row.totalEarnedTon ?? 0)} TON</b></div>)}</div>
            <p className="invite-rule">{t('profile.invite.tonRule')}</p>
          </section>
          {Boolean(data.commissionHistory?.length) && <section className="invite-history"><h2>{t('profile.invite.commissionHistory')}</h2>{data.commissionHistory?.slice(0, 10).map(row => <div key={row.id}><span><b>{row.name}</b><small>{row.sourceType} · {formatTon(row.sourceAmountTon)} TON</small></span><strong>+{formatTon(row.commissionTon)} TON</strong></div>)}</section>}
          <section className="invite-roster"><h2><Users />{t('profile.invite.myInvited')}</h2>
            <nav aria-label={t('profile.invite.commissionLevels')}>{([undefined, 1, 2, 3] as const).map(value => <OceanControl key={value ?? 'all'} aria-pressed={level === value} onClick={() => onLevel(value)}>{value ? `LV${value}` : t('profile.invite.all')}</OceanControl>)}</nav>
            {invites.length ? <ul>{invites.map(person => <li key={person.id}>
              {person.avatar ? <img src={person.avatar} alt="" /> : <span className="invite-avatar"><Users /></span>}
              <div><b>{person.name}</b><small>{person.username ? `@${person.username} · ` : ''}LV{person.level} · {t(person.online ? 'profile.invite.online' : 'profile.invite.offline')}</small><small>{t('profile.invite.joinedOn', { date: new Date(person.joinedAt).toLocaleDateString(languageCode === 'pt' ? 'pt-BR' : languageCode) })}</small></div>
              <span className="invite-person-ton"><b>+{formatTon(person.commissionTon ?? 0)} TON</b><small>{t('profile.invite.generatedTon', { amount: formatTon(person.generatedTon ?? 0) })}</small></span>
            </li>)}</ul> : <div className="invite-empty"><Anchor /><p>{t('profile.invite.noInvitesYet')}</p><OceanControl onClick={onShare}><Share2 />{t('profile.invite.share')}</OceanControl></div>}
            {data.pagination?.hasMore && <OceanControl className="invite-more" disabled={isLoading} onClick={onMore}>{t(isLoading ? 'profile.invite.loading' : 'profile.invite.loadMore')}</OceanControl>}
          </section>
        </>}
    </main>
  </div>;
}