import { SEA_SIZE, type SeaIsland } from './grandLineNavigation';

const bitmapCache = new WeakMap<HTMLImageElement, Map<number, HTMLCanvasElement>>();
const imageCache = new Map<string, HTMLImageElement>();
export function oceanImage(url: string) {
  const cached = imageCache.get(url);
  if (cached) return cached;
  const image = new Image(); image.src = url; imageCache.set(url, image); return image;
}

/** Cosmetic bounds only; official collision radii and dock positions do not change. */
export const islandArtDiameter = (radius: number) => radius * 2.2;

export function islandBitmap(atlas: HTMLImageElement, template: SeaIsland): HTMLCanvasElement {
  let cache = bitmapCache.get(atlas);
  if (!cache) { cache = new Map(); bitmapCache.set(atlas, cache); }
  const cached = cache.get(template.templateIndex);
  if (cached) return cached;
  const tile = document.createElement('canvas');
  tile.width = 512; tile.height = 512;
  const ctx = tile.getContext('2d');
  if (!ctx) return tile;
  const cropRadius = template.radius * 1.35;
  ctx.drawImage(atlas,
    (template.center.x - cropRadius) / SEA_SIZE.width * atlas.naturalWidth,
    (template.center.y - cropRadius) / SEA_SIZE.height * atlas.naturalHeight,
    cropRadius * 2 / SEA_SIZE.width * atlas.naturalWidth,
    cropRadius * 2 / SEA_SIZE.height * atlas.naturalHeight,
    0, 0, 512, 512);
  // Alpha-only feathering, not a visible colored decoration.
  ctx.globalCompositeOperation = 'destination-in';
  const mask = ctx.createRadialGradient(256, 256, 178, 256, 256, 256);
  mask.addColorStop(0, 'rgba(0,0,0,1)');
  mask.addColorStop(1, 'rgba(0,0,0,0)');
  ctx.fillStyle = mask; ctx.fillRect(0, 0, 512, 512);
  cache.set(template.templateIndex, tile);
  return tile;
}

/** Mirrored neighbors share exactly the same boundary. */
export function drawOpenWater(ctx: CanvasRenderingContext2D, image: HTMLImageElement, camera: { x: number; y: number }, width: number, height: number) {
  const size = 900;
  const left = Math.floor((camera.x - width) / size), top = Math.floor((camera.y - height) / size);
  for (let x = left; x <= Math.ceil((camera.x + width) / size); x++) {
    for (let y = top; y <= Math.ceil((camera.y + height) / size); y++) {
      const flipX = Math.abs(x % 2) === 1, flipY = Math.abs(y % 2) === 1;
      ctx.save(); ctx.translate(x * size + (flipX ? size : 0), y * size + (flipY ? size : 0));
      ctx.scale(flipX ? -1 : 1, flipY ? -1 : 1);
      ctx.drawImage(image, 0, 0, size + .5, size + .5); ctx.restore();
    }
  }
}