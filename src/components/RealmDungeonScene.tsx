import { useEffect, useMemo, useRef, useState } from 'react';
import { REALM_ROOM_LABEL_KEY, type RealmRuinRoom, type RealmRuinRun, type RealmState } from '../realm';
import { useT } from '../LanguageContext';
import RealmBattleScene from './RealmBattleScene';
import type { RealmExploreLog, RealmExploreNodeType } from '../realm';

const BG_HALL = '/assets/game/realm/dungeon-hall.jpg';
const BG_TREASURE = '/assets/game/realm/dungeon-treasure.jpg';
const BG_SHRINE = '/assets/game/realm/dungeon-shrine.jpg';
const BG_BOSS = '/assets/game/realm/dungeon-boss.jpg';
const DOOR = '/assets/game/realm/dungeon-door.png';

const ROOM_BG: Record<string, string> = {
  combat: BG_HALL,
  elite: BG_HALL,
  trap: BG_HALL,
  rest: BG_SHRINE,
  shrine: BG_SHRINE,
  treasure: BG_TREASURE,
  boss: BG_BOSS,
};

const ROOM_HINT_KEY: Record<string, string> = {
  combat: 'realm.dungeon.hint.combat',
  elite: 'realm.dungeon.hint.elite',
  trap: 'realm.dungeon.hint.trap',
  rest: 'realm.dungeon.hint.rest',
  shrine: 'realm.dungeon.hint.shrine',
  treasure: 'realm.dungeon.hint.treasure',
  boss: 'realm.dungeon.hint.boss',
};

const FIGHT_ROOMS = ['combat', 'elite', 'boss'];

/**
 * Turns the authoritative room result into a round-by-round script for the duel scene.
 * Presentation only: the totals (damage taken, loot) come straight from the server.
 */
function duelLogFrom(lastRoom: Record<string, unknown>): RealmExploreLog {
  const type = String(lastRoom.roomType ?? 'combat') as RealmExploreNodeType;
  const damage = Math.max(0, Number(lastRoom.damage ?? 0));
  const coins = Math.max(1, Number(lastRoom.coins ?? 0));
  const failed = String(lastRoom.result ?? '') === 'failed';
  const turns = type === 'boss' ? 5 : type === 'elite' ? 4 : 3;
  const rounds = Array.from({ length: turns }).map((_, i) => ({
    round: i + 1,
    playerHit: Math.max(1, Math.round((coins * 4) / turns)),
    enemyHit: Math.max(1, Math.round((damage * 12) / turns)),
  }));
  return {
    nodeType: type,
    rounds,
    damage,
    fc: coins,
    hp: Number(lastRoom.hp ?? 0),
    result: failed ? 'failed' : String(lastRoom.result ?? '') === 'cleared' ? 'cleared' : 'ongoing',
  };
}

const fmt = (n: number) => new Intl.NumberFormat('pt-BR').format(Math.floor(n || 0));

type Phase = 'intro' | 'idle' | 'walking' | 'result';

/**
 * MODO DUNGEON FULLSCREEN — Ruínas Ancestrais.
 * Puramente visual: toda a matemática (dano, loot, salas, boss) continua no servidor.
 */
export default function RealmDungeonScene({
  run,
  rooms,
  lastRoom,
  regionName,
  busy,
  onChoose,
  onExtract,
  onLeave,
}: {
  run: RealmRuinRun;
  rooms: RealmRuinRoom[];
  lastRoom?: Record<string, unknown>;
  regionName: string;
  busy: boolean;
  onChoose: (branch: number) => Promise<RealmState | null>;
  onExtract: () => Promise<RealmState | null>;
  onLeave: () => void;
}) {
  const t = useT();
  const [phase, setPhase] = useState<Phase>('intro');
  const [flash, setFlash] = useState<string | null>(null);
  const [confirmExtract, setConfirmExtract] = useState(false);
  const seenRoom = useRef<string>('');
  const [duel, setDuel] = useState<RealmExploreLog | null>(null);

  const roomNumber = Math.min(run.current_room + 1, 10);
  const bossNext = roomNumber >= 10 || rooms.some((r) => r.room_type === 'boss');

  useEffect(() => {
    const id = window.setTimeout(() => setPhase((p) => (p === 'intro' ? 'idle' : p)), 1800);
    return () => window.clearTimeout(id);
  }, []);

  /* Sempre que o servidor devolve um novo resultado de sala, mostramos o banner de descoberta. */
  useEffect(() => {
    if (!lastRoom) return;
    const key = JSON.stringify(lastRoom);
    if (key === seenRoom.current) return;
    seenRoom.current = key;
    if (FIGHT_ROOMS.includes(String((lastRoom as { roomType?: string }).roomType ?? ''))) {
      setDuel(duelLogFrom(lastRoom));
      setPhase('idle');
      return;
    }
    setPhase('result');
    const id = window.setTimeout(() => setPhase('idle'), 2600);
    return () => window.clearTimeout(id);
  }, [lastRoom]);

  const currentType = String((lastRoom as { roomType?: string } | undefined)?.roomType ?? 'combat');
  const bg = useMemo(() => (bossNext ? BG_BOSS : ROOM_BG[currentType] ?? BG_HALL), [bossNext, currentType]);

  const choose = async (branch: number) => {
    if (busy || phase === 'walking') return;
    setPhase('walking');
    const next = await onChoose(branch);
    if (!next) setPhase('idle');
  };

  const extract = async () => {
    setConfirmExtract(false);
    const next = await onExtract();
    if (next) {
      setFlash(t('realm.dungeon.extracted'));
      window.setTimeout(onLeave, 900);
    }
  };

  const damage = Number((lastRoom as { damage?: number } | undefined)?.damage ?? 0);
  const finished = String((lastRoom as { result?: string } | undefined)?.result ?? '');

  return (
    <div className="dungeon-mode">
      <img src={bg} alt="" className="dungeon-bg" loading="eager" width={1280} height={720} />
      <div className="dungeon-vignette" aria-hidden />
      <div className="dungeon-dust" aria-hidden />
      <div className="dungeon-floor-glow" aria-hidden />

      {/* HUD */}
      <header className="dungeon-hud">
        <button onClick={onLeave} className="dungeon-hud-exit">‹ Sair</button>
        <div className="dungeon-hud-mid">
          <b className="dungeon-hud-region">{regionName}</b>
          <div className="dungeon-depth">
            {Array.from({ length: 10 }).map((_, i) => (
              <span key={i} className={`dungeon-pip ${i < roomNumber - 1 ? 'is-done' : i === roomNumber - 1 ? 'is-now' : ''}`} />
            ))}
          </div>
          <span className="dungeon-hud-room">{t('realm.dungeon.room', { n: roomNumber })}</span>
        </div>
        <div className="dungeon-loot">
          <span className="dungeon-loot-cap">
            {t('realm.dungeon.lootCap')}
            {run.entry_tier === 'ton' && <em className="ml-1 not-italic text-amber-300">TON</em>}
          </span>
          <b>{fmt(run.ruin_coins)}</b>
        </div>

      </header>

      <div className="dungeon-hp">
        <div className="dungeon-hp-fill" style={{ width: `${Math.max(0, Math.min(100, run.hp))}%` }} />
        <span className="dungeon-hp-label">{t('realm.dungeon.vitality', { v: Math.max(0, run.hp) })}</span>
      </div>



      {phase === 'intro' && (
        <div className="dungeon-intro">
          <b>{t('realm.ruins.title')}</b>
          <span>{t('realm.dungeon.descentStarted', { region: regionName })}</span>
        </div>
      )}

      {phase === 'result' && lastRoom && (
        <div className="dungeon-discovery">
          <b>{t(REALM_ROOM_LABEL_KEY[currentType] ?? '') || currentType}</b>
          <p>
            {damage > 0 && <em className="text-rose-300">−{damage}% {t('realm.dungeon.vit')} </em>}
            {damage < 0 && <em className="text-emerald-300">+{Math.abs(damage)}% {t('realm.dungeon.vit')} </em>}
            +{fmt(Number((lastRoom as { coins?: number }).coins ?? 0))} {t('realm.dungeon.loot')}
          </p>
          {finished === 'failed' && <span className="dungeon-fail">{t('realm.dungeon.failed')}</span>}
          {finished === 'cleared' && <span className="dungeon-clear">{t('realm.dungeon.cleared')}</span>}
        </div>
      )}

      {/* PORTAS */}
      <div className="dungeon-doors">
        {rooms.length === 0 && phase !== 'walking' && (
          <p className="dungeon-empty">{t('realm.dungeon.waiting')}</p>
        )}
        {rooms.map((room) => (
          <button
            key={room.id}
            disabled={busy || phase === 'walking'}
            onClick={() => choose(room.branch)}
            className={`dungeon-door ${room.room_type === 'boss' ? 'is-boss' : ''}`}
          >
            <img src={DOOR} alt="" className="dungeon-door-art" loading="lazy" width={768} height={1024} />
            <span className="dungeon-door-glow" aria-hidden />
            <b className="dungeon-door-label">{t(REALM_ROOM_LABEL_KEY[room.room_type] ?? '') || room.room_type}</b>
            <span className="dungeon-door-hint">{t(ROOM_HINT_KEY[room.room_type] ?? 'realm.dungeon.hint.unknown')}</span>
            <span className="dungeon-door-diff">{t('realm.dungeon.risk', { n: room.config?.difficulty ?? 1 })}</span>
          </button>
        ))}
      </div>

      <button onClick={() => setConfirmExtract(true)} disabled={busy} className="dungeon-extract">
        {t('realm.dungeon.extractWith', { n: fmt(run.ruin_coins) })}
      </button>

      {confirmExtract && (
        <div className="dungeon-modal" role="dialog">
          <div className="dungeon-modal-card">
            <b>{t('realm.dungeon.extractNow')}</b>
            <p>{t('realm.dungeon.extractDesc', { n: fmt(run.ruin_coins), room: roomNumber })}</p>
            <div className="flex gap-2">
              <button onClick={() => setConfirmExtract(false)} className="dungeon-modal-ghost">{t('realm.dungeon.continue')}</button>
              <button onClick={extract} className="dungeon-modal-cta">{t('realm.dungeon.extract')}</button>
            </div>
          </div>
        </div>
      )}

      {duel && (
        <RealmBattleScene
          log={duel}
          duel
          regionId={run.region_id}
          regionName={regionName}
          onClose={() => setDuel(null)}
        />
      )}

      {flash && <div className="dungeon-flash">{flash}</div>}
    </div>
  );
}
