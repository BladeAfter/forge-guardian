import {describe,expect,it} from 'vitest';import {calculateReferralCommissions,validateReferralBinding} from './referralRules';
describe('referral rules',()=>{
 it('pays Lv1 10%',()=>expect(calculateReferralCommissions(['A'],1000)[0].amountFc).toBe(100));
 it('pays Lv2 5%',()=>expect(calculateReferralCommissions(['C','B'],1000)[1].amountFc).toBe(50));
 it('pays Lv3 2%',()=>expect(calculateReferralCommissions(['D','C','B'],1000)[2].amountFc).toBe(20));
 it('never pays Lv4',()=>expect(calculateReferralCommissions(['A','B','C','D'],1000)).toHaveLength(3));
 it('does not pay ineligible events',()=>expect(calculateReferralCommissions(['A'],1000,'daily_login')).toEqual([]));
 it('rejects self referral',()=>expect(()=>validateReferralBinding('A','A',null,[])).toThrow('SELF_REFERRAL_BLOCKED'));
 it('does not allow sponsor changes',()=>expect(()=>validateReferralBinding('A','C','B',[])).toThrow('SPONSOR_IMMUTABLE'));
 it('blocks cycles',()=>expect(()=>validateReferralBinding('A','B',null,['C','A'])).toThrow('REFERRAL_CYCLE_BLOCKED'));
 it('accepts a permanent existing sponsor',()=>expect(validateReferralBinding('A','B','B',[])).toBe(true));
 it('rejects invalid monetary values',()=>expect(calculateReferralCommissions(['A'],Infinity)).toEqual([]));
});
