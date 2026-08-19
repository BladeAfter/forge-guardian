CREATE OR REPLACE FUNCTION public.sync_founder_frame_border()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
begin
  if NEW.code <> 'founder_frame' then return NEW; end if;
  if coalesce(NEW.equipped, false) then
    update public.game_players
       set avatar_border = 'founder_exclusive', updated_at = now()
     where id = NEW.user_id
       and coalesce(avatar_border, '') = '';
  else
    update public.game_players
       set avatar_border = null, updated_at = now()
     where id = NEW.user_id and avatar_border = 'founder_exclusive';
  end if;
  return NEW;
end
$$;

DROP TRIGGER IF EXISTS sync_founder_frame_border_trg ON public.player_entitlements;
CREATE TRIGGER sync_founder_frame_border_trg
AFTER INSERT OR UPDATE OF equipped ON public.player_entitlements
FOR EACH ROW EXECUTE FUNCTION public.sync_founder_frame_border();

UPDATE public.game_players g
   SET avatar_border = 'founder_exclusive', updated_at = now()
 WHERE coalesce(g.avatar_border, '') = ''
   AND EXISTS (
     SELECT 1 FROM public.player_entitlements e
      WHERE e.user_id = g.id AND e.code = 'founder_frame' AND coalesce(e.equipped, false)
   );