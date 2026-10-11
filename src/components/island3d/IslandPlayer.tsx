import { useEffect, useMemo, useRef, type MutableRefObject } from 'react';
import { useFrame } from '@react-three/fiber';
import { CapsuleCollider, RigidBody, useBeforePhysicsStep, useRapier, type RapierRigidBody } from '@react-three/rapier';
import * as THREE from 'three';
import { cameraRelativeMotion, HARBOR, ISLAND_3D, type HarborState, type IslandInput, type IslandMotion, type IslandTelemetry } from '../../island3dWorld';
import { ISLAND_MAP, islandWalkable, safeIslandStep } from '../../illustratedIslandWorld';

type Props = { islandIndex: number; harbor: MutableRefObject<HarborState>; input: MutableRefObject<IslandInput>; onTelemetry: (value: IslandTelemetry) => void; onReturn: () => void; children: (motion: MutableRefObject<IslandMotion>, speed: MutableRefObject<number>) => React.ReactNode };
export function IslandPlayer({ islandIndex, harbor, input, onTelemetry, onReturn, children }: Props) {
  const body = useRef<RapierRigidBody>(null), model = useRef<THREE.Group>(null);
  const motion = useRef<IslandMotion>('walk'), speed = useRef(0);
  const { world, rapier } = useRapier();
  const controller = useMemo(() => {
    const c = world.createCharacterController(.01);
    c.enableAutostep(.45, .3, true); c.enableSnapToGround(.3); c.setMaxSlopeClimbAngle(Math.PI / 3); c.setMinSlopeSlideAngle(Math.PI / 3);
    return c;
  }, [world]);
  useEffect(() => () => { world.removeCharacterController(controller); }, [world, controller]);
  const state = useRef({ phase: 'approaching' as IslandTelemetry['phase'], waypoint: 0, vy: 0, grounded: true, heading: Math.PI, action: 0, actionKind: 'idle' as IslandMotion, jumpHeld: false, returned: false, cameraStarted: false, lastHud: 0, ray: new rapier.Ray({ x: 0, y: 0, z: 0 }, { x: 0, y: 0, z: 1 }) });
  const cameraTarget = useMemo(() => new THREE.Vector3(), []);
  const cameraLook = useMemo(() => new THREE.Vector3(), []);
  const cameraDirection = useMemo(() => new THREE.Vector3(), []);
  const lastSafe = useRef({ ...ISLAND_3D.shore, y: ISLAND_MAP.floor + .035 });

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
    if (s.phase === 'exploring' && (!islandWalkable(islandIndex, p) || !Number.isFinite(p.y) || p.y < ISLAND_MAP.floor - .2)) {
      b.setTranslation(lastSafe.current, true); b.setNextKinematicTranslation(lastSafe.current);
      s.vy = 0; s.grounded = true; s.action = 0; speed.current = 0; motion.current = 'idle';
      return;
    }
    let dx = 0, dz = 0, targetSpeed = 0;
    if (s.phase === 'landing' || s.phase === 'boarding') {
      const route = s.phase === 'landing' ? [{ x: 4.1, z: HARBOR.gangway.z }, ISLAND_3D.gangway, ISLAND_3D.shore] : [ISLAND_3D.gangway, { x: 4.1, z: HARBOR.gangway.z }, ISLAND_3D.spawn];
      const goal = route[s.waypoint] ?? route[route.length - 1];
      const x = goal.x - p.x, z = goal.z - p.z, d = Math.hypot(x, z);
      if (d < .35) {
        if (s.waypoint < route.length - 1) s.waypoint++;
        else if (s.phase === 'landing') s.phase = 'exploring';
        else { s.returned = true; onReturn(); return; }
      } else { dx = x / d; dz = z / d; targetSpeed = 4.1; }
    } else if (!i.blocked) {
      const vector = cameraRelativeMotion(i.x, -i.y, i.yaw);
      dx = vector.x; dz = vector.z;
      const magnitude = Math.min(1, Math.hypot(i.x, i.y));
      targetSpeed = magnitude * (i.sprint ? 6.5 : magnitude < .7 ? 2.3 : 4.1);
    }
    // Official encounter responses can request an attack while the encounter HUD locks movement.
    if (i.attack && s.action <= 0) { s.action = .75; s.actionKind = 'attack'; }
    if (i.interact && s.action <= 0) { s.action = .8; s.actionKind = 'interact'; }
    if (i.dodge && s.phase === 'exploring' && !i.blocked && s.action <= 0 && s.grounded) { s.action = .55; s.actionKind = 'dodge'; }
    i.attack = false; i.interact = false; i.dodge = false;
    if (s.action > 0) {
      s.action -= dt;
      if (s.actionKind === 'dodge') { dx = Math.sin(s.heading); dz = Math.cos(s.heading); targetSpeed = 7; }
      else targetSpeed = 0;
    }
    speed.current += (targetSpeed - speed.current) * (1 - Math.exp(-16 * dt));
    if (targetSpeed === 0 && speed.current < .08) speed.current = 0;
    if (i.jump && s.phase === 'exploring' && !s.jumpHeld && s.grounded && !i.blocked) { s.vy = 6.5; s.grounded = false; }
    s.jumpHeld = i.jump;
    s.vy = Math.max(-18, s.vy - 19 * dt);
    const collider = b.collider(0);
    if (!collider) return;
    const automatic = s.phase === 'landing' || s.phase === 'boarding';
    const desired = safeIslandStep(islandIndex, p, { x: p.x + dx * speed.current * dt, z: p.z + dz * speed.current * dt }, automatic);
    controller.computeColliderMovement(collider, { x: desired.x - p.x, y: s.vy * dt, z: desired.z - p.z }, undefined, undefined, c => c.parent()?.handle !== b.handle);
    const movement = controller.computedMovement();
    s.grounded = controller.computedGrounded();
    if (s.grounded && s.vy < 0) s.vy = 0;
    const safe = safeIslandStep(islandIndex, p, { x: p.x + movement.x, z: p.z + movement.z }, automatic);
    movement.x = safe.x - p.x; movement.z = safe.z - p.z;
    const next = { ...safe, y: p.y + movement.y };
    b.setNextKinematicTranslation(next);
    if (s.phase === 'exploring' && s.grounded && next.y >= ISLAND_MAP.floor - .1) lastSafe.current = next;
    if (Math.hypot(movement.x, movement.z) > .001) {
      const target = Math.atan2(dx, dz);
      s.heading += Math.atan2(Math.sin(target - s.heading), Math.cos(target - s.heading)) * (1 - Math.exp(-14 * dt));
    }
    const actualSpeed = Math.hypot(movement.x, movement.z) / dt;
    motion.current = s.action > 0 ? s.actionKind : !s.grounded ? s.vy > 0 ? 'jump' : 'fall' : actualSpeed < .1 ? 'idle' : movement.y > .018 ? 'climb' : movement.y < -.018 ? 'descend' : actualSpeed > 5 ? 'sprint' : actualSpeed > 2.6 ? 'run' : 'walk';
    speed.current = actualSpeed;
  });

  useFrame(({ camera, clock, size }, rawDelta) => {
    const b = body.current; if (!b) return;
    const dt = Math.min(rawDelta, .05), s = state.current, i = input.current, p = b.translation();
    if (model.current) {
      model.current.rotation.y = s.heading;
      model.current.rotation.z = motion.current === 'run' || motion.current === 'sprint' ? Math.sin(s.heading - i.yaw) * .035 : 0;
    }
    if (model.current) model.current.getWorldPosition(cameraLook);
    else cameraLook.set(p.x, p.y, p.z);
    cameraLook.y += 1.45;
    cameraDirection.set(Math.sin(i.yaw) * Math.cos(i.pitch), Math.sin(i.pitch), Math.cos(i.yaw) * Math.cos(i.pitch));
    // Camera raycast uses physical scene colliders and ignores the player.
    let distance = 75;
    if (camera instanceof THREE.OrthographicCamera) {
      const zoom = Math.min(size.width, size.height) / i.zoom;
      if (camera.zoom !== zoom) { camera.zoom = zoom; camera.updateProjectionMatrix(); }
    } else {
      Object.assign(s.ray.origin, cameraLook);
      Object.assign(s.ray.dir, cameraDirection);
      const hit = world.castRay(s.ray, i.zoom, true, undefined, undefined, undefined, b);
      distance = hit ? Math.max(1.5, hit.timeOfImpact - .25) : i.zoom;
    }
    cameraTarget.copy(cameraLook).addScaledVector(cameraDirection, distance);
    if (!s.cameraStarted) { camera.position.copy(cameraTarget); s.cameraStarted = true; }
    else camera.position.lerp(cameraTarget, 1 - Math.exp(-8 * dt));
    camera.lookAt(cameraLook);
    if (clock.elapsedTime - s.lastHud > .2) {
      s.lastHud = clock.elapsedTime;
      onTelemetry({ x: p.x, y: p.y, z: p.z, motion: motion.current, speed: speed.current, phase: s.phase, heading: s.heading });
    }
  });
  return <RigidBody ref={body} type="kinematicPosition" colliders={false} position={[HARBOR.approach.x + ISLAND_3D.spawn.x - HARBOR.ship.x, HARBOR.ship.deck + .035, HARBOR.approach.z + ISLAND_3D.spawn.z - HARBOR.ship.z]} enabledRotations={[false, false, false]}>
    <CapsuleCollider args={[.5, .3]} position={[0, .81, 0]} />
    <group ref={model}>{children(motion, speed)}</group>
  </RigidBody>;
}
