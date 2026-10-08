ALTER TABLE public.nft_mining_ledger DROP CONSTRAINT IF EXISTS nft_mining_ledger_entry_type_check;
ALTER TABLE public.nft_mining_ledger ADD CONSTRAINT nft_mining_ledger_entry_type_check CHECK (entry_type = ANY (ARRAY[
  'NFT_MINING_TON_ACCRUAL',
  'NFT_MINING_TON_CLAIM',
  'NFT_MINING_MYTH_ACCRUAL',
  'NFT_MINING_MYTH_CLAIM',
  'NFT_MINING_CURRENCY_CHANGED',
  'RARE_MYTH_MINING_ACCRUAL',
  'RARE_MYTH_MINING_CLAIM'
]));