import type { LanguageCode } from './registry';
const copy: Record<string, [string, string, string, string]> = {
  'Personalização disponível apenas nos navios comprados.': ['Customization is only available for purchased ships.', 'Personalización disponible solo para barcos comprados.', 'Настройка доступна только для купленных кораблей.', 'Özelleştirme yalnızca satın alınan gemilerde kullanılabilir.'],
  'Personalização salva!': ['Customization saved!', '¡Personalización guardada!', 'Настройки сохранены!', 'Özelleştirme kaydedildi!'],
  'Não foi possível salvar a personalização.': ['Unable to save customization.', 'No se pudo guardar la personalización.', 'Не удалось сохранить настройки.', 'Özelleştirme kaydedilemedi.'],
  'Cor do casco': ['Hull color', 'Color del casco', 'Цвет корпуса', 'Gövde rengi'],
  'Cor das velas': ['Sail color', 'Color de las velas', 'Цвет парусов', 'Yelken rengi'],
  'Cor da bandeira': ['Flag color', 'Color de la bandera', 'Цвет флага', 'Bayrak rengi'],
  'Emblema da bandeira': ['Flag emblem', 'Emblema de bandera', 'Эмблема флага', 'Bayrak amblemi'],
  'Original': ['Original', 'Original', 'Исходный', 'Orijinal'],
  'Vermelho': ['Red', 'Rojo', 'Красный', 'Kırmızı'],
  'Azul': ['Blue', 'Azul', 'Синий', 'Mavi'],
  'Verde': ['Green', 'Verde', 'Зелёный', 'Yeşil'],
  'Dourado': ['Gold', 'Dorado', 'Золотой', 'Altın'],
  'Preto': ['Black', 'Negro', 'Чёрный', 'Siyah'],
  'Branco': ['White', 'Blanco', 'Белый', 'Beyaz'],
  'SALVAR APARÊNCIA': ['SAVE APPEARANCE', 'GUARDAR APARIENCIA', 'СОХРАНИТЬ ОБЛИК', 'GÖRÜNÜMÜ KAYDET'],
  'RESTAURAR': ['RESET', 'RESTABLECER', 'СБРОСИТЬ', 'SIFIRLA'],
  'Prévia do navio personalizado': ['Customized ship preview', 'Vista previa del barco personalizado', 'Предпросмотр корабля', 'Özelleştirilmiş gemi önizlemesi'],
  'Figura de proa': ['Figurehead', 'Mascarón de proa', 'Носовая фигура', 'Baş figürü'],
  'Decoração': ['Decoration', 'Decoración', 'Украшение', 'Dekorasyon'],
  'Esteira e efeitos': ['Wake and effects', 'Estela y efectos', 'След и эффекты', 'İz ve efektler'],
  'Caveira': ['Skull', 'Calavera', 'Череп', 'Kafatası'], 'Sol': ['Sun', 'Sol', 'Солнце', 'Güneş'], 'Lua': ['Moon', 'Luna', 'Луна', 'Ay'],
  'Leão': ['Lion', 'León', 'Лев', 'Aslan'], 'Lâmina': ['Blade', 'Hoja', 'Клинок', 'Bıçak'], 'Sem figura': ['No figurehead', 'Sin figura', 'Без фигуры', 'Figür yok'],
  'Ouro': ['Gold', 'Oro', 'Золото', 'Altın'], 'Prata': ['Silver', 'Plata', 'Серебро', 'Gümüş'], 'Sem decoração': ['No decoration', 'Sin decoración', 'Без украшений', 'Dekorasyon yok'],
  'Espuma': ['Foam', 'Espuma', 'Пена', 'Köpük'], 'Brasas': ['Embers', 'Brasas', 'Искры', 'Köz'], 'Névoa': ['Mist', 'Niebla', 'Туман', 'Sis'],
};
export function shipCustomizationLiteral(language: LanguageCode, text: string): string | undefined {
  if (language === 'pt') return copy[text] ? text : undefined;
  return copy[text]?.[(['en', 'es', 'ru', 'tr'] as const).indexOf(language)];
}