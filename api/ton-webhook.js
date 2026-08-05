import{timingSafeEqual}from'node:crypto';import{createClient}from'@supabase/supabase-js';
export default async function handler(req,res){
 if(req.method!=='POST')return res.status(405).json({error:'Method not allowed.'});
 try{
  const configured=Buffer.from(process.env.TON_WEBHOOK_SECRET||''),received=Buffer.from(String(req.headers['x-ton-webhook-secret']||''));
  if(!configured.length||configured.length!==received.length||!timingSafeEqual(configured,received))return res.status(401).json({error:'Unauthorized.'});
  const{kind,id,txHash,amountNano}=req.body||{};
  if(!['deposit','egg','season_pass'].includes(kind)||typeof txHash!=='string'||typeof amountNano!=='string')throw new Error('Invalid confirmation payload.');
  const url=process.env.SUPABASE_URL||process.env.VITE_SUPABASE_URL,key=process.env.SUPABASE_SERVICE_ROLE_KEY;
  if(!url||!key)throw new Error('Backend not configured.');
  const db=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}}),table=kind==='deposit'?'wallet_deposits':kind==='egg'?'pet_egg_orders':'season_pass_orders';
  const{data:order,error:readError}=await db.from(table).select('*').eq('id',id).maybeSingle();
  if(readError||!order)throw readError||new Error('Order not found.');
  const fn=kind==='deposit'?'confirm_wallet_deposit':kind==='egg'?'confirm_pet_egg_order':'confirm_season_pass_order',args=kind==='deposit'?{p_deposit_id:id,p_tx_hash:txHash,p_amount_nano:amountNano}:{p_order_id:id,p_tx_hash:txHash,p_amount_nano:amountNano};
  const{error}=await db.rpc(fn,args);if(error)throw error;
  const source=kind==='deposit'?'fc_purchase':kind==='egg'?'egg':'season_pass',amount=Number(order.amount_ton??order.price_ton);
  const revenue=await db.rpc('pool_record_revenue',{p_user_id:order.user_id,p_source_type:source,p_source_id:String(id),p_amount_ton:amount});if(revenue.error)throw revenue.error;
  if(kind!=='deposit'){const points=await db.rpc('award_pool_points',{p_user_id:order.user_id,p_activity:kind==='egg'?'egg_purchase':'season_pass_purchase',p_source_id:String(id)});if(points.error)throw points.error}
  return res.status(200).json({ok:true});
 }catch(error){return res.status(400).json({error:error instanceof Error?error.message:'Confirmation failed.'})}
}
