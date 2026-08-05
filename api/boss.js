import { createHmac, timingSafeEqual } from 'node:crypto';
import { createClient } from '@supabase/supabase-js';

function telegramUser(initData) {
  const token = process.env.TELEGRAM_BOT_TOKEN;
  if (!token) throw new Error('Telegram authentication is not configured.');
  const params = new URLSearchParams(initData); const hash = params.get('hash') || ''; params.delete('hash');
  const check = [...params.entries()].sort(([a],[b]) => a.localeCompare(b)).map(([k,v]) => `${k}=${v}`).join('\n');
  const secret = createHmac('sha256','WebAppData').update(token).digest();
  const expected = Buffer.from(createHmac('sha256',secret).update(check).digest('hex'),'hex'); const received = Buffer.from(hash,'hex');
  const authDate = Number(params.get('auth_date'));
  if (received.length !== expected.length || !timingSafeEqual(received,expected) || !Number.isFinite(authDate) || Math.abs(Date.now()/1000-authDate)>86400) throw new Error('Invalid or expired Telegram initData.');
  const user = JSON.parse(params.get('user') || 'null'); if (!user?.id) throw new Error('Telegram user is missing.'); return user;
}

export default async function handler(req,res) {
  if (req.method !== 'POST') return res.status(405).json({error:'Method not allowed.'});
  try {
    const user = telegramUser(typeof req.body?.initData === 'string' ? req.body.initData : '');
    const url=process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL; const key=process.env.SUPABASE_SERVICE_ROLE_KEY;
    if (!url || !key) return res.status(503).json({error:'Boss backend is not configured.'});
    const db=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}}); const action=req.body?.action || 'process';
    const fn=action==='equip'?'equip_combat_hero':action==='team'?'set_boss_team':action==='claim'?'claim_boss_reward':action==='recruit'?'recruit_heroes':action==='get'?'get_boss_combat':'process_boss_combat';
    const args={p_telegram_id:user.id};
    if(action==='equip'){
      const slot=Number(req.body?.slot); const heroId=typeof req.body?.hero_id==='string'?req.body.hero_id:'';
      if(!Number.isInteger(slot)||slot<1||slot>5) throw new Error('Slot inválido.');
      if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(heroId)) throw new Error('Herói inválido.');
      args.p_hero_id=heroId;args.p_slot=slot;
    }
    if(action==='team') args.p_hero_ids=Array.isArray(req.body.heroIds)?req.body.heroIds:[]; if(action==='recruit') args.p_count=Number(req.body.count);
    const {data,error}=await db.rpc(fn,args); if(error) throw error;
    if(action!=='recruit'){
      const pets=await db.rpc('get_pet_dashboard',{p_telegram_id:user.id});
      if(!pets.error&&data&&typeof data==='object')return res.status(200).json({...data,petSummary:{activePet:pets.data?.activePet??null,bonuses:pets.data?.bonuses??{}}});
    }
    return res.status(200).json(data);
  } catch(error) { return res.status(400).json({error:error instanceof Error?error.message:'Boss request failed.'}); }
}
