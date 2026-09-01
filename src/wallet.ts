export type DepositType='ton_to_fc'|'ton_balance';
export type WalletDepositConfig={fcEnabled:boolean;directEnabled:boolean;minFcTon:number;minDirectTon:number;fcPerTon:number};
export type WalletHistoryItem={id:string;type:'deposit'|'withdrawal'|'egg_order';depositType?:DepositType;txHash?:string|null;label:string;amountFc:number|null;amountTon:number|null;grossTon?:number|null;feePercent?:number|null;feeTon?:number|null;netTon?:number|null;status:string;createdAt:string};
export type WalletSummary={balanceFc:number;equivalentTon:number;withdrawFeePercent?:number;fcPerTon?:number;depositConfig?:WalletDepositConfig;deposits:Array<{id:string;depositType?:DepositType;txHash?:string|null;amountTon:number;amountFc:number;status:string;createdAt:string}>;withdrawals:Array<{id:string;amountFc:number;amountTon:number;grossTon?:number;feePercent?:number;feeTon?:number;netTon?:number;status:string;createdAt:string}>;eggOrders:Array<{id:string;eggName:string;priceTon:number;status:string;createdAt:string}>;history:WalletHistoryItem[]};
export type TonPaymentIntent={id:string;depositType?:DepositType;paymentAddress:string;amountNano:string;amountTon:number;amountFc?:number;paymentComment:string;expiresAt:string};

/** Withdrawable TON balance: fed ONLY by official rewards (pool, events, admin). Never by FC. */
export type TonRewardEntry={id:string;amountTon:number;direction:'credit'|'debit';sourceType:string;sourceId:string|null;status:string;note:string|null;createdAt:string};
export type TonWithdrawalEntry={id:string;grossTon:number;feePercent:number;feeTon:number;netTon:number;status:string;source:string;createdAt:string};
export type TonWallet={balanceFc:number;availableTon:number;lockedTon?:number;withdrawableTon?:number;reservedTon:number;feePercent:number;minWithdrawTon:number;depositRequirementTon?:number;depositTotalTon?:number;depositRequirementMet?:boolean;passRequirementMet?:boolean;passRequirementTon?:number;rewards:TonRewardEntry[];withdrawals:TonWithdrawalEntry[]};
export type TonWithdrawalReceipt={id:string;status:string;grossTon:number;feePercent:number;feeTon:number;netTon:number;walletAddress:string;availableTon?:number};

/** MYTH Token: decorative only. Supply lives with the Admin Bot; players never buy, sell or withdraw it. */
export type MythWallet={name:string;symbol:string;balance:number;staked?:number;totalOwned?:number;totalSupply:number;circulating?:number;sold?:number;burned?:number;feePercent?:number|null;feeThreshold?:number;feePercentReduced?:number;visible:boolean;status:string;tradable:false;withdrawable:false;hasUtility:false};
