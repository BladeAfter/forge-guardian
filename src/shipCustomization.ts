import type { ShipCosmetics } from './naval';

export const SHIP_COLORS = ['original', 'red', 'blue', 'green', 'gold', 'black', 'white'] as const;
export type ShipColor = typeof SHIP_COLORS[number];
export const COLOR_LABELS: Record<ShipColor, string> = { original: 'Original', red: 'Vermelho', blue: 'Azul', green: 'Verde', gold: 'Dourado', black: 'Preto', white: 'Branco' };
export const CUSTOMIZATION_DEFAULTS: ShipCosmetics = { flag: 'skull', prow: 'none', decoration: 'none', trail: 'foam', hullColor: 'original', sailColor: 'original', flagColor: 'red' };

/** The paid marker is supplied by the server, never inferred from the catalog price. */
export const canCustomizeShip = (owned?: { canCustomize?: boolean }) => owned?.canCustomize === true;
export const shipCosmetics = (saved?: Partial<ShipCosmetics>): ShipCosmetics => ({ ...CUSTOMIZATION_DEFAULTS, ...saved });

const recolored = new Map<string, HTMLCanvasElement>();
/** Cache masked bitmap recolors once per appearance, keeping texture and silhouette intact. */
export function customizedFleetImage(image: HTMLImageElement, cosmetics: ShipCosmetics, colors?: Record<string, string>): CanvasImageSource {
  if (!colors || !image.naturalWidth || ((!cosmetics.hullColor || cosmetics.hullColor === 'original') && (!cosmetics.sailColor || cosmetics.sailColor === 'original'))) return image;
  const key = `${image.src}:${cosmetics.hullColor}:${cosmetics.sailColor}:${JSON.stringify(colors)}`;
  const cached = recolored.get(key); if (cached) return cached;
  const canvas = document.createElement('canvas'); canvas.width = image.naturalWidth; canvas.height = image.naturalHeight;
  const ctx = canvas.getContext('2d', { willReadFrequently: true }); if (!ctx) return image;
  ctx.drawImage(image, 0, 0);
  try {
    const bitmap = ctx.getImageData(0, 0, canvas.width, canvas.height);
    const rgb = (color?: string) => {
      if (!color || color === 'original' || !colors[color]) return null;
      ctx.clearRect(0, 0, 1, 1); ctx.fillStyle = colors[color]; ctx.fillRect(0, 0, 1, 1);
      return ctx.getImageData(0, 0, 1, 1).data;
    };
    const hull = rgb(cosmetics.hullColor), sail = rgb(cosmetics.sailColor);
    for (let i = 0; i < bitmap.data.length; i += 4) {
      const d = bitmap.data; if (d[i + 3] < 20) continue;
      const y = Math.floor(i / 4 / canvas.width) / canvas.height;
      const high = Math.max(d[i], d[i + 1], d[i + 2]), low = Math.min(d[i], d[i + 1], d[i + 2]);
      const sailPixel = high > 70 && (high - low < 85 || d[i] > d[i + 1] * 1.25);
      const tint = y < .62 && sailPixel ? sail : y > .62 ? hull : null;
      if (!tint) continue;
      const light = (.2126 * d[i] + .7152 * d[i + 1] + .0722 * d[i + 2]) / 180;
      for (let channel = 0; channel < 3; channel++) d[i + channel] = Math.min(255, tint[channel] * light);
    }
    ctx.putImageData(bitmap, 0, 0);
  } catch { return image; }
  if (recolored.size >= 36) recolored.clear(); recolored.set(key, canvas); return canvas;
}