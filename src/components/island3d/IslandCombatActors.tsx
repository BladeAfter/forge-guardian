import { useRef } from 'react';
import { Html } from '@react-three/drei';
import { useFrame } from '@react-three/fiber';
import * as THREE from 'three';
import { useT } from '../../LanguageContext';
import type { IslandPirateEnemy, IslandPirateSession } from '../../islandCombat';
import type { IslandMotion } from '../../island3dWorld';
import { ISLAND_MAP } from '../../illustratedIslandWorld';
import { frameDelta } from '../../gamePerformance';
import type { IslandPalette } from './IslandTerrain';
import { IslandPirate, IslandProp } from './IslandModels';
import './IslandCombatActors.css';

const colors = ['#527338', '#744e39', '#a44429', '#54839b', '#6b4779'];
export function IslandCombatActors({ session, palette }: { session?: IslandPirateSession | null; palette: IslandPalette }) {
  return <>{session?.state.enemies.map(enemy => <CombatActor key={enemy.id} enemy={enemy} palette={palette} />)}</>;
}
function CombatActor({ enemy, palette }: { enemy: IslandPirateEnemy; palette: IslandPalette }) {
  const t = useT(), group = useRef<THREE.Group>(null), fallen = useRef<THREE.Group>(null), motion = useRef<IslandMotion>('idle'), speed = useRef(0);
  const defeat = useRef({ started: enemy.hp > 0, elapsed: enemy.hp > 0 ? 0 : 1 });
  useFrame((_, rawDelta) => {
    if (document.hidden) return;
    const dt = frameDelta(rawDelta);
    if (enemy.hp <= 0 && defeat.current.started) {
      defeat.current.elapsed = Math.min(1, defeat.current.elapsed + dt * 1.8);
      if (fallen.current) { fallen.current.rotation.z = -Math.PI / 2 * defeat.current.elapsed; fallen.current.visible = defeat.current.elapsed < 1; }
    }
    if (!group.current) return;
    // Smooth only committed NPC locations; no predicted attacks or damage.
    group.current.position.x += (enemy.x - group.current.position.x) * (1 - Math.exp(-12 * dt));
    group.current.position.z += (enemy.z - group.current.position.z) * (1 - Math.exp(-12 * dt));
    motion.current = enemy.mode === 'attack' ? 'attack' : ['chase', 'patrol'].includes(enemy.mode) ? 'walk' : 'idle';
    speed.current = motion.current === 'walk' ? 2 : 0;
  });
  if (enemy.hp <= 0) return enemy.claimed ? null : <group>
    <group position={[enemy.x, ISLAND_MAP.floor, enemy.z]}><group ref={fallen} visible={defeat.current.elapsed < 1} scale={ISLAND_MAP.pirateScale}><IslandPirate style="male" motion={motion} speed={speed} palette={palette} /></group></group>
    <IslandProp model="chest" x={enemy.x} z={enemy.z} y={ISLAND_MAP.floor} scale={enemy.boss ? 1.65 : 1.15} collider="none" />
    <mesh position={[enemy.x, ISLAND_MAP.floor + .015, enemy.z]} rotation-x={-Math.PI / 2}><ringGeometry args={[1.2, 1.4, 24]} /><meshBasicMaterial color={enemy.boss ? '#af89fa' : '#dfb557'} transparent opacity={.8} /></mesh>
    <Html position={[enemy.x, 3.5, enemy.z]} center distanceFactor={65}><span className={`island-enemy-label ${enemy.boss ? 'island-enemy-label--rare' : ''}`}>{t(enemy.boss ? 'islandCombat.rareChest' : 'islandCombat.commonChest')}</span></Html>
  </group>;
  return <group ref={group} position={[enemy.x, ISLAND_MAP.floor, enemy.z]}>
    <group rotation-y={enemy.heading} scale={ISLAND_MAP.pirateScale * (enemy.boss ? 1.25 : 1)}><IslandPirate style="male" motion={motion} speed={speed} palette={{ ...palette, gold: colors[enemy.variant] ?? palette.gold }} /></group>
    <mesh position-y={.025} rotation-x={-Math.PI / 2}><ringGeometry args={[enemy.boss ? 1.6 : 1.1, enemy.boss ? 1.85 : 1.3, 24]} /><meshBasicMaterial color={colors[enemy.variant]} transparent opacity={.8} /></mesh>
    {enemy.mode === 'warning' && <mesh position-y={.04} rotation-x={-Math.PI / 2}><ringGeometry args={[5.2, 5.75, 32]} /><meshBasicMaterial color="#fa665b" transparent opacity={.75} /></mesh>}
    <Html position={[0, enemy.boss ? 5.6 : 4.5, 0]} center distanceFactor={65}><div className={`island-enemy-label ${enemy.boss ? 'island-enemy-label--rare' : ''}`}><b>{t(enemy.nameKey)}</b><progress max={enemy.maxHp} value={enemy.hp} /><small>{enemy.hp}/{enemy.maxHp} {enemy.boss && t('islandCombat.phase', { phase: enemy.phase })}</small>{enemy.mode === 'warning' && <strong>{t('islandCombat.warning')}</strong>}</div></Html>
  </group>;
}