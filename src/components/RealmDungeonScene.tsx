import { useEffect, useMemo, useRef, useState } from 'react';
import { REALM_ROOM_LABEL, type RealmRuinRoom, type RealmRuinRun, type RealmState } from '../realm';

const BG_HALL = '/assets/game/realm/dungeon-hall.jpg';
const BG_TREASURE = '/assets/game/realm/dungeon-treasure.jpg';
const BG_SHRINE = '/assets/game/realm/dungeon-shrine.jpg';
const BG_BOSS = '/assets/game/realm/dungeon-boss.jpg';
const DOOR = '/assets/game/realm/dungeon-door.png';
const PARTY = '/assets/game/realm/battle-hero.png';

const ROOM_BG: Record<string, string> = {
  combat: BG_HALL,
  elite: BG_HALL,
  trap: BG_HALL,
  rest: BG_SHRINE,
  shrine: BG_SHRINE,
  treasure: BG_TREASURE,
  boss: BG_BOSS,
};

const ROOM_HINT: Record<string, string> = {
  combat: 'Sons de passos e metal na escuridão.',
  elite: 'Algo grande respira do outro lado.',
  trap: 'O chão à frente parece instável.',
  rest: 'Uma fogueira apagada convida ao descanso.',
  shrine: 'Runas antigas pulsam com energia curativa.',
  treasure: 'Um brilho dourado escapa pelas frestas.',
  boss: 'O ar pesa. O Guardião aguarda.',
};

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
  const [phase, setPhase] = useState<Phase>('intro');
  const [flash, setFlash] = useState<string | null>(null);
  const [confirmExtract, setConfirmExtract] = useState(false);
  const seenRoom = useRef<string>('');

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
      setFlash('Você extraiu com o loot.');
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
          <span className="dungeon-hud-room">SALA {roomNumber}/10</span>
        </div>
        <div className="dungeon-loot">
          <span className="dungeon-loot-cap">LOOT</span>
          <b>{fmt(run.ruin_coins)}</b>
        </div>
      </header>

      <div className="dungeon-hp">
        <div className="dungeon-hp-fill" style={{ width: `${Math.max(0, Math.min(100, run.hp))}%` }} />
        <span className="dungeon-hp-label">VITALIDADE {Math.max(0, run.hp)}%</span>
      </div>



      {phase === 'intro' && (
        <div className="dungeon-intro">
          <b>RUÍNAS ANCESTRAIS</b>
          <span>{regionName} · descida iniciada</span>
        </div>
      )}

      {phase === 'result' && lastRoom && (
        <div className="dungeon-discovery">
          <b>{REALM_ROOM_LABEL[currentType] ?? currentType}</b>
          <p>
            {damage > 0 && <em className="text-rose-300">−{damage}% vitalidade </em>}
            {damage < 0 && <em className="text-emerald-300">+{Math.abs(damage)}% vitalidade </em>}
            +{fmt(Number((lastRoom as { coins?: number }).coins ?? 0))} loot
          </p>
          {finished === 'failed' && <span className="dungeon-fail">SUA EQUIPE CAIU</span>}
          {finished === 'cleared' && <span className="dungeon-clear">RUÍNA CONCLUÍDA</span>}
        </div>
      )}

      {/* PORTAS */}
      <div className="dungeon-doors">
        {rooms.length === 0 && phase !== 'walking' && (
          <p className="dungeon-empty">Aguardando a próxima passagem…</p>
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
            <b className="dungeon-door-label">{REALM_ROOM_LABEL[room.room_type] ?? room.room_type}</b>
            <span className="dungeon-door-hint">{ROOM_HINT[room.room_type] ?? 'Passagem desconhecida.'}</span>
            <span className="dungeon-door-diff">RISCO {room.config?.difficulty ?? 1}</span>
          </button>
        ))}
      </div>

      <button onClick={() => setConfirmExtract(true)} disabled={busy} className="dungeon-extract">
        Extrair com {fmt(run.ruin_coins)} de loot
      </button>

      {confirmExtract && (
        <div className="dungeon-modal" role="dialog">
          <div className="dungeon-modal-card">
            <b>Extrair agora?</b>
            <p>Você sai das Ruínas com {fmt(run.ruin_coins)} de loot e encerra a descida na sala {roomNumber}.</p>
            <div className="flex gap-2">
              <button onClick={() => setConfirmExtract(false)} className="dungeon-modal-ghost">Continuar</button>
              <button onClick={extract} className="dungeon-modal-cta">Extrair</button>
            </div>
          </div>
        </div>
      )}

      {flash && <div className="dungeon-flash">{flash}</div>}
    </div>
  );
}
