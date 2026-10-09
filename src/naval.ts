import { forgeFetch } from './apiClient';

export const SHIP_MODELS = [
  { id: 'small', name: 'Barco pequeno', size: 145 }, { id: 'caravel', name: 'Caravela', size: 180 },
  { id: 'pirate', name: 'Navio pirata', size: 205 }, { id: 'war', name: 'Navio de guerra', size: 220 },
  { id: 'legendary', name: 'Navio lendário', size: 240 }, { id: 'special', name: 'Navio especial', size: 225 },
] as const;
export const SHIP_SKINS = [
  { id: 'black', name: 'Pirata Negro' }, { id: 'inferno', name: 'Inferno' }, { id: 'deep', name: 'Mar Profundo' },
  { id: 'storm', name: 'Tempestade' }, { id: 'reaper', name: 'Ceifador' }, { id: 'king', name: 'Rei dos Mares' },
] as const;
export type ShipCosmetics = { flag: 'skull' | 'sun' | 'moon'; prow: 'lion' | 'blade' | 'none'; decoration: 'gold' | 'silver' | 'none'; trail: 'foam' | 'embers' | 'mist' };
export type NavalShip = { user_id: string; name?: string; model: string; skin: string; cosmetics: ShipCosmetics; level: number; xp: number; reputation: number; hp: number; x: number; y: number; heading: number; throttle: number; battle_id: string | null };
export type NavalEvent = { id: number; actor: string; kind: string; x: number; y: number; target_x: number; target_y: number; damage: number; created_at: string };
export type NavalState = { ship: NavalShip; others: NavalShip[]; events: NavalEvent[]; battle: { id: string; status: string; attacker: string; defender: string; winner: string | null; loot: { berries?: number; items?: Record<string, number> } } | null; rules: { pvpEnabled: boolean; lootPercent: number; repairWood: number; repairIron: number }; materials: Record<string, number> };
export const DEFAULT_SHIP: NavalShip = { user_id: '', model: 'small', skin: 'black', cosmetics: { flag: 'skull', prow: 'lion', decoration: 'gold', trail: 'foam' }, level: 1, xp: 0, reputation: 0, hp: 1000, x: 1700, y: 1340, heading: 0, throttle: 0, battle_id: null };
export const shipMaxHp = (ship: NavalShip) => 1000 + (ship.level - 1) * 100;
export const shipStats = (ship: NavalShip) => ({ hull: shipMaxHp(ship), cannons: 100 + ship.level * 8, defense: ship.level * 3, speed: 120 + ship.level * 2, vision: 700 + ship.level * 10, crew: 3 + Math.floor(ship.level / 5) });
const ERRORS: Record<string, string> = {
  NAVAL_RULES_PENDING: 'Guerra naval aguarda definição do percentual e dos itens de saque.', NAVAL_MATERIALS_REQUIRED: 'Materiais insuficientes para o estaleiro.',
  NAVAL_XP_REQUIRED: 'Experiência naval insuficiente.', NAVAL_IN_BATTLE: 'Conclua a batalha antes de atracar ou mudar o navio.', NAVAL_TARGET_UNAVAILABLE: 'Esse navio não está mais disponível.',
  NAVAL_PROTECTED: 'Capitão sob proteção naval.', NAVAL_PAIR_COOLDOWN: 'Este capitão já foi enfrentado nas últimas 24 horas.', NAVAL_OUT_OF_RANGE: 'Navio fora do alcance dos canhões.',
  NAVAL_BROADSIDE_REQUIRED: 'Vire a lateral do navio para o inimigo.', NAVAL_CANNON_COOLDOWN: 'Canhões recarregando.', NAVAL_SKILL_COOLDOWN: 'Habilidade recarregando.',
  NAVAL_BOARD_UNAVAILABLE: 'Aproxime-se a menos de 100 m de um navio com até 25% de vida.', NAVAL_ESCAPE_DISTANCE: 'Afaste-se mais de 650 m para fugir.', NAVAL_NO_BATTLE: 'Nenhuma batalha naval ativa.',
  GAME_RESET: 'O oceano compartilhado está pausado durante o novo início.', REALM_LOCKED: 'O oceano compartilhado ainda não está liberado para este capitão.',
};
export async function navalCall(initData: string, navalAction: string, input: Record<string, unknown> = {}): Promise<NavalState> {
  const response = await forgeFetch('realm', { initData, action: 'naval', navalAction, input });
  const payload = await response.json() as NavalState & { error?: string; code?: string } | null;
  if (!response.ok || !payload?.ship) {
    const message = payload?.error ?? payload?.code ?? 'O oceano compartilhado não está disponível.';
    const key = Object.keys(ERRORS).find(k => message.includes(k));
    throw new Error(key ? ERRORS[key] : message);
  }
  return payload;
}