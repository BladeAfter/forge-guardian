/**
 * POOL MARKETING (Community Pool tab): read-only project transparency.
 * Every value comes from the backend (`marketing_pool_dashboard`) and is edited
 * exclusively by the admin bot — nothing here is hardcoded in the client.
 */
export type MarketingPoolExpense = {
  id: string;
  category: string;
  description: string;
  amountTon: number;
  note: string | null;
  spentAt: string;
};

export type MarketingPoolDashboard = {
  enabled: boolean;
  totalTon: number;
  spentTon: number;
  remainingTon: number;
  entries: number;
  updatedAt: string | null;
  categories: string[];
  expenses: MarketingPoolExpense[];
};
