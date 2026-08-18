update public.hero_catalog set hero_class = v.cls
from (values
 ('common-1','warrior'),('common-2','warrior'),('common-3','archer'),('common-4','support'),('common-5','tank'),
 ('uncommon-1','archer'),('uncommon-2','assassin'),('uncommon-3','archer'),('uncommon-4','archer'),('uncommon-5','assassin'),
 ('rare-1','tank'),('rare-2','warrior'),('rare-3','warrior'),('rare-4','support'),('rare-5','tank'),
 ('epic-1','mage'),('epic-2','mage'),('epic-3','warrior'),('epic-4','mage'),('epic-5','warrior'),
 ('legendary-1','warrior'),('legendary-2','mage'),('legendary-3','tank'),('legendary-4','mage'),('legendary-5','warrior'),
 ('nft-thalvyra','archer')
) as v(hero_key,cls)
where public.hero_catalog.hero_key = v.hero_key;

update public.player_heroes ph
   set archetype = hc.hero_class
  from public.hero_catalog hc
 where hc.hero_key = ph.hero_key
   and hc.hero_class in ('warrior','assassin','tank','mage','archer','support')
   and ph.archetype is distinct from hc.hero_class;