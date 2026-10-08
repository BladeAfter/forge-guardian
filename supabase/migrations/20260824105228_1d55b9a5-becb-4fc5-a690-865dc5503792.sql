SELECT cron.unschedule(jobid) FROM cron.job WHERE command ILIKE '%clan_boss_auto_attacks%' OR jobname = 'clan-boss-auto-attacks';

SELECT cron.schedule('clan-boss-auto-tick', '* * * * *', $$
  select net.http_post(
    url:='https://oaivxwzrggfqhapohlht.supabase.co/functions/v1/clan-boss-auto-tick',
    headers:='{"Content-Type": "application/json", "apikey": "sb_publishable_aO2th7uGcAs84v9kR4m7Cg_6mmZVNpZ"}'::jsonb,
    body:=concat('{"time": "', now(), '"}')::jsonb
  ) as request_id;
$$);