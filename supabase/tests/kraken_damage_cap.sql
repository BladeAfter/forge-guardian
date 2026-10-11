BEGIN;
SET LOCAL ROLE service_role;
DO $test$
DECLARE hit numeric; hp numeric := 100;
BEGIN
  hit := public.kraken_damage_to_hero(99999, 'common', 100, 0);
  IF hit <> 35 THEN RAISE EXCEPTION 'Huge hit cap failed'; END IF;
  hp := greatest(0, hp - hit);
  IF hp <> 65 THEN RAISE EXCEPTION 'Full health did not survive'; END IF;
  hp := greatest(0, hp - hit);
  IF hp <> 30 THEN RAISE EXCEPTION 'Second hit did not survive'; END IF;
  hp := greatest(0, hp - hit);
  IF hp <> 0 THEN RAISE EXCEPTION 'Low health cannot be knocked out'; END IF;
  IF public.kraken_damage_to_hero(8,'legendary',300,0) <> 6
    OR public.kraken_damage_to_hero(100,'common',100,90) <> 10 THEN
    RAISE EXCEPTION 'Rarity or pet mitigation lost';
  END IF;
END $test$;
ROLLBACK;