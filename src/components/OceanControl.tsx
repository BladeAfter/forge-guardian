import type { ButtonHTMLAttributes } from 'react';

/** Compact semantic control shared by the ocean HUD and sailing controls. */
export function OceanControl({ className = '', ...props }: ButtonHTMLAttributes<HTMLButtonElement>) {
  return <button type="button" className={`ocean-control ${className}`} {...props} />;
}