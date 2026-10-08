export type DailyQuest = {
  code: string;
  title: string;
  description: string | null;
  icon: string | null;
  target: number;
  progress: number;
  rewardFc: number;
  rewardItem: { type: string; code: string; quantity: number } | null;
  completed: boolean;
  claimed: boolean;
};

export type DailyQuestBonus = {
  name: string;
  itemType: string;
  itemCode: string;
  quantity: number;
  unlocked: boolean;
  claimed: boolean;
};

export type DailyQuestsDashboard = {
  questDate: string;
  timezone: string;
  total: number;
  completed: number;
  balance: number;
  quests: DailyQuest[];
  bonus: DailyQuestBonus;
};

export type QuestClaimResult = {
  claimed: boolean;
  code?: string;
  rewardFc?: number;
  balance?: number;
  itemType?: string;
  itemCode?: string;
  inventoryItemId?: string;
  quests: DailyQuestsDashboard;
};
