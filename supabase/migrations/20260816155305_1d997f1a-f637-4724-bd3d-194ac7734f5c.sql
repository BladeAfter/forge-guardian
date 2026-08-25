-- 5 novos Clan Bosses (ciclos 11-15). A rotação já é automática:
-- clan_boss_template_for_cycle pega o maior cycle_number <= ciclo atual e
-- ensure_clan_boss_instance cria a nova instância assim que a anterior morre.
INSERT INTO public.clan_boss_templates
  (cycle_number, boss_key, name, subtitle, theme, max_hp, base_damage, reward_fc, reward_clan_xp, enabled, sort_order)
VALUES
  (11,'obsidian_leviathan','Obsidian Leviathan','Coil of the Black Depths','obsidian',2600000,1250,1000000,6000,true,11),
  (12,'sunken_oracle','Sunken Oracle','Prophet of the Drowned Stars','sunken',3300000,1550,500000,7000,true,12),
  (13,'ashen_warbringer','Ashen Warbringer','Forgemaster of the Cinder War','ashen',4200000,1900,620000,8500,true,13),
  (14,'celestial_inquisitor','Celestial Inquisitor','Judgment of the White Flame','celestial',5400000,2400,780000,10000,true,14),
  (15,'nightmare_sovereign','Nightmare Sovereign','Throne of Endless Dread','nightmare',7000000,3000,1000000,12500,true,15)
ON CONFLICT (boss_key) DO UPDATE SET
  cycle_number=EXCLUDED.cycle_number, name=EXCLUDED.name, subtitle=EXCLUDED.subtitle, theme=EXCLUDED.theme,
  max_hp=EXCLUDED.max_hp, base_damage=EXCLUDED.base_damage, reward_fc=EXCLUDED.reward_fc,
  reward_clan_xp=EXCLUDED.reward_clan_xp, enabled=true, sort_order=EXCLUDED.sort_order, updated_at=now();