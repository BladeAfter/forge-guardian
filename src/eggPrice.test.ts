import{describe,expect,it}from'vitest';import{formatEggPrice}from'./eggPurchase';
describe('formatEggPrice',()=>{it('shows a single BERRIES price without changing the FC value',()=>{expect(formatEggPrice({priceFc:50000})).toBe('50.000 BERRIES')});
it('shows a single TON price',()=>{expect(formatEggPrice({priceTon:3})).toBe('3 TON');expect(formatEggPrice({priceTon:10})).toBe('10 TON')});
it('falls back to availability label when not for sale',()=>{expect(formatEggPrice({availabilityLabel:'Evento Exclusivo'})).toBe('Evento Exclusivo')})});
