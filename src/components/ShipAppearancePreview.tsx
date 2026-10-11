import { useEffect, useRef } from 'react';
import { navalArt } from '../gameAssets';
import { DEFAULT_SHIP, type ShipCosmetics } from '../naval';
import { drawNavalShip, fleetAppearanceUrl, navalPalette } from '../navalRendering';
import { useLocalizedText } from '../LanguageContext';

export function ShipAppearancePreview({ classId, cosmetics }: { classId: string; cosmetics: ShipCosmetics }) {
  const ref = useRef<HTMLCanvasElement>(null);
  const text = useLocalizedText();
  useEffect(() => {
    const el = ref.current, ctx = el?.getContext('2d'); if (!el || !ctx) return;
    let alive = true;
    const ship = { ...DEFAULT_SHIP, class_id: classId, cosmetics, x: 180, y: 150, heading: -Math.PI / 2, throttle: 1 };
    const image = new Image(); image.src = fleetAppearanceUrl(ship) ?? navalArt.fleet;
    void image.decode().then(() => {
      if (!alive) return;
      ctx.clearRect(0, 0, 360, 300);
      drawNavalShip(ctx, image, ship, navalPalette(el), 100, 275);
    }).catch(() => {});
    return () => { alive = false; };
  }, [classId, cosmetics]);
  return <canvas ref={ref} width={360} height={300} className="ship-fleet__appearance-preview" aria-label={text('Prévia do navio personalizado')} />;
}