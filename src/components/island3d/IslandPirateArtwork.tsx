import { useEffect } from 'react';
import { Billboard, useTexture } from '@react-three/drei';
import { SRGBColorSpace } from 'three';
import { pirateEncounterArt } from '../../islandPirateArt';

/** Grounded illustrated model; authoritative movement remains on the parent body. */
export function IslandPirateArtwork({ identity }: { identity: string }) {
  const art = pirateEncounterArt(identity);
  return art ? <Artwork image={art.image} aspect={art.aspect} /> : null;
}
function Artwork({ image, aspect }: { image: string; aspect: number }) {
  const texture = useTexture(image);
  useEffect(() => { texture.colorSpace = SRGBColorSpace; texture.needsUpdate = true; }, [texture]);
  return <Billboard><mesh position-y={.9}>
    <planeGeometry args={[1.8 * aspect, 1.8]} />
    <meshBasicMaterial map={texture} transparent alphaTest={.12} toneMapped={false} />
  </mesh></Billboard>;
}