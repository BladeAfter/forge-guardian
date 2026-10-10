/** Display policy only: server balances, ownership and settlements remain intact. */
export function isMythTokenReward(type: string): boolean {
  return /(^|_)myth($|_)/i.test(type) || type.toLowerCase() === 'myth';
}
export function isVisiblePurchaseCurrency(currency: string): boolean {
  return ['FC', 'BERRIES', 'TON'].includes(currency.toUpperCase());
}
