import {createHmac,timingSafeEqual} from 'node:crypto';
import {createClient} from '@supabase/supabase-js';

function authenticate(initData){
  const token=process.env.TELEGRAM_BOT_TOKEN;
  if(!token)throw new Error('A autenticação do Telegram não está configurada.');
  const params=new URLSearchParams(initData);const hash=params.get('hash')||'';params.delete('hash');
  const check=[...params.entries()].sort(([a],[b])=>a.localeCompare(b)).map(([k,v])=>`${k}=${v}`).join('\n');
  const secret=createHmac('sha256','WebAppData').update(token).digest();
  const expected=Buffer.from(createHmac('sha256',secret).update(check).digest('hex'),'hex');const received=Buffer.from(hash,'hex');
  const authDate=Number(params.get('auth_date'));
  if(received.length!==expected.length||!timingSafeEqual(received,expected)||!Number.isFinite(authDate)||Math.abs(Date.now()/1000-authDate)>86400)throw new Error('Sessão do Telegram inválida ou expirada.');
  const user=JSON.parse(params.get('user')||'null');if(!user?.id)throw new Error('Usuário do Telegram não encontrado.');return user;
}

async function getBotIdentity(token){
  const configured=String(process.env.TELEGRAM_BOT_USERNAME||'').trim().replace(/^@/,'');
  if(configured)return {botUsername:configured,appShortName:String(process.env.TELEGRAM_APP_SHORT_NAME||'').trim()||null};
  const response=await fetch(`https://api.telegram.org/bot${token}/getMe`);
  const payload=await response.json().catch(()=>null);
  const username=payload?.ok&&payload?.result?.username?String(payload.result.username).replace(/^@/,''):'';
  if(!username)throw new Error('Não foi possível identificar o bot do Telegram. Configure TELEGRAM_BOT_USERNAME.');
  return {botUsername:username,appShortName:String(process.env.TELEGRAM_APP_SHORT_NAME||'').trim()||null};
}

function referralLink({botUsername,appShortName},telegramId){
  const route=appShortName?`${botUsername}/${appShortName}`:botUsername;
  return `https://t.me/${route}?startapp=${telegramId}`;
}

export default async function handler(req,res){
  if(req.method!=='POST')return res.status(405).json({error:'Método não permitido.'});
  let authenticatedTelegramId=null;
  try{
    const user=authenticate(typeof req.body?.initData==='string'?req.body.initData:'');authenticatedTelegramId=user.id;
    const url=process.env.SUPABASE_URL||process.env.VITE_SUPABASE_URL;const key=process.env.SUPABASE_SERVICE_ROLE_KEY;
    if(!url||!key)return res.status(503).json({error:'O backend de convites não está configurado.'});
    const db=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
    const fullName=[user.first_name,user.last_name].filter(Boolean).join(' ');
    const touched=await db.rpc('touch_referral_player',{p_telegram_id:user.id,p_name:fullName,p_username:user.username||'',p_avatar:user.photo_url||''});if(touched.error)throw touched.error;
    if(req.body?.action==='bind'){
      const inviterId=Number(req.body?.inviterTelegramId);if(!Number.isSafeInteger(inviterId)||inviterId<=0)throw new Error('Indicador inválido.');
      const linked=await db.rpc('bind_referral',{p_telegram_id:user.id,p_inviter_telegram_id:inviterId});if(linked.error)throw linked.error;return res.status(200).json(linked.data);
    }
    const level=req.body?.level==null?null:Number(req.body.level);const offset=Math.max(0,Number(req.body?.offset)||0);const limit=Math.min(20,Math.max(1,Number(req.body?.limit)||20));
    if(level!==null&&![1,2,3].includes(level))throw new Error('Filtro de nível inválido.');
    const dashboard=await db.rpc('get_referral_dashboard_v2',{p_telegram_id:user.id,p_level:level,p_offset:offset,p_limit:limit});if(dashboard.error)throw dashboard.error;
    const identity=await getBotIdentity(process.env.TELEGRAM_BOT_TOKEN);const link=referralLink(identity,user.id);
    return res.status(200).json({...dashboard.data,...identity,telegramId:user.id,link,referralLink:link});
  }catch(error){
    console.error('[getReferralDashboard]',{telegramId:authenticatedTelegramId,error:error instanceof Error?error.message:'Erro desconhecido'});
    return res.status(400).json({error:error instanceof Error?error.message:'Não foi possível carregar seus convites.'});
  }
}
