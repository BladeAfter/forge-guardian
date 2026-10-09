import { useEffect, type MutableRefObject, type RefObject } from 'react';
import { grandLineArt, navalArt } from '../gameAssets';
import { SEA_CHUNK, SEA_SIZE, seaIslandsAround, type SeaPoint } from '../grandLineNavigation';
import { DEFAULT_SHIP, type NavalState } from '../naval';
import { drawNavalShip, navalPalette } from '../navalRendering';

type Pose = { position: SeaPoint; camera: SeaPoint; scale: number; heading: number; moving: boolean };
/** Single lightweight bitmap canvas; simulation and official naval actions stay outside. */
export default function IllustratedOcean({ pose, network, wide, canvasRef, onSail, onSelect }: {
  pose: MutableRefObject<Pose>; network: MutableRefObject<NavalState | null>; wide: MutableRefObject<boolean>;
  canvasRef: RefObject<HTMLCanvasElement>; onSail: (point: SeaPoint) => void; onSelect: (id: string) => void;
}) {
  useEffect(() => {
    const canvas = canvasRef.current, ctx = canvas?.getContext('2d', { alpha: false });
    if (!canvas || !ctx) return;
    let frame = 0, last = 0;
    const ocean = new Image(), fleet = new Image();
    ocean.src = grandLineArt.ocean; fleet.src = navalArt.fleet;
    const palette = navalPalette(canvas);
    const resize = () => { canvas.width = canvas.clientWidth; canvas.height = canvas.clientHeight; };
    const observer = new ResizeObserver(resize); observer.observe(canvas); resize();
    const render = (time: number) => {
      frame = requestAnimationFrame(render);
      if (document.hidden || time - last < 33) return;
      last = time;
      const s = pose.current, scale = wide.current ? .32 : Math.min(.8, Math.max(.48, canvas.width / 660));
      s.scale = scale; s.camera.x += (s.position.x - s.camera.x) * .12; s.camera.y += (s.position.y - s.camera.y) * .12;
      const w = canvas.width, h = canvas.height;
      ctx.fillStyle = palette.vitality; ctx.fillRect(0, 0, w, h);
      ctx.save(); ctx.translate(w / 2, h * .58); ctx.scale(scale, scale); ctx.translate(-s.camera.x, -s.camera.y);
      if (ocean.complete && ocean.naturalWidth) {
        // Water repeats independently of the original archipelago: there is no map edge.
        const size = 500, minX = Math.floor((s.camera.x - w / scale) / size), minY = Math.floor((s.camera.y - h / scale) / size);
        for (let x = minX; x < minX + Math.ceil(w / scale * 2 / size) + 1; x++) for (let y = minY; y < minY + Math.ceil(h / scale * 2 / size) + 1; y++) {
          ctx.drawImage(ocean, ocean.naturalWidth * .49, 0, ocean.naturalWidth * .09, ocean.naturalHeight * .1, x * size, y * size, size + 1, size + 1);
        }
        ctx.drawImage(ocean, 0, 0, SEA_SIZE.width, SEA_SIZE.height);
        for (const island of seaIslandsAround(s.position, 1).filter(i => i.procedural)) {
          const crop = [[0, 0], [.32, .25], [.64, 0], [.61, .5], [0, .5]][island.templateIndex];
          const diameter = island.radius * 2.5;
          ctx.save(); ctx.beginPath(); ctx.ellipse(island.center.x, island.center.y, diameter / 2, diameter / 2, 0, 0, Math.PI * 2); ctx.clip();
          ctx.drawImage(ocean, crop[0] * ocean.naturalWidth, crop[1] * ocean.naturalHeight, ocean.naturalWidth * .38, ocean.naturalHeight * .48, island.center.x - diameter / 2, island.center.y - diameter / 2, diameter, diameter); ctx.restore();
        }
      }
      const live = network.current;
      for (const ship of live?.others ?? []) drawNavalShip(ctx, fleet, ship, palette, time);
      drawNavalShip(ctx, fleet, { ...(live?.ship ?? DEFAULT_SHIP), x: s.position.x, y: s.position.y, heading: s.heading, throttle: s.moving ? 1 : 0 }, palette, time, 170);
      ctx.restore();
      canvas.dataset.chunk = `${Math.floor(s.position.x / SEA_CHUNK)}:${Math.floor(s.position.y / SEA_CHUNK)}`;
    };
    frame = requestAnimationFrame(render);
    return () => { cancelAnimationFrame(frame); observer.disconnect(); };
  }, [canvasRef, network, pose, wide]);
  return <canvas ref={canvasRef} role="img" aria-label="Oceano da Grand Line" data-renderer="illustrated-2d" onClick={event => {
    const canvas = event.currentTarget, rect = canvas.getBoundingClientRect(), s = pose.current;
    const point = { x: s.camera.x + (event.clientX - rect.left - rect.width / 2) / s.scale, y: s.camera.y + (event.clientY - rect.top - rect.height * .58) / s.scale };
    const other = network.current?.others.find(ship => Math.hypot(ship.x - point.x, ship.y - point.y) < 100);
    if (other) onSelect(other.user_id); else onSail(point);
  }} />;
}