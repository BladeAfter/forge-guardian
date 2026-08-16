do $$
declare res jsonb;
begin
  -- cancel the duplicate unpaid order for the same item
  update public.nft_equipment_orders
     set status = 'expired', updated_at = now()
   where id = '6984eaee-cc1e-47ce-a549-29eddace3d4c'
     and status = 'pending';

  select public.nft_equipment_confirm_purchase(
    'c8016744-b876-4550-a3a6-cc9168229d79'::uuid,
    'OLuUR1rzGu2NxMNc/wiNu4UwgMLb9yG9XbwYs5uHJN8=',
    '2000000000'
  ) into res;
  raise notice 'delivery result: %', res;
end $$;