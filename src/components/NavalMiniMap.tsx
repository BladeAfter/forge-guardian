import { useLocalizedText } from '../LanguageContext';
import { useEffect, useRef, useState, type MutableRefObject } from 'react';
import { grandLineArt } from '../gameAssets';
import { SEA_ISLANDS, seaIslandsAround, type SeaPoint } from '../grandLineNavigation';
import { type NavalState } from '../naval';
import { islandArtDiameter, islandBitmap } from '../oceanPresentation';
import { navalPalette } from '../navalRendering';
import { OceanControl } from './OceanControl';
import './NavalMiniMap.css';

/** Read-only local chart: no hidden treasure, invented players or navigation commands. */
export default function NavalMiniMap({ pose, network }: {
  pose: MutableRefObject<{ position: SeaPoint; heading: number }>;
  network: MutableRefObject<NavalState | null>;
}) {
  const localizeText = useLocalizedText();

  const ref = useRef<HTMLCanvasElement>(null);
  const [expanded, setExpanded] = useState(false);
  useEffect(() => {
    const canvas = ref.current, ctx = canvas?.getContext('2d');
    if (!canvas || !ctx) return;
    const palette = navalPalette(canvas);
    const atlas = new Image(), water = new Image();
    const islands: HTMLCanvasElement[] = [];
    atlas.onload = () => SEA_ISLANDS.forEach((island, templateIndex) => {
      islands[templateIndex] = islandBitmap(atlas, { ...island, id: `home:${templateIndex}`, templateIndex, procedural: false });
    });
    atlas.src = grandLineArt.ocean; water.src = grandLineArt.water;
    const draw = () => {
      if (document.hidden) return;
      const { position, heading } = pose.current;
      const range = expanded ? 3200 : 1800, factor = 104 / range;
      ctx.clearRect(0, 0, 256, 256);
      ctx.save(); ctx.beginPath(); ctx.arc(128, 128, 110, 0, Math.PI * 2); ctx.clip();
      ctx.fillStyle = palette.ink; ctx.fillRect(0, 0, 256, 256);
      if (water.complete && water.naturalWidth) {
        ctx.globalAlpha = .35; ctx.drawImage(water, 18, 18, 220, 220); ctx.globalAlpha = 1;
      }
      // North-up local projection follows the same approved pose as the main scene.
      ctx.save(); ctx.translate(128, 128); ctx.scale(factor, factor); ctx.translate(-position.x, -position.y);
      for (const island of seaIslandsAround(position, 1)) {
        const tile = islands[island.templateIndex], diameter = islandArtDiameter(island.radius);
        if (tile) ctx.drawImage(tile, island.center.x - diameter / 2, island.center.y - diameter / 2, diameter, diameter);
        if (Math.hypot(island.dock.x - position.x, island.dock.y - position.y) < range) {
          ctx.fillStyle = palette.gold; ctx.beginPath(); ctx.arc(island.dock.x, island.dock.y, 2.4 / factor, 0, Math.PI * 2); ctx.fill();
        }
      }
      ctx.restore();
      ctx.strokeStyle = palette.foam; ctx.globalAlpha = .12; ctx.lineWidth = 1;
      for (const radius of [36, 72, 108]) { ctx.beginPath(); ctx.arc(128, 128, radius, 0, Math.PI * 2); ctx.stroke(); }
      ctx.beginPath(); ctx.moveTo(18,128);ctx.lineTo(238,128);ctx.moveTo(128,18);ctx.lineTo(128,238);ctx.stroke();ctx.globalAlpha = 1;
      for (const ship of network.current?.others ?? []) {
        const x = 128 + (ship.x - position.x) * factor, y = 128 + (ship.y - position.y) * factor;
        ctx.fillStyle = palette.vitality; ctx.strokeStyle = palette.ink; ctx.lineWidth = 2;
        ctx.beginPath();ctx.arc(x,y,4,0,Math.PI*2);ctx.fill();ctx.stroke();
      }
      ctx.translate(128,128);ctx.rotate(heading);
      ctx.fillStyle = palette.gold;ctx.strokeStyle = palette.ink;ctx.lineWidth = 2;
      ctx.beginPath();ctx.moveTo(0,-12);ctx.lineTo(7,9);ctx.lineTo(0,5);ctx.lineTo(-7,9);ctx.closePath();ctx.fill();ctx.stroke();ctx.restore();
      ctx.strokeStyle = palette.gold; ctx.lineWidth = 2;ctx.beginPath();ctx.arc(128,128,113,0,Math.PI*2);ctx.stroke();
      ctx.strokeStyle = palette.foam;ctx.globalAlpha=.55;ctx.lineWidth=1;
      for (let i=0;i<48;i++) {
        const a=i*Math.PI/24, inner=i%4===0?115:119;
        ctx.beginPath();ctx.moveTo(128+Math.sin(a)*inner,128-Math.cos(a)*inner);ctx.lineTo(128+Math.sin(a)*123,128-Math.cos(a)*123);ctx.stroke();
      }
      ctx.globalAlpha=1;
      canvas.dataset.heading = String(heading); canvas.dataset.range = String(range);
      canvas.dataset.players = String(network.current?.others.length ?? 0);
    };
    draw();const timer=window.setInterval(draw,200);
    return () => { window.clearInterval(timer);atlas.onload=null; };
  }, [pose, network, expanded]);
  return <aside className={`naval-minimap ${expanded ? 'naval-minimap-expanded' : ''}`} aria-label={localizeText("Carta náutica local")}>
    <OceanControl className="naval-minimap-toggle" onClick={() => setExpanded(value=>!value)} aria-label={expanded?localizeText("Reduzir carta náutica"):localizeText("Ampliar carta náutica")} aria-expanded={expanded} title={expanded?localizeText("Reduzir carta náutica"):localizeText("Ampliar carta náutica")}>
      <canvas ref={ref} width={256} height={256} role="img" aria-label={localizeText("Mapa das ilhas e navios próximos")} />
      <span className="naval-map-n">N</span><span className="naval-map-e">L</span><span className="naval-map-s">S</span><span className="naval-map-w">O</span>
    </OceanControl>
    <span className="naval-map-caption">{localizeText("GRAND LINE")}</span>
  </aside>;
}