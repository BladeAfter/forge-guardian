import { mainScreenArt } from '../gameAssets';
import { useLocalizedText } from '../LanguageContext';
import { OceanControl } from './OceanControl';
import './PortSideMenus.css';

type PortSideMenusProps = {
  onRealm: () => void; onPool: () => void; onShop: () => void; onPass: () => void;
  onInvites: () => void; onPvp: () => void; onPets: () => void; onHeroes: () => void;
};

/** Symmetric edge rails; every destination retains its official callback. */
export function PortSideMenus(props: PortSideMenusProps) {
  const text = useLocalizedText();
  const sides = [
    [
      { image: mainScreenArt.realm, label: 'GRAND LINE', action: props.onRealm },
      { image: mainScreenArt.seasonPass, label: 'DIÁRIO DE BORDO', action: props.onPass },
      { image: mainScreenArt.invite, label: 'RECRUTAR', action: props.onInvites },
      { image: mainScreenArt.pvp, label: 'DUELOS', action: props.onPvp },
    ],
    [
      { image: mainScreenArt.pool, label: 'BAÚ DA FROTA', action: props.onPool },
      { image: mainScreenArt.heroShop, label: 'TAVERNA', action: props.onShop },
      { image: mainScreenArt.pet, label: 'MASCOTE', action: props.onPets },
      { image: mainScreenArt.heroes, label: 'TRIPULAÇÃO', action: props.onHeroes },
    ],
  ];
  return <div className="port-side-menus">
    {sides.map((items, index) => <nav key={index} className={`port-side-rail port-side-rail--${index === 0 ? 'left' : 'right'}`}>
      {items.map(item => <OceanControl key={item.label} onClick={item.action} className="port-side-button" aria-label={text(item.label)}>
        <img src={item.image} alt="" width={64} height={64} />
        <span>{text(item.label)}</span>
      </OceanControl>)}
    </nav>)}
  </div>;
}