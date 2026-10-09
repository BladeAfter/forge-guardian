import { describe, expect, it } from 'vitest';
import { approachApprovedPose } from './navalMotion';

describe('approved ship motion', () => {
  it('continues moving between updates without passing the approved location', () => {
    const approved = { x: 110, y: 40, heading: Math.PI / 2 };
    const first = approachApprovedPose({ x: 10, y: 40 }, 0, approved, .016);
    const second = approachApprovedPose(first.position, first.heading, approved, .016);
    expect(first.position.x).toBeGreaterThan(10);
    expect(second.position.x).toBeGreaterThan(first.position.x);
    expect(second.position.x).toBeLessThan(110);
    expect(second.position.y).toBe(40);
  });
  it('does not invent movement when the approved ship is stationary', () => {
    expect(approachApprovedPose({ x: 10, y: 40 }, 0, { x: 10, y: 40, heading: 0 }, .05).position).toEqual({ x: 10, y: 40 });
  });
});