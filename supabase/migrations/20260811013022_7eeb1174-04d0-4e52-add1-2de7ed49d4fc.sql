-- Central progress helper (authoritative, server-side only)
CREATE OR REPLACE FUNCTION public.record_daily_quest_progress(p_user_id uuid, p_event text, p_amount integer DEFAULT 1)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.record_quest_event(p_user_id, p_event, GREATEST(1, COALESCE(p_amount, 1)));
END;
$$;

-- Egg hatching only counts once the hatch actually completes
CREATE OR REPLACE FUNCTION public.quest_hook_pet_egg_hatched()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.status = 'completed' AND (TG_OP = 'INSERT' OR COALESCE(OLD.status,'') <> 'completed') THEN
    PERFORM public.record_quest_event(NEW.user_id, 'reward_opened', 1);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS quest_egg_hatch ON public.pet_hatch_history;
CREATE TRIGGER quest_egg_hatch
AFTER INSERT OR UPDATE OF status ON public.pet_hatch_history
FOR EACH ROW EXECUTE FUNCTION public.quest_hook_pet_egg_hatched();

-- Any chest/egg consumed from the inventory counts as a reward opening
CREATE OR REPLACE FUNCTION public.quest_hook_inventory_open()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.item_type IN ('hero_chest','pet_egg','mythic_egg') AND NEW.quantity < OLD.quantity THEN
    PERFORM public.record_quest_event(NEW.user_id, 'reward_opened', OLD.quantity - NEW.quantity);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS quest_inventory_open ON public.player_inventory;
CREATE TRIGGER quest_inventory_open
AFTER UPDATE OF quantity ON public.player_inventory
FOR EACH ROW EXECUTE FUNCTION public.quest_hook_inventory_open();
