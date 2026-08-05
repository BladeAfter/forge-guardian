import {createHmac,timingSafeEqual} from 'node:crypto';
import {createClient} from '@supabase/supabase-js';

function telegramUser(initData){
  const token=process.env.TELEGRAM_BOT_TOKEN;if(!token)throw new Error('A autenticação do Telegram não está configurada.');
  const params=new URLSearchParams(initData),hash=params.get('hash')||'';params.delete('hash');
  const check=[...params.entries()].sort(([a],[b])=>a.localeCompare(b)).map(([key,value])=>`${key}=${value}`).join('\n');
  const secret=createHmac('sha256','WebAppData').update(token).digest();const expected=Buffer.from(createHmac('sha256',secret).update(check).digest('hex'),'hex'),received=Buffer.from(hash,'hex');
  const authDate=Number(params.get('auth_date'));if(received.length!==expected.length||!timingSafeEqual(received,expected)||!Number.isFinite(authDate)||Math.abs(Date.now()/1000-authDate)>86400)throw new Error('Sessão do Telegram inválida ou expirada.');
  const user=JSON.parse(params.get('user')||'null');if(!user?.id||!user?.first_name)throw new Error('Usuário do Telegram não encontrado.');return user;
}

export default async function handler(req,res){
  if(req.method!=='POST')return res.status(405).json({error:'Método não permitido.'});
  try{
    const user=telegramUser(typeof req.body?.initData==='string'?req.body.initData:'');const url=process.env.SUPABASE_URL||process.env.VITE_SUPABASE_URL,key=process.env.SUPABASE_SERVICE_ROLE_KEY;
    if(!url||!key)return res.status(503).json({error:'O backend do perfil não está configurado.'});
    const db=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});const result=await db.rpc('upsert_telegram_player_profile',{p_telegram_id:user.id,p_first_name:user.first_name,p_last_name:user.last_name||null,p_username:user.username||null,p_photo_url:user.photo_url||null});
    if(result.error)throw result.error;return res.status(200).json(result.data);
  }catch(error){console.error('[telegram-profile]',error instanceof Error?error.message:'Erro desconhecido');return res.status(400).json({error:error instanceof Error?error.message:'Não foi possível carregar seu perfil.'});}
}
