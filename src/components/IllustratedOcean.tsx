import { useLocalizedText } from '../LanguageContext';
import { useEffect, type MutableRefObject, type RefObject } from 'react';
import { grandLineArt, navalArt } from '../gameAssets';
import { SEA_CHUNK, SEA_ISLANDS, seaIslandsAround, type SeaPoint } from '../grandLineNavigation';
import { DEFAULT_SHIP, type NavalState } from '../naval';
import { drawNavalShip, navalPalette } from '../navalRendering';
import { drawOpenWater, islandArtDiameter, islandBitmap } from '../oceanPresentation';
import { qualityMonitor, qualitySettings } from '../gamePerformance';

type Pose = { position: SeaPoint; camera: SeaPoint; scale: number; heading: number; moving: boolean };
/** Single lightweight bitmap canvas; simulation and official naval actions stay outside. */
export default function IllustratedOcean({ pose, network, wide, canvasRef, drawRef, onSail, onSelect }: {
  pose: MutableRefObject<Pose>; network: MutableRefObject<NavalState | null>; wide: MutableRefObject<boolean>;
  canvasRef: RefObject<HTMLCanvasElement>; onSail: (point: SeaPoint) => void; onSelect: (id: string) => void;
  drawRef: MutableRefObject<((time: number, delta: number) => void) | null>;
}) {
  const localizeText = useLocalizedText();

  useEffect(() => {
    const canvas = canvasRef.current, ctx = canvas?.getContext('2d', { alpha: false });
    if (!canvas || !ctx) return;
    let last = 0, resolution = 1;
    const monitor = qualityMonitor();
    let chunk = '', visibleIslands: ReturnType<typeof seaIslandsAround> = [];
    const ocean = new Image(), water = new Image(), fleet = new Image();
    const islandTiles: HTMLCanvasElement[] = [];
    ocean.onload = () => {
      SEA_ISLANDS.forEach((island, templateIndex) => {
        islandTiles[templateIndex] = islandBitmap(ocean, { ...island, id: `home:${templateIndex}`, templateIndex, procedural: false });
      });
    };
    ocean.src = grandLineArt.ocean; water.src = grandLineArt.water; fleet.src = navalArt.fleet;
    const palette = navalPalette(canvas);
    const resize = () => {
      const width = Math.max(1, Math.round(canvas.clientWidth * resolution)), height = Math.max(1, Math.round(canvas.clientHeight * resolution));
      if (canvas.width !== width) canvas.width = width;
      if (canvas.height !== height) canvas.height = height;
    };
    const observer = new ResizeObserver(resize); observer.observe(canvas); resize();
    const render = (time: number, delta: number) => {
      const settings = qualitySettings[monitor.sample(delta)];
      if (resolution !== settings.resolution) { resolution = settings.resolution; resize(); }
      const s = pose.current, scale = wide.current ? .32 : Math.min(.8, Math.max(.48, canvas.clientWidth / 660));
      s.scale = scale; const blend = 1 - Math.exp(-3.84 * delta);
      s.camera.x += (s.position.x - s.camera.x) * blend; s.camera.y += (s.position.y - s.camera.y) * blend;
      if (document.hidden || time - last < (monitor.quality === 'low' ? 33 : 16)) return;
      last = time;
      const w = canvas.clientWidth, h = canvas.clientHeight;
      ctx.setTransform(resolution, 0, 0, resolution, 0, 0);
      ctx.fillStyle = palette.vitality; ctx.fillRect(0, 0, w, h);
      ctx.save(); ctx.translate(w / 2, h * .58); ctx.scale(scale, scale); ctx.translate(-s.camera.x, -s.camera.y);
      if (water.complete && water.naturalWidth) drawOpenWater(ctx, water, s.camera, w / scale, h / scale);
      const nextChunk = `${Math.floor(s.position.x / SEA_CHUNK)}:${Math.floor(s.position.y / SEA_CHUNK)}`;
      if (chunk !== nextChunk) { chunk = nextChunk; visibleIslands = seaIslandsAround(s.position, 1); }
      for (const island of visibleIslands) {
        const tile = islandTiles[island.templateIndex];
        const diameter = islandArtDiameter(island.radius);
        if (!tile || Math.abs(island.center.x - s.camera.x) > w / scale + diameter || Math.abs(island.center.y - s.camera.y) > h / scale + diameter) continue;
        ctx.drawImage(tile, island.center.x - diameter / 2, island.center.y - diameter / 2, diameter, diameter);
      }
      const live = network.current;
      for (const ship of live?.others ?? []) {
        if (Math.abs(ship.x - s.camera.x) > w / scale / 2 + 250 || Math.abs(ship.y - s.camera.y) > h / scale + 250) continue;
        drawNavalShip(ctx, fleet, ship, palette, time, undefined, settings.wake);
      }
      drawNavalShip(ctx, fleet, { ...(live?.ship ?? DEFAULT_SHIP), x: s.position.x, y: s.position.y, heading: s.heading, throttle: s.moving ? 1 : 0 }, palette, time, 170, settings.wake);
      ctx.restore();
    };
    drawRef.current = render;
    return () => { drawRef.current = null; observer.disconnect(); ocean.onload = null; islandTiles.length = 0; };
  }, [canvasRef, network, pose, wide, drawRef]);
  return <canvas ref={canvasRef} role="img" aria-label={localizeText("Oceano da Grand Line")} data-renderer="illustrated-2d" onClick={event => {
    const canvas = event.currentTarget, rect = canvas.getBoundingClientRect(), s = pose.current;
    const point = { x: s.camera.x + (event.clientX - rect.left - rect.width / 2) / s.scale, y: s.camera.y + (event.clientY - rect.top - rect.height * .58) / s.scale };
    const other = network.current?.others.find(ship => Math.hypot(ship.x - point.x, ship.y - point.y) < 100);
    if (other) onSelect(other.user_id); else onSail(point);
  }} />;
}