import { useLocalizedText } from '../LanguageContext';
import { useEffect, type MutableRefObject, type RefObject } from 'react';
import { grandLineArt, navalArt, oceanChestImage } from '../gameAssets';
import type { OceanChestState } from '../oceanChests';
import { SEA_CHUNK, SEA_ISLANDS, seaIslandsAround, type SeaPoint } from '../grandLineNavigation';
import { DEFAULT_SHIP, type NavalState, type NavalShip } from '../naval';
import { drawNavalShip, navalPalette } from '../navalRendering';
import { drawOpenWater, islandArtDiameter, islandBitmap, oceanImage } from '../oceanPresentation';
import { qualityMonitor, qualitySettings } from '../gamePerformance';
import { updateApprovedFleet } from '../navalMotion';

type Pose = { position: SeaPoint; camera: SeaPoint; scale: number; heading: number; moving: boolean };
/** Single lightweight bitmap canvas; simulation and official naval actions stay outside. */
export default function IllustratedOcean({ pose, network, chests, wide, canvasRef, drawRef, onSail, onSelect, onChestSelect }: {
  pose: MutableRefObject<Pose>; network: MutableRefObject<NavalState | null>; wide: MutableRefObject<boolean>;
  chests?: MutableRefObject<OceanChestState | null>;
  onChestSelect?: (id: string) => void;
  canvasRef: RefObject<HTMLCanvasElement>; onSail: (point: SeaPoint) => void; onSelect: (id: string) => void;
  drawRef: MutableRefObject<((time: number, delta: number, rawDelta?: number) => void) | null>;
}) {
  const localizeText = useLocalizedText();

  useEffect(() => {
    const canvas = canvasRef.current, ctx = canvas?.getContext('2d', { alpha: false });
    if (!canvas || !ctx) return;
    let last = 0, resolution = 1, width = 1, height = 1;
    const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
    const displayedFleet = new Map<string, NavalShip>();
    const monitor = qualityMonitor();
    let chunk = '', islandTime = 0, visibleIslands: ReturnType<typeof seaIslandsAround> = [];
    const ocean = oceanImage(grandLineArt.ocean), water = oceanImage(grandLineArt.water), fleet = oceanImage(navalArt.fleet);
    const islandTiles: HTMLCanvasElement[] = [];
    const prepare = () => {
      SEA_ISLANDS.forEach((island, templateIndex) => {
        islandTiles[templateIndex] = islandBitmap(ocean, { ...island, id: `home:${templateIndex}`, templateIndex, procedural: false });
      });
    };
    if (ocean.complete && ocean.naturalWidth) prepare(); else ocean.addEventListener('load', prepare);
    const palette = navalPalette(canvas);
    const resize = () => {
      width = Math.max(1, canvas.clientWidth); height = Math.max(1, canvas.clientHeight);
      const pixelsWide = Math.round(width * resolution), pixelsHigh = Math.round(height * resolution);
      if (canvas.width !== pixelsWide) canvas.width = pixelsWide;
      if (canvas.height !== pixelsHigh) canvas.height = pixelsHigh;
    };
    const observer = new ResizeObserver(resize); observer.observe(canvas); resize();
    const render = (time: number, delta: number, rawDelta = delta) => {
      const settings = qualitySettings[monitor.sample(rawDelta)];
      // Spend extra density on phone-sized canvases, not millions of desktop pixels.
      const densityBudget = Math.max(1, Math.sqrt(900000 / (width * height)));
      const desiredResolution = monitor.quality === 'high' ? Math.min(window.devicePixelRatio || 1, 1.5, densityBudget) : settings.resolution;
      if (resolution !== desiredResolution) { resolution = desiredResolution; resize(); }
      const s = pose.current, scale = wide.current ? .32 : Math.min(.8, Math.max(.48, width / 660));
      s.scale = scale; const blend = 1 - Math.exp(-3.84 * delta);
      s.camera.x += (s.position.x - s.camera.x) * blend; s.camera.y += (s.position.y - s.camera.y) * blend;
      const live = network.current;
      updateApprovedFleet(displayedFleet, (live?.others ?? []).filter(ship => Math.abs(ship.x-s.camera.x) < width/scale/2+250 && Math.abs(ship.y-s.camera.y) < height/scale+250), delta);
      if (document.hidden || time - last < (monitor.quality === 'low' ? 32 : 15)) return;
      last = time;
      const w = width, h = height;
      ctx.setTransform(resolution, 0, 0, resolution, 0, 0);
      ctx.fillStyle = palette.vitality; ctx.fillRect(0, 0, w, h);
      ctx.save(); ctx.translate(w / 2, h * .58); ctx.scale(scale, scale); ctx.translate(-s.camera.x, -s.camera.y);
      if (water.complete && water.naturalWidth) {
        const drift = reducedMotion.matches ? 0 : Math.sin(time / 4000) * 2;
        ctx.save(); ctx.translate(drift, drift / 2);
        drawOpenWater(ctx, water, { x: s.camera.x-drift, y: s.camera.y-drift/2 }, w / scale, h / scale); ctx.restore();
      }
      const nextChunk = `${Math.floor(s.position.x / SEA_CHUNK)}:${Math.floor(s.position.y / SEA_CHUNK)}`;
      if (chunk !== nextChunk || time - islandTime > 250) { chunk = nextChunk; islandTime = time; visibleIslands = seaIslandsAround(s.position, 1); }
      for (const island of visibleIslands) {
        const tile = islandTiles[island.templateIndex];
        const diameter = islandArtDiameter(island.radius);
        if (!tile || Math.abs(island.center.x - s.camera.x) > w / scale + diameter || Math.abs(island.center.y - s.camera.y) > h / scale + diameter) continue;
        ctx.drawImage(tile, island.center.x - diameter / 2, island.center.y - diameter / 2, diameter, diameter);
      }
      for (const chest of chests?.current?.chests ?? []) {
        if (Date.parse(chest.expiresAt)<=Date.now() || Math.abs(chest.x-s.camera.x)>w/scale || Math.abs(chest.y-s.camera.y)>h/scale) continue;
        const image=oceanImage(oceanChestImage(chest.rarity));
        ctx.save(); ctx.translate(chest.x,chest.y); ctx.strokeStyle=palette.gold; ctx.lineWidth=2; ctx.globalAlpha=.55+Math.sin(time/500)*.15;
        ctx.beginPath();ctx.ellipse(0,20,42,18,0,0,Math.PI*2);ctx.stroke();ctx.globalAlpha=1;
        const bob = reducedMotion.matches ? 0 : Math.sin(time / 900 + chest.x) * 2;
        if(image.complete && image.naturalWidth)ctx.drawImage(image,-40,-42+bob,80,80);
        ctx.restore();
      }
      const animationTime = reducedMotion.matches ? 0 : time;
      for (const ship of displayedFleet.values()) {
        drawNavalShip(ctx, fleet, ship, palette, animationTime, undefined, settings.wake);
      }
      drawNavalShip(ctx, fleet, { ...(live?.ship ?? DEFAULT_SHIP), x: s.position.x, y: s.position.y, heading: s.heading, throttle: s.moving ? 1 : 0 }, palette, animationTime, 170, settings.wake);
      canvas.dataset.quality = monitor.quality; canvas.dataset.resolution = String(resolution);
      ctx.restore();
    };
    drawRef.current = render;
    return () => { drawRef.current = null; observer.disconnect(); ocean.removeEventListener('load', prepare); islandTiles.length = 0; };
  }, [canvasRef, network, chests, pose, wide, drawRef]);
  return <canvas ref={canvasRef} role="img" aria-label={localizeText("Oceano da Grand Line")} data-renderer="illustrated-2d" onClick={event => {
    const canvas = event.currentTarget, rect = canvas.getBoundingClientRect(), s = pose.current;
    const point = { x: s.camera.x + (event.clientX - rect.left - rect.width / 2) / s.scale, y: s.camera.y + (event.clientY - rect.top - rect.height * .58) / s.scale };
    const chest = chests?.current?.chests.find(c => Date.parse(c.expiresAt)>Date.now() && Math.hypot(c.x-point.x,c.y-point.y)<60);
    if(chest){onChestSelect?.(chest.id);return;}
    const other = network.current?.others.find(ship => Math.hypot(ship.x - point.x, ship.y - point.y) < 100);
    if (other) onSelect(other.user_id); else onSail(point);
  }} />;
}