export const REFERRAL_RATES=[.10,.05,.02] as const;
export const INELIGIBLE_REFERRAL_EVENTS=new Set(['referral_commission','withdrawal','admin_bonus','gift','free_reward','daily_login']);
export function calculateReferralCommissions(inviterChain:string[],amountFc:number,eventType='purchase'){
  if(!Number.isFinite(amountFc)||amountFc<=0||INELIGIBLE_REFERRAL_EVENTS.has(eventType))return [];
  return inviterChain.slice(0,3).map((userId,index)=>({userId,level:index+1,amountFc:Number((amountFc*REFERRAL_RATES[index]).toFixed(3))}));
}
export function validateReferralBinding(userId:string,inviterId:string,currentInviter:string|null,ancestorIds:string[]){
  if(userId===inviterId)throw new Error('SELF_REFERRAL_BLOCKED');
  if(currentInviter&&currentInviter!==inviterId)throw new Error('SPONSOR_IMMUTABLE');
  if(ancestorIds.includes(userId))throw new Error('REFERRAL_CYCLE_BLOCKED');
  return true;
}
