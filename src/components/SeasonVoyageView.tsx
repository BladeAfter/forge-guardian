import { useLocalizedText } from '../LanguageContext';
import { useMemo, useState } from 'react';
import { ArrowLeft, Check, LockKeyhole, X } from 'lucide-react';
import type { PassReward, PassTier, SeasonPassDashboard } from '../seasonPass';
import { formatTon } from '../economy';
import { seasonVoyageArt } from '../gameAssets';
import { voyageHeroArt } from '../voyageArt';
import { isHiddenVeteranItem } from '../retiredOfferPresentation';
import { isMythTokenReward } from '../tokenPresentation';
import { OceanControl } from './OceanControl';
import { navalMaterialArt } from '../navalMaterialArt';

/** Nautical artwork does not change the kind, amount or utility of official rewards. */
function rewardVisual(reward: PassReward) {
  const type = reward.type;
  if (/equipment/.test(type)) return { art: seasonVoyageArt.saber, name: 'Equipamento de bordo' };
  if (/food/.test(type)) return { art: seasonVoyageArt.provisions, name: 'Provisões do mascote' };
  if (/fragment|skin/.test(type)) return { art: seasonVoyageArt.chart, name: 'Fragmentos da viagem' };
  if (/ticket/.test(type)) return { art: seasonVoyageArt.chart, name: 'Bilhetes do convés' };
  if (/hero_random/.test(type)) return { art: voyageHeroArt.deckblade, name: 'Tripulante misterioso' };
  if (/egg|nft_pet|pet_random/.test(type)) return { art: seasonVoyageArt.treasure, name: 'Baú de mascote' };
  if (/myth/.test(type)) return { art: seasonVoyageArt.essence, name: 'MYTH' };
  if (/fc/.test(type)) return { art: seasonVoyageArt.treasure, name: 'BERRIES' };
  if (/wood|iron|material/.test(type)) return { art: /iron/.test(type) ? navalMaterialArt.iron_ore : navalMaterialArt.magic_wood, name: 'Materiais náuticos' };
  return { art: seasonVoyageArt.treasure, name: 'Tesouro da tripulação' };
}

type Props = { data: SeasonPassDashboard; onClose: () => void; onMissions: () => void; onBuyLevel: () => void; onBuy: (tier: PassTier) => void; buying: boolean; onClaim: (id: string) => void; claiming: boolean; onUnlock: (reward: PassReward) => void; unlocking: boolean };
export function SeasonVoyageView({ data, onClose, onMissions, onBuyLevel, onBuy, buying, onClaim, claiming, onUnlock, unlocking }: Props) {
  const localizeText = useLocalizedText();

  const [focus, setFocus] = useState<PassReward | null>(null);
  const rewards = useMemo(() => data.rewards.filter(r => !isHiddenVeteranItem(r) && !isMythTokenReward(r.type)), [data.rewards]);
  const levels = useMemo(() => {
    const grouped = new Map<number, Record<PassTier, PassReward[]>>();
    for (const reward of rewards) {
      const row = grouped.get(reward.level) ?? { adventurer: [], legendary: [] };
      row[reward.tier].push(reward); grouped.set(reward.level, row);
    }
    return Array.from({ length: Math.max(data.season.levels, ...rewards.map(r => r.level), 0) }, (_, index) => ({ level: index + 1, slots: grouped.get(index + 1) }));
  }, [data.season.levels, rewards]);
  const remaining = Math.max(0, new Date(data.season.endsAt).getTime() - Date.now());
  const xp = data.player.xpIntoLevel ?? data.player.xp % data.season.xpPerLevel;
  const maxed = data.player.maxed ?? false;
  const focusedArt = focus ? rewardVisual(focus) : null;
  const buyable = Boolean(focus?.versionLocked && focus.purchasable && !focus.claimed && Number(focus.priceTon ?? 0) > 0);
  return <main className="fullscreen-page seas-season">
    <header className="season-topbar"><OceanControl onClick={onClose} aria-label={localizeText("Voltar ao porto")}><ArrowLeft size={20} /></OceanControl><div><span>MYTHIC SEAS</span><b>{localizeText("PASSE DE TEMPORADA")}</b></div><span className="season-level-chip">{localizeText("Nv. ")}{data.player.level}</span></header>
    <section className="season-cover"><img src={seasonVoyageArt.banner} alt={localizeText("Navio de velas vermelhas rumo a ilhas tropicais")} width={1536} height={1024} /><div className="season-cover-shade" /><div className="season-cover-title"><span>{localizeText("ROTA DOS TESOUROS")}</span><h1>{localizeText("Passe de Temporada")}</h1><p>{remaining > 0 ? `${Math.floor(remaining / 86400000)}d ${Math.floor(remaining % 86400000 / 3600000)}h restantes` : localizeText("Temporada encerrada")}</p></div></section>
    <div className="season-inner">
      <section className="season-progress"><div><b>{maxed ? localizeText("Nível máximo") : `Nível ${data.player.level}`}</b><span>{maxed ? 'MAX' : `${xp.toLocaleString('pt-BR')} / ${data.season.xpPerLevel.toLocaleString('pt-BR')} XP`}</span></div><progress max={data.season.xpPerLevel} value={maxed ? data.season.xpPerLevel : xp} /><nav><OceanControl onClick={onMissions}>{localizeText("Missões")}</OceanControl>{data.levelPurchase?.enabled && !maxed ? <OceanControl onClick={onBuyLevel}>{localizeText("Comprar níveis")}</OceanControl> : null}<span>{data.player.xpBonusPercent ? `+${data.player.xpBonusPercent}% XP` : `${(data.player.xpMultiplier ?? 1).toFixed(1)}× XP`}</span></nav></section>
      <section className="season-passes" aria-label={localizeText("Passes disponíveis")}>{(['adventurer', 'legendary'] as const).map(tier => {
        const owned = tier === 'legendary' ? data.player.legendaryOwned : data.player.adventurerOwned || data.player.legendaryOwned;
        const price = tier === 'adventurer' ? data.season.adventurerPriceTon : data.player.adventurerOwned ? data.season.upgradePriceTon : data.season.legendaryPriceTon;
        const bonus = Math.round(((data.xpMultipliers?.[tier] ?? (tier === 'adventurer' ? 1.2 : 1.4)) - 1) * 100);
        return <article key={tier} className={`season-pass-option season-pass-${tier}`}><img src={tier === 'adventurer' ? seasonVoyageArt.chart : seasonVoyageArt.treasure} alt="" width={384} height={384} loading="lazy" /><h2>{tier === 'adventurer' ? localizeText("Aventureiro") : localizeText("Lendário")}</h2><strong>{owned ? localizeText("Ativo") : `${formatTon(price)} TON`}</strong><small>+{bonus}{localizeText("% XP")}</small><OceanControl disabled={owned || buying} onClick={() => onBuy(tier)}>{owned ? localizeText("Adquirido") : buying ? 'Aguarde…' : 'Comprar passe'}</OceanControl></article>;
      })}</section>
      <p className="season-inclusion">{localizeText("O Lendário inclui as recompensas do Aventureiro.")}</p>
      <section className="season-track" aria-label={localizeText("Recompensas da temporada")}><div className="season-track-head"><span>{localizeText("NÍVEL ")}</span><b>{localizeText("AVENTUREIRO")}</b><b>{localizeText("LENDÁRIO")}</b></div>{levels.map(({ level, slots }) => <div key={level} className={`season-track-row ${data.player.level >= level ? 'season-reached' : ''}`}><div className="season-milestone"><b>{level}</b></div>{(['adventurer', 'legendary'] as const).map(tier => <div className="season-reward-slots" key={tier}>{slots?.[tier].length ? [...slots[tier]].sort((a,b) => (a.slot ?? 1) - (b.slot ?? 1)).map(reward => {
        const visual = rewardVisual(reward);
        return <OceanControl key={reward.id} className={`season-reward ${reward.claimed ? 'season-reward-claimed' : ''}`} aria-label={`${visual.name}, nível ${level}, ${tier}`} title={reward.claimed ? localizeText("Recebido") : reward.versionLocked ? 'Requer passe atualizado' : reward.unlocked ? 'Resgatar recompensa' : 'Bloqueado'} onClick={() => setFocus(reward)}><img src={visual.art} alt="" width={384} height={384} loading="lazy" decoding="async" /><b>{visual.name}</b><span className="season-reward-amount">×{reward.amount.toLocaleString('pt-BR')}</span>{reward.claimed ? <Check className="season-reward-state" size={13} aria-label={localizeText("Recebido")} /> : !reward.unlocked || reward.versionLocked ? <LockKeyhole className="season-reward-state" size={12} aria-label={localizeText("Bloqueado")} /> : null}</OceanControl>;
      }) : <span className="season-no-reward">—</span>}</div>)}</div>)}</section>
    </div>
    {focus && focusedArt ? <div className="season-modal-backdrop" onClick={() => setFocus(null)}><section className="season-reward-dialog" role="dialog" aria-modal="true" aria-label={localizeText("Recompensa da temporada")} onClick={event => event.stopPropagation()}><OceanControl aria-label={localizeText("Fechar recompensa")} className="season-dialog-close" onClick={() => setFocus(null)}><X size={18} /></OceanControl><img src={focusedArt.art} alt={focusedArt.name} width={384} height={384} /><span>{localizeText("NÍVEL ")}{focus.level} · {focus.tier === 'legendary' ? localizeText("LENDÁRIO") : localizeText("AVENTUREIRO")}</span><h2>{focusedArt.name}</h2><p>{focus.amount.toLocaleString('pt-BR')} × {focus.title}</p><OceanControl disabled={focus.claimed || claiming || unlocking || (!buyable && (!focus.unlocked || focus.versionLocked))} onClick={() => { if (buyable) onUnlock(focus); else onClaim(focus.id); setFocus(null); }}>{focus.claimed ? localizeText("Recebido") : buyable ? `Desbloquear · ${formatTon(Number(focus.priceTon))} TON` : focus.versionLocked ? 'Requer passe atualizado' : focus.unlocked ? 'Resgatar recompensa' : 'Ainda bloqueado'}</OceanControl></section></div> : null}
  </main>;
}