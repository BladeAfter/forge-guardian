import { DEFAULT_SHIP, SHIP_MODELS, shipMaxHp, type NavalShip } from './naval';

export type NavalPalette = { foam: string; gold: string; ink: string; vitality: string; ember: string; filters: Record<string, string> };
export function navalPalette(element: Element): NavalPalette {
  const css = getComputedStyle(element);
  const color = (token: string) => `hsl(${css.getPropertyValue(token).trim()})`;
  return { foam: color('--ocean-foam'), gold: color('--ocean-gold'), ink: color('--ocean-shadow'), vitality: color('--ocean-vitality'), ember: color('--pirate-red'), filters: Object.fromEntries(['black','inferno','deep','storm','reaper','king'].map(k => [k, css.getPropertyValue(`--naval-filter-${k}`).trim() || 'none'])) };
}
export function drawNavalShip(ctx: CanvasRenderingContext2D, atlas: HTMLImageElement, ship: NavalShip, palette: NavalPalette, time: number, sizeOverride?: number) {
  const index = Math.max(0, SHIP_MODELS.findIndex(m => m.id === ship.model));
  const size = sizeOverride ?? SHIP_MODELS[index].size;
  const cosmetics = ship.cosmetics ?? DEFAULT_SHIP.cosmetics;
  const w = atlas.naturalWidth / 3, h = atlas.naturalHeight / 2;
  ctx.save(); ctx.translate(ship.x, ship.y); ctx.rotate(ship.heading);
  // Waterline stays attached to the hull, including when stationary.
  ctx.fillStyle = palette.ink; ctx.globalAlpha = .24;
  ctx.beginPath(); ctx.ellipse(0, size * .06, size * .19, size * .43, 0, 0, Math.PI * 2); ctx.fill();
  ctx.strokeStyle = palette.foam; ctx.globalAlpha = .5; ctx.lineWidth = 2;
  ctx.beginPath(); ctx.ellipse(0, size * .02, size * .22, size * .46, 0, 0, Math.PI * 2); ctx.stroke(); ctx.globalAlpha = 1;
  if (ship.throttle > 0) {
    ctx.strokeStyle = cosmetics.trail === 'embers' ? palette.ember : cosmetics.trail === 'mist' ? palette.vitality : palette.foam;
    ctx.globalAlpha = .55; ctx.lineWidth = cosmetics.trail === 'mist' ? 8 : 3;
    for (let i = 0; i < 6; i++) {
      const phase = ((time / 700 + i / 6) % 1);
      ctx.globalAlpha = (1 - phase) * .6;
      ctx.beginPath(); ctx.ellipse(0, size * (.4 + phase * .85), size * (.13 + phase * .2), size * .06, 0, 0, Math.PI); ctx.stroke();
    }
    ctx.globalAlpha = 1;
  }
  ctx.filter = palette.filters[ship.skin] || 'none';
  if (atlas.complete && atlas.naturalWidth) { ctx.save();ctx.rotate(Math.PI);ctx.drawImage(atlas,(index%3)*w,Math.floor(index/3)*h,w,h,-size/2,-size/2,size,size);ctx.restore(); }
  ctx.filter = 'none';
  ctx.fillStyle = ship.skin === 'inferno' ? palette.ember : ship.skin === 'king' ? palette.gold : palette.vitality;
  ctx.beginPath(); ctx.moveTo(8,-size*.42); ctx.lineTo(33,-size*.38 + Math.sin(time/350)*3); ctx.lineTo(8,-size*.31); ctx.closePath(); ctx.fill();
  ctx.fillStyle = palette.ink; ctx.font = `bold ${Math.max(9,size*.06)}px sans-serif`; ctx.textAlign = 'center'; ctx.fillText(cosmetics.flag === 'sun' ? '☀' : cosmetics.flag === 'moon' ? '☾' : '☠',18,-size*.35);
  if (cosmetics.prow !== 'none') { ctx.strokeStyle = cosmetics.prow === 'lion' ? palette.gold : palette.foam; ctx.lineWidth = 3; ctx.beginPath(); ctx.moveTo(0,-size*.4); ctx.lineTo(0,-size*.51); ctx.lineTo(cosmetics.prow === 'lion' ? 7 : 0,-size*.45); ctx.stroke(); }
  if (cosmetics.decoration !== 'none') { ctx.strokeStyle = cosmetics.decoration === 'gold' ? palette.gold : palette.foam; ctx.lineWidth = 2; ctx.beginPath(); ctx.arc(0,size*.27,size*.12,0,Math.PI); ctx.stroke(); }
  if (ship.hp < shipMaxHp(ship)*.3) { ctx.fillStyle = palette.ember; ctx.globalAlpha = .6; for(let i=0;i<4;i++) { ctx.beginPath(); ctx.ellipse(Math.sin(i+time/300)*16,size*.15-i*8,5,12,0,0,Math.PI*2); ctx.fill(); } }
  ctx.restore();
  if (ship.name) { ctx.save(); ctx.font='bold 14px sans-serif'; ctx.textAlign='center'; ctx.lineWidth=4; ctx.strokeStyle=palette.ink; ctx.strokeText(`${ship.name} · Nv.${ship.level}`,ship.x,ship.y-size*.58); ctx.fillStyle=palette.foam; ctx.fillText(`${ship.name} · Nv.${ship.level}`,ship.x,ship.y-size*.58); ctx.restore(); }
}