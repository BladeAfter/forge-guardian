import type { LanguageCode } from './registry';

const copy: Record<string, [string, string, string, string, string]> = {
  'Fleet Coins': ['Moedas da frota', 'Fleet Coins', 'Monedas de flota', 'Монеты флотилии', 'Filo paraları'],
  'magic wood': ['Madeira mágica', 'Magic wood', 'Madera mágica', 'Магическая древесина', 'Büyülü ahşap'],
  'iron ore': ['Minério de ferro', 'Iron ore', 'Mineral de hierro', 'Железная руда', 'Demir cevheri'],
  'Entre em uma frota para acessar a progressão coletiva.': ['Entre em uma frota para acessar a progressão coletiva.', 'Join a fleet to access collective progression.', 'Únete a una flota para acceder al progreso colectivo.', 'Вступите во флотилию для общего прогресса.', 'Ortak ilerleme için bir filoya katıl.'],
  'Não foi possível carregar a Grand Fleet.': ['Não foi possível carregar a Grand Fleet.', 'Unable to load Grand Fleet.', 'No se pudo cargar Grand Fleet.', 'Не удалось загрузить Grand Fleet.', 'Grand Fleet yüklenemedi.'],
  'Grand Fleet Raid': ['Ataque da Grand Fleet', 'Grand Fleet Raid', 'Incursión de Grand Fleet', 'Рейд Grand Fleet', 'Grand Fleet Baskını'],
  'Tesouro do clã': ['Tesouro da frota', 'Fleet treasury', 'Tesoro de la flota', 'Казна флотилии', 'Filo hazinesi'],
  'Tesouro do Clã': ['Tesouro da frota', 'Fleet treasury', 'Tesoro de la flota', 'Казна флотилии', 'Filo hazinesi'],
  'Fundos do clã insuficientes': ['Fundos da frota insuficientes', 'Insufficient fleet funds', 'Fondos de la flota insuficientes', 'Недостаточно средств флотилии', 'Filo fonları yetersiz'],
  'Buffs de Guilda': ['Bônus da frota', 'Fleet buffs', 'Bonificaciones de la flota', 'Усиления флотилии', 'Filo güçlendirmeleri'],
  'Loja do Clã': ['Armazém da frota', 'Fleet store', 'Almacén de la flota', 'Магазин флотилии', 'Filo mağazası'],
  'clã': ['frota', 'fleet', 'flota', 'флотилия', 'filo'],
  'Abrir Guerra de Clãs': ['Abrir guerra de frotas', 'Open fleet war', 'Abrir guerra de flotas', 'Открыть войну флотилий', 'Filo savaşını aç'],
};
const languages = ['pt', 'en', 'es', 'ru', 'tr'] as const;
export function grandFleetLiteral(language: LanguageCode, text: string): string | undefined {
  const index = languages.indexOf(language as typeof languages[number]);
  return index < 0 ? undefined : copy[text]?.[index];
}