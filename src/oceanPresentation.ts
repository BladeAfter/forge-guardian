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

const waterCache = new WeakMap<HTMLImageElement, HTMLCanvasElement>();
const patternCache = new WeakMap<CanvasRenderingContext2D, WeakMap<HTMLImageElement, CanvasPattern>>();
/** Decode the water JPEG once into a small canvas so mobile webviews never re-decode it per frame. */
function waterTile(image: HTMLImageElement) {
  let tile = waterCache.get(image);
  if (tile) return tile;
  tile = document.createElement('canvas'); tile.width = 512; tile.height = 512;
  tile.getContext('2d', { alpha: false })?.drawImage(image, 0, 0, 512, 512);
  waterCache.set(image, tile); return tile;
}

/** Mirrored neighbors share exactly the same boundary. Width/height are the full visible span. */
export function drawOpenWater(ctx: CanvasRenderingContext2D, source: HTMLImageElement, camera: { x: number; y: number }, width: number, height: number) {
  // Match the native detail scale of the original illustrated sea crop.
  const size = 300, image = waterTile(source);
  let patterns = patternCache.get(ctx);
  if (!patterns) { patterns = new WeakMap(); patternCache.set(ctx, patterns); }
  let pattern = patterns.get(source);
  if (!pattern && typeof ctx.createPattern === 'function') {
    const mirrored = document.createElement('canvas'); mirrored.width = size * 2; mirrored.height = size * 2;
    const painter = mirrored.getContext('2d', { alpha: false });
    if (painter) {
      for (let x = 0; x < 2; x++) for (let y = 0; y < 2; y++) {
        painter.save(); painter.translate(x ? size * 2 : 0, y ? size * 2 : 0);
        painter.scale(x ? -1 : 1, y ? -1 : 1); painter.drawImage(image, 0, 0, size, size); painter.restore();
      }
      pattern = ctx.createPattern(mirrored, 'repeat') ?? undefined;
      if (pattern) patterns.set(source, pattern);
    }
  }
  if (pattern) {
    ctx.fillStyle = pattern;
    ctx.fillRect(camera.x - width * .55, camera.y - height * .65, width * 1.1, height * 1.15);
    return;
  }
  const left = Math.floor((camera.x - width * .55) / size), top = Math.floor((camera.y - height * .65) / size);
  for (let x = left; x <= Math.floor((camera.x + width * .55) / size); x++) {
    for (let y = top; y <= Math.floor((camera.y + height * .5) / size); y++) {
      const flipX = Math.abs(x % 2) === 1, flipY = Math.abs(y % 2) === 1;
      ctx.save(); ctx.translate(x * size + (flipX ? size : 0), y * size + (flipY ? size : 0));
      ctx.scale(flipX ? -1 : 1, flipY ? -1 : 1);
      ctx.drawImage(image, 0, 0, size + .5, size + .5); ctx.restore();
    }
  }
}