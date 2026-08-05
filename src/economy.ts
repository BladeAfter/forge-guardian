export const FC_PER_TON=100_000;
export const MIN_WITHDRAWAL_FC=100_000;
export const TON_NANO=1_000_000_000;
export const tonToFc=(ton:number)=>Number.isFinite(ton)&&ton>0?Math.round(ton*FC_PER_TON):0;
export const fcToTon=(fc:number)=>Number.isFinite(fc)&&fc>0?fc/FC_PER_TON:0;
export const validWithdrawal=(amount:number,balance:number)=>Number.isInteger(amount)&&amount>=MIN_WITHDRAWAL_FC&&amount%MIN_WITHDRAWAL_FC===0&&amount<=balance;
