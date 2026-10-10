import type { LanguageCode } from './registry';
export const TREASURE_TRANSLATIONS: Record<LanguageCode, Record<string, string>> = {
  pt: {},
  en: { 'X · Tesouro enterrado': 'X · Buried treasure', 'Mapa de tesouro': 'Treasure map', 'Recolher mapa': 'Collect map', 'Abrir': 'Open', 'Mapa de tesouro necessário.': 'Treasure map required.' },
  es: { 'X · Tesouro enterrado': 'X · Tesoro enterrado', 'Mapa de tesouro': 'Mapa del tesoro', 'Recolher mapa': 'Recoger mapa', 'Abrir': 'Abrir', 'Mapa de tesouro necessário.': 'Se necesita un mapa del tesoro.' },
  ru: { 'X · Tesouro enterrado': 'X · Зарытое сокровище', 'Mapa de tesouro': 'Карта сокровищ', 'Recolher mapa': 'Забрать карту', 'Abrir': 'Открыть', 'Mapa de tesouro necessário.': 'Нужна карта сокровищ.' },
  tr: { 'X · Tesouro enterrado': 'X · Gömülü hazine', 'Mapa de tesouro': 'Hazine haritası', 'Recolher mapa': 'Haritayı al', 'Abrir': 'Aç', 'Mapa de tesouro necessário.': 'Hazine haritası gerekli.' },
};
