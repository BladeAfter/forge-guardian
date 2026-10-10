import { useLocalizedText } from '../LanguageContext';
import { useRef } from 'react';
import { Compass } from 'lucide-react';
import { OceanControl } from './OceanControl';
import type { SeaPoint } from '../grandLineNavigation';
export function IslandJoystick({ onDirection, disabled }: { onDirection: (point: SeaPoint) => void; disabled: boolean }) {
  const localizeText = useLocalizedText();

  const pointer = useRef<number | null>(null);
  const knob = useRef<HTMLSpanElement>(null);
  const reset = () => { pointer.current = null; onDirection({ x: 0, y: 0 }); if (knob.current) knob.current.style.transform = 'translate(0px, 0px)'; };
  const steer = (event: React.PointerEvent<HTMLButtonElement>) => {
    if (pointer.current !== event.pointerId) return;
    const rect = event.currentTarget.getBoundingClientRect();
    const x = event.clientX - rect.left - rect.width / 2, y = event.clientY - rect.top - rect.height / 2;
    const d = Math.hypot(x, y), radius = rect.width * .29, factor = d > radius ? radius / d : 1;
    onDirection(d < 6 ? { x: 0, y: 0 } : { x: x * factor / radius, y: y * factor / radius });
    if (knob.current) knob.current.style.transform = `translate(${x * factor}px, ${y * factor}px)`;
  };
  return <nav className="ocean-helm" aria-label={localizeText("Direção do pirata")}><OceanControl className="ocean-joystick" aria-label={localizeText("Joystick do pirata")} title={localizeText("Joystick do pirata")} disabled={disabled}
    onPointerDown={e => { if (pointer.current !== null) return; pointer.current = e.pointerId; e.currentTarget.setPointerCapture(e.pointerId); steer(e); }}
    onPointerMove={steer} onPointerUp={reset} onPointerCancel={reset} onLostPointerCapture={reset} onBlur={reset}>
    <span className="ocean-joystick-ring" aria-hidden="true" /><span ref={knob} className="ocean-joystick-knob" aria-hidden="true"><Compass size={24} /></span>
  </OceanControl></nav>;
}