export const FC_PER_TON=100_000;
export const MIN_WITHDRAWAL_FC=100_000;
export const TON_NANO=1_000_000_000;
export const tonToFc=(ton:number)=>Number.isFinite(ton)&&ton>0?Math.round(ton*FC_PER_TON):0;
export const fcToTon=(fc:number)=>Number.isFinite(fc)&&fc>0?fc/FC_PER_TON:0;
export const validWithdrawal=(amount:number,balance:number)=>Number.isInteger(amount)&&amount>=MIN_WITHDRAWAL_FC&&amount%MIN_WITHDRAWAL_FC===0&&amount<=balance;
export const DEFAULT_WITHDRAW_FEE_PERCENT=10;
export type WithdrawalQuote={fc:number;feePercent:number;grossTon:number;feeTon:number;netTon:number};
const round6=(value:number)=>Math.round(value*1e6)/1e6;
/** Estimativa exibida ao jogador. O backend recalcula e é a autoridade final. */
export function withdrawalQuote(fc:number,feePercent:number=DEFAULT_WITHDRAW_FEE_PERCENT):WithdrawalQuote{
  const percent=Number.isFinite(feePercent)&&feePercent>=0&&feePercent<=50?feePercent:DEFAULT_WITHDRAW_FEE_PERCENT;
  const gross=round6(fcToTon(fc));
  const fee=round6(gross*percent/100);
  return{fc,feePercent:percent,grossTon:gross,feeTon:fee,netTon:round6(gross-fee)};
}
export const formatTon=(value:number)=>(Number.isFinite(value)?value:0).toFixed(3);
