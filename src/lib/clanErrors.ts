// Server error codes are stable identifiers; the player always sees PT-BR text.
const CLAN_ERRORS: Record<string, string> = {
  RAID_PHASE_LOCKED: 'Fase do dia concluída! O chefão travou nesta faixa de HP — o próximo trecho abre amanhã. Seus ataques não foram gastos.',
  RAID_DAILY_LIMIT: 'Você já usou todos os seus ataques de hoje.',
  RAID_NOT_ACTIVE: 'Nenhuma raid ativa no momento.',
  RAID_EXPIRED: 'O prazo desta raid terminou.',
  RAID_DISABLED: 'A Clan Raid está desativada.',
  NOT_IN_CLAN: 'Você precisa estar em um clã.',
  CLAN_UPGRADE_FORBIDDEN: 'Apenas o líder ou vice-líder pode comprar melhorias.',
  TREASURY_INSUFFICIENT: 'O tesouro do clã não tem recursos suficientes.',
  SHOP_OUT_OF_STOCK: 'Estoque semanal do clã esgotado para este item.',
  SHOP_PERSONAL_LIMIT: 'Você já atingiu seu limite pessoal deste item nesta semana.',
  SHOP_DAILY_LIMIT: 'Você já atingiu o limite de hoje deste item.',
  INSUFFICIENT_COINS: 'Clan Coins insuficientes.',
  CLAN_JOIN_COOLDOWN: 'Você saiu de um clã recentemente. Aguarde o cooldown de 24h.',
};

export function clanErrorMessage(error: unknown, fallback = 'Ação indisponível.') {
  const raw = error instanceof Error ? error.message : typeof error === 'string' ? error : '';
  const code = raw.trim().toUpperCase().replace(/[^A-Z0-9_]/g, '_');
  if (CLAN_ERRORS[code]) return CLAN_ERRORS[code];
  const hit = Object.keys(CLAN_ERRORS).find((k) => code.includes(k));
  if (hit) return CLAN_ERRORS[hit];
  return raw && !/^[A-Z0-9_]+$/.test(raw.trim()) ? raw : fallback;
}
