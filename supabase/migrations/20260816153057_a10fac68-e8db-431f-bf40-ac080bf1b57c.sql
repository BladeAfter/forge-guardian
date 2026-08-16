ALTER TABLE public.wallet_deposits DROP CONSTRAINT IF EXISTS wallet_deposits_amount_fc_check;
ALTER TABLE public.wallet_deposits
  ADD CONSTRAINT wallet_deposits_amount_fc_check CHECK (
    amount_fc >= 0
    AND (deposit_type <> 'ton_to_fc' OR amount_fc > 0)
  );