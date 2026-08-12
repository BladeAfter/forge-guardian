export type WalletHistoryItem={id:string;type:'deposit'|'withdrawal'|'egg_order';label:string;amountFc:number|null;amountTon:number|null;grossTon?:number|null;feePercent?:number|null;feeTon?:number|null;netTon?:number|null;status:string;createdAt:string};
export type WalletSummary={balanceFc:number;equivalentTon:number;withdrawFeePercent?:number;fcPerTon?:number;deposits:Array<{id:string;amountTon:number;amountFc:number;status:string;createdAt:string}>;withdrawals:Array<{id:string;amountFc:number;amountTon:number;grossTon?:number;feePercent?:number;feeTon?:number;netTon?:number;status:string;createdAt:string}>;eggOrders:Array<{id:string;eggName:string;priceTon:number;status:string;createdAt:string}>;history:WalletHistoryItem[]};
export type TonPaymentIntent={id:string;paymentAddress:string;amountNano:string;amountTon:number;amountFc?:number;paymentComment:string;expiresAt:string};

/** Withdrawable TON balance: fed ONLY by official rewards (pool, events, admin). Never by FC. */
export type TonRewardEntry={id:string;amountTon:number;direction:'credit'|'debit';sourceType:string;sourceId:string|null;status:string;note:string|null;createdAt:string};
export type TonWithdrawalEntry={id:string;grossTon:number;feePercent:number;feeTon:number;netTon:number;status:string;source:string;createdAt:string};
export type TonWallet={balanceFc:number;availableTon:number;reservedTon:number;feePercent:number;minWithdrawTon:number;rewards:TonRewardEntry[];withdrawals:TonWithdrawalEntry[]};
export type TonWithdrawalReceipt={id:string;status:string;grossTon:number;feePercent:number;feeTon:number;netTon:number;walletAddress:string;availableTon?:number};
