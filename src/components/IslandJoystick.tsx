import { useLocalizedText } from '../LanguageContext';
import { useEffect, useRef } from 'react';
import { Compass } from 'lucide-react';
import { OceanControl } from './OceanControl';
import type { SeaPoint } from '../grandLineNavigation';
export function IslandJoystick({ onDirection, disabled }: { onDirection: (point: SeaPoint) => void; disabled: boolean }) {
  const localizeText = useLocalizedText();

  const pointer = useRef<number | null>(null);
  const knob = useRef<HTMLSpanElement>(null);
  const direction = useRef(onDirection);
  direction.current = onDirection;
  useEffect(() => {
    const clear = () => { pointer.current = null; direction.current({ x: 0, y: 0 }); if (knob.current) knob.current.style.transform = 'translate(0px, 0px)'; };
    const visibility = () => { if (document.hidden) clear(); };
    window.addEventListener('blur', clear); document.addEventListener('visibilitychange', visibility);
    return () => { clear(); window.removeEventListener('blur', clear); document.removeEventListener('visibilitychange', visibility); };
  }, []);
  useEffect(() => { if (disabled) { pointer.current = null; direction.current({ x: 0, y: 0 }); if (knob.current) knob.current.style.transform = 'translate(0px, 0px)'; } }, [disabled]);
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
    onPointerDown={e => { if (pointer.current !== null) return; e.preventDefault(); pointer.current = e.pointerId; try { e.currentTarget.setPointerCapture(e.pointerId); } catch { /* Older WebViews. */ } steer(e); }}
    onPointerMove={steer} onPointerUp={e => { if (pointer.current === e.pointerId) reset(); }} onPointerCancel={e => { if (pointer.current === e.pointerId) reset(); }} onLostPointerCapture={e => { if (pointer.current === e.pointerId) reset(); }} onBlur={reset}>
    <span className="ocean-joystick-ring" aria-hidden="true" /><span ref={knob} className="ocean-joystick-knob" aria-hidden="true"><Compass size={24} /></span>
  </OceanControl></nav>;
}