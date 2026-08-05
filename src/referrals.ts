export type ReferralInvite={id:string;name:string;username:string|null;avatar:string|null;level:1|2|3;joinedAt:string;lastSeenAt:string;online:boolean;generated:number;commission:number};
export type ReferralCommissionLevel={level:1|2|3;percent:number;invitedCount:number;totalEarnedFc:number};
export type ReferralTreeNode={id:string;parentId:string;name:string;avatar:string|null;level:1|2|3};
export type ReferralRanking={position:number;id:string;name:string|null;avatar:string|null;invites:number;commissions:number};
export type ReferralDashboard={
  telegramId:number;link:string;referralLink?:string;botUsername?:string;appShortName?:string|null;
  profile?:{telegramId:string;username:string|null;firstName:string|null;photoUrl:string|null};
  commissionLevels?:ReferralCommissionLevel[];summary?:{totalInvited:number;totalEarnedFc:number;earnedTodayFc:number;earned7DaysFc:number};
  pagination?:{offset:number;limit:number;hasMore:boolean};counts:{total:number;lv1:number;lv2:number;lv3:number};
  earnings:{today:number;yesterday:number;days7:number;days30:number;total:number};
  invites:ReferralInvite[];tree:ReferralTreeNode[];ranking:ReferralRanking[];
  bonuses:Array<{milestone:number;bonusFc:number;enabled:boolean;claimed:boolean}>;
  notifications:Array<{id:string;title:string;message:string;amountFc:number|null;createdAt:string}>;
};

export const buildTelegramShareUrl=(referralLink:string,text='Entre no Forge Village pelo meu convite!')=>
  `https://t.me/share/url?url=${encodeURIComponent(referralLink)}&text=${encodeURIComponent(text)}`;
