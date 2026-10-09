import { useEffect, useMemo, useRef, type MutableRefObject } from 'react';
import { useFrame } from '@react-three/fiber';
import { CapsuleCollider, RigidBody, useBeforePhysicsStep, useRapier, type RapierRigidBody } from '@react-three/rapier';
import * as THREE from 'three';
import { cameraRelativeMotion, HARBOR, ISLAND_3D, type HarborState, type IslandInput, type IslandMotion, type IslandTelemetry } from '../../island3dWorld';

type Props = { harbor: MutableRefObject<HarborState>; input: MutableRefObject<IslandInput>; onTelemetry: (value: IslandTelemetry) => void; onReturn: () => void; children: (motion: MutableRefObject<IslandMotion>, speed: MutableRefObject<number>) => React.ReactNode };
export function IslandPlayer({ harbor, input, onTelemetry, onReturn, children }: Props) {
  const body = useRef<RapierRigidBody>(null), model = useRef<THREE.Group>(null);
  const motion = useRef<IslandMotion>('walk'), speed = useRef(0);
  const { world, rapier } = useRapier();
  const controller = useMemo(() => {
    const c = world.createCharacterController(.01);
    c.enableAutostep(.45, .3, true); c.enableSnapToGround(.3); c.setMaxSlopeClimbAngle(Math.PI / 3); c.setMinSlopeSlideAngle(Math.PI / 3);
    return c;
  }, [world]);
  useEffect(() => () => { world.removeCharacterController(controller); }, [world, controller]);
  const state = useRef({ phase: 'approaching' as IslandTelemetry['phase'], waypoint: 0, vy: 0, grounded: true, heading: Math.PI, action: 0, actionKind: 'idle' as IslandMotion, jumpHeld: false, returned: false, cameraStarted: false, lastHud: 0 });
  const cameraTarget = useMemo(() => new THREE.Vector3(), []);
  const cameraLook = useMemo(() => new THREE.Vector3(), []);
  const cameraDirection = useMemo(() => new THREE.Vector3(), []);

  useBeforePhysicsStep(() => {
    const b = body.current;
    if (!b || state.current.returned) return;
    const dt = 1 / 60, s = state.current, i = input.current, p = b.translation();
    const h = harbor.current;
    if (s.phase === 'approaching' || s.phase === 'deploying') {
      b.setNextKinematicTranslation({ x: h.x + ISLAND_3D.spawn.x - HARBOR.ship.x, y: h.y + 2.625 + .035, z: h.z + ISLAND_3D.spawn.z - HARBOR.ship.z });
      motion.current = 'idle'; speed.current = 0;
      s.phase = h.ready ? 'landing' : h.deployment > 0 ? 'deploying' : 'approaching';
      return;
    }
    if (i.boarding && s.phase !== 'boarding') { s.phase = 'boarding'; s.waypoint = 0; }
    let dx = 0, dz = 0, targetSpeed = 0;
    if (s.phase === 'landing' || s.phase === 'boarding') {
      const route = s.phase === 'landing' ? [{ x: 4.1, z: HARBOR.gangway.z }, ISLAND_3D.gangway, ISLAND_3D.shore] : [ISLAND_3D.gangway, { x: 4.1, z: HARBOR.gangway.z }, ISLAND_3D.spawn];
      const goal = route[s.waypoint] ?? route[route.length - 1];
      const x = goal.x - p.x, z = goal.z - p.z, d = Math.hypot(x, z);
      if (d < .35) {
        if (s.waypoint < route.length - 1) s.waypoint++;
        else if (s.phase === 'landing') s.phase = 'exploring';
        else { s.returned = true; onReturn(); return; }
      } else { dx = x / d; dz = z / d; targetSpeed = 2.2; }
    } else if (!i.blocked) {
      const vector = cameraRelativeMotion(i.x, -i.y, i.yaw);
      dx = vector.x; dz = vector.z;
      const magnitude = Math.min(1, Math.hypot(i.x, i.y));
      targetSpeed = magnitude * (i.sprint ? 6.5 : magnitude < .7 ? 2.3 : 4.1);
    }
    const swimming = p.y < .5 && Math.hypot(p.x / 1.07, p.z) > 41 && Math.abs(p.x) > 2;
    if (swimming) targetSpeed = Math.min(targetSpeed, 2.3);
    // Official encounter responses can request an attack while the encounter HUD locks movement.
    if (i.attack && s.action <= 0) { s.action = .75; s.actionKind = 'attack'; }
    if (i.interact && s.action <= 0) { s.action = .8; s.actionKind = 'interact'; }
    if (i.dodge && !i.blocked && s.action <= 0 && s.grounded) { s.action = .55; s.actionKind = 'dodge'; }
    i.attack = false; i.interact = false; i.dodge = false;
    if (s.action > 0) {
      s.action -= dt;
      if (s.actionKind === 'dodge') { dx = Math.sin(s.heading); dz = Math.cos(s.heading); targetSpeed = 7; }
      else targetSpeed = 0;
    }
    speed.current += (targetSpeed - speed.current) * (1 - Math.exp(-16 * dt));
    if (targetSpeed === 0 && speed.current < .08) speed.current = 0;
    if (i.jump && !s.jumpHeld && s.grounded && !i.blocked && !swimming) { s.vy = 6.5; s.grounded = false; }
    s.jumpHeld = i.jump;
    s.vy = swimming ? Math.max(-1, Math.min(1, (.18 - p.y) * 5)) : Math.max(-18, s.vy - 19 * dt);
    const collider = b.collider(0);
    if (!collider) return;
    const bounds = Math.hypot(p.x, p.z) > 55;
    if (bounds && s.phase === 'exploring') { dx = -p.x / Math.hypot(p.x, p.z); dz = -p.z / Math.hypot(p.x, p.z); speed.current = 2; }
    controller.computeColliderMovement(collider, { x: dx * speed.current * dt, y: s.vy * dt, z: dz * speed.current * dt }, undefined, undefined, c => c.parent()?.handle !== b.handle);
    const movement = controller.computedMovement();
    s.grounded = controller.computedGrounded();
    if (s.grounded && s.vy < 0) s.vy = 0;
    b.setNextKinematicTranslation({ x: p.x + movement.x, y: p.y + movement.y, z: p.z + movement.z });
    if (Math.hypot(movement.x, movement.z) > .001) {
      const target = Math.atan2(dx, dz);
      s.heading += Math.atan2(Math.sin(target - s.heading), Math.cos(target - s.heading)) * (1 - Math.exp(-14 * dt));
    }
    const actualSpeed = Math.hypot(movement.x, movement.z) / dt;
    motion.current = s.action > 0 ? s.actionKind : swimming ? 'swim' : !s.grounded ? s.vy > 0 ? 'jump' : 'fall' : actualSpeed < .1 ? 'idle' : movement.y > .018 ? 'climb' : movement.y < -.018 ? 'descend' : actualSpeed > 5 ? 'sprint' : actualSpeed > 2.6 ? 'run' : 'walk';
    speed.current = actualSpeed;
  });

  useFrame(({ camera, clock }, rawDelta) => {
    const b = body.current; if (!b) return;
    const dt = Math.min(rawDelta, .05), s = state.current, i = input.current, p = b.translation();
    if (model.current) {
      model.current.rotation.y = s.heading;
      model.current.rotation.z = motion.current === 'run' || motion.current === 'sprint' ? Math.sin(s.heading - i.yaw) * .035 : 0;
    }
    cameraLook.set(p.x, p.y + 1.45, p.z);
    cameraDirection.set(Math.sin(i.yaw) * Math.cos(i.pitch), Math.sin(i.pitch), Math.cos(i.yaw) * Math.cos(i.pitch));
    // Camera raycast uses physical scene colliders and ignores the player.
    const ray = new rapier.Ray(cameraLook, cameraDirection);
    const hit = world.castRay(ray, i.zoom, true, undefined, undefined, undefined, b);
    const distance = hit ? Math.max(1.5, hit.timeOfImpact - .25) : i.zoom;
    cameraTarget.copy(cameraLook).addScaledVector(cameraDirection, distance);
    if (!s.cameraStarted) { camera.position.copy(cameraTarget); s.cameraStarted = true; }
    else camera.position.lerp(cameraTarget, 1 - Math.exp(-8 * dt));
    camera.lookAt(cameraLook);
    if (clock.elapsedTime - s.lastHud > .1) {
      s.lastHud = clock.elapsedTime;
      onTelemetry({ x: p.x, y: p.y, z: p.z, motion: motion.current, speed: speed.current, phase: s.phase, heading: s.heading });
    }
  });
  return <RigidBody ref={body} type="kinematicPosition" colliders={false} position={[HARBOR.approach.x + ISLAND_3D.spawn.x - HARBOR.ship.x, HARBOR.ship.deck + .035, HARBOR.approach.z + ISLAND_3D.spawn.z - HARBOR.ship.z]} enabledRotations={[false, false, false]}>
    <CapsuleCollider args={[.5, .3]} position={[0, .81, 0]} />
    <group ref={model}>{children(motion, speed)}</group>
  </RigidBody>;
}