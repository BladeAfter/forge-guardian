import type { ReactNode } from 'react';
import { Anchor, Compass, Flag, Info, Swords } from 'lucide-react';
import type { HeroRarity, ShopHero } from '../heroCatalog';
import { recruitmentArt } from '../gameAssets';
import { formatCurrency } from '../utils';

type Props = {
  odds: Array<{ rarity: HeroRarity; chance: number }>;
  price: (count: number) => number;
  results: ShopHero[];
  onRecruit: (count: 1 | 5 | 10) => void;
  rarityLabel: (rarity: HeroRarity) => string;
  alternativePayment: (count: 1 | 5 | 10) => ReactNode;
  balanceHint: ReactNode;
};

/** Pirate presentation of the existing recruitment operation; never rolls or grants heroes. */
export function RecruitCrewView({ odds, price, results, onRecruit, rarityLabel, alternativePayment, balanceHint }: Props) {
  return (
    <div className="crew-recruit">
      <section className="crew-scene" aria-labelledby="crew-title">
        <img src={recruitmentArt.harbor} alt="Navio pirata aguardando sua tripulação no porto" width={1536} height={1024} />
        <div className="crew-scene-shade" />
        <div className="crew-scene-heading">
          <span className="crew-eyebrow"><Compass size={13} /> PORTO DOS AVENTUREIROS</span>
          <h3 id="crew-title">Sua próxima<br />grande tripulação.</h3>
        </div>
      </section>

      <section className="crew-odds" aria-label="Chances de recrutamento">
        <div className="crew-section-heading"><Swords size={14} /><h4>CHANCES DE RECRUTAMENTO</h4><span>POR HERÓI</span></div>
        <div className="crew-odds-grid">
          {odds.filter(entry => entry.rarity !== 'ancestral').map(entry => (
            <div key={entry.rarity} className={`crew-odd crew-rarity-${entry.rarity}`}>
              <span>{rarityLabel(entry.rarity)}</span><strong>{entry.chance}%</strong>
            </div>
          ))}
        </div>
      </section>

      <section className="crew-contracts" aria-label="Recrutar tripulação">
        <div className="crew-section-heading"><Flag size={14} /><h4>ESCOLHA SUA TRIPULAÇÃO</h4></div>
        <div className="crew-contract-grid">
          {([1, 5, 10] as const).map(count => (
            <div className="crew-contract-option" key={count}>
              <button type="button" className={`crew-contract ${count === 10 ? 'crew-contract-fleet' : ''}`} onClick={() => onRecruit(count)} aria-label={`Recrutar ${count} ${count === 1 ? 'herói' : 'heróis'} por ${formatCurrency(price(count))} BERRIES`}>
                <img className="crew-contract-art" src={recruitmentArt.contracts[count]} alt={count === 1 ? 'Aventureiro pirata no porto' : count === 5 ? 'Tripulação de cinco aventureiros' : 'Frota de navios piratas'} width={768} height={1024} loading="lazy" />
                <strong>{count}×</strong>
                <span className="crew-contract-name">{count === 1 ? 'AVENTUREIRO' : count === 5 ? 'TRIPULAÇÃO' : 'FROTA'}</span>
                <span className="crew-contract-price">{formatCurrency(price(count))}<small>BERRIES</small></span>
                <span className="crew-contract-action">RECRUTAR</span>
              </button>
              {alternativePayment(count)}
            </div>
          ))}
        </div>
        {balanceHint}
      </section>

      <div className="crew-hint"><Info size={15} /><p>Heróis de maior raridade têm atributos e habilidades melhores. Evolua sua tripulação com a FUSÃO DE RARIDADE.</p></div>

      {results.length > 0 && (
        <section className="crew-results" aria-label="Últimos heróis recrutados" aria-live="polite">
          <div className="crew-section-heading"><Anchor size={14} /><h4>A BORDO DA SUA TRIPULAÇÃO</h4></div>
          <div className="crew-results-grid">
            {results.map((hero, index) => (
              <div key={`${hero.id}-${index}`} className={`crew-result crew-rarity-${hero.rarity}`}>
                <img src={hero.image} alt={hero.name} width={160} height={160} loading="lazy" />
                <span>{rarityLabel(hero.rarity)}</span>
              </div>
            ))}
          </div>
        </section>
      )}
    </div>
  );
}