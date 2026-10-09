import { Archive, ShoppingCart } from 'lucide-react';
import type { PetEgg } from '../pets';
import { formatEggPrice } from '../eggPurchase';
import { mascotChestImage, mascotChestName, mascotChestTier } from '../gameAssets';
import { petRarityLabel } from '../petLabels';
import { useT } from '../LanguageContext';
import { OceanControl } from './OceanControl';

export function MascotChestCard({ egg, pending, onOpen, onBuy }: { egg: PetEgg; pending: boolean; onOpen: () => void; onBuy: () => void }) {
  const t = useT();
  const order = ['common', 'uncommon', 'rare', 'epic', 'legendary', 'mythic', 'ancestral', 'exclusive', 'nft_exclusive', 'celestial'];
  const rates = Object.entries(egg.rarityRates ?? {}).filter(([, rate]) => rate > 0).sort(([a], [b]) => order.indexOf(a) - order.indexOf(b));
  const locked = !egg.isPurchasable || (!egg.priceFc && !egg.priceTon);
  return <article className={`mascot-chest-card mascot-tier-${mascotChestTier(egg.slug)}`}>
    <img src={mascotChestImage(egg.slug)} alt={mascotChestName(egg.slug)} width={1024} height={1024} loading="lazy" />
    <h3>{mascotChestName(egg.slug)}</h3>
    <p className="mascot-chest-price">{formatEggPrice(egg)}</p>
    <div className="mascot-chest-rates">{rates.map(([rarity, rate]) => <span key={rarity}>{petRarityLabel(rarity)} <b>{rate}%</b></span>)}</div>
    <p className="mascot-chest-owned">{t('pets.youOwn', { quantity: egg.quantity })}</p>
    <OceanControl disabled={pending || (egg.quantity <= 0 && locked)} onClick={egg.quantity > 0 ? onOpen : onBuy}>
      {egg.quantity > 0 ? <Archive size={15} /> : <ShoppingCart size={15} />}
      {egg.quantity > 0 ? t('pets.openEgg') : locked ? egg.availabilityLabel || t('pets.exclusiveEvent') : t('pets.buyLabel')}
    </OceanControl>
  </article>;
}