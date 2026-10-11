type Ctx={adminId:number;chatId:number;messageId?:number};
type Dependencies={rpc:(name:string,args:Record<string,unknown>)=>Promise<any>;edit:(ctx:Ctx,text:string,markup?:unknown)=>Promise<unknown>;send:(ctx:Ctx,text:string,markup?:unknown)=>Promise<unknown>;ask:(ctx:Ctx,key:string,text:string)=>Promise<unknown>;esc:(text:unknown)=>string;kb:(rows:{t:string;d:string}[][])=>unknown};
export function createOceanChestAdmin({rpc,edit,send,ask,esc,kb}:Dependencies) {
 const panel=async(ctx:Ctx)=>{
  const s=await rpc('ocean_chest_admin',{p_admin:ctx.adminId,p_patch:null});
  const b=s.budget;const cfg=s.config;
  return edit(ctx,`🌊 <b>BAÚS DO OCEANO</b>\n${cfg.enabled?'🟢 Ativo':'🔴 Suspenso'} · ${s.active} baús\n\nFinanciado: ${b.funded} TON\nReservado: ${b.reserved} TON\nGanho pendente: ${b.earned} TON\nPago: ${b.paid} TON\nDisponível: ${b.available} TON\nEm análise: ${s.pending} · Falhas: ${s.failed}\n\nSem verba comprovada, a tabela TON fica suspensa. Nenhum saldo ou pagamento automático é ativado.\n\n<pre>${esc(JSON.stringify(cfg,null,2))}</pre>`,kb([[{t:cfg.enabled?'⏸ Suspender':'▶️ Retomar',d:`oc:toggle:${cfg.enabled?0:1}`},{t:'🔄 Atualizar',d:'oc:hub'}],[{t:'⚙️ Configurar',d:'oc:config'},{t:'🎲 Probabilidades',d:'oc:odds'}],[{t:'🌎 Regiões / eventos',d:'oc:config'},{t:'🪵 Equipamentos → materiais',d:'oc:materials'}],[{t:'🏠 Menu',d:'home'}]]));
 };
 const callback=async(ctx:Ctx,args:string[])=>{
  if(args[0]==='toggle')await rpc('ocean_chest_admin',{p_admin:ctx.adminId,p_patch:{enabled:args[1]==='1'}});
  if(args[0]==='config')return ask(ctx,'oceanconfig','Envie alterações em JSON. Campos: maxActive, minInterval, maxInterval, lifetime, minDistance, collectRadius, cooldown, dailyClaims, dailyTon, monthlyTon, regions, eventStartsAt, eventEndsAt. Limites não criam verba.');
  if(args[0]==='odds')return ask(ctx,'oceanodds','Envie JSON com odds e/ou fallback. Cada tabela soma 100%. Exemplo de formato: {"odds":[{"kind":"material","weight":40},{"kind":"equipment","weight":25},{"kind":"mascot","weight":12},{"kind":"ton","amount":0.001,"weight":12},{"kind":"ton","amount":0.01,"weight":6},{"kind":"ton","amount":0.05,"weight":3},{"kind":"ton","amount":0.1,"weight":1.8},{"kind":"ton","amount":0.5,"weight":0.2}]}. Fallback não pode incluir TON.');
  if(args[0]==='materials')return ask(ctx,'oceanmaterials','Envie cotações em JSON por raridade. Ex.: {"common":{"magic_wood":1,"nails":1,"rope":1}}. Recuperar materiais consome definitivamente o equipamento e não pode ser repetido.');
  return panel(ctx);
 };
 const prompt=async(ctx:Ctx,key:string,text:string)=>{
  try { const value=JSON.parse(text);await rpc('ocean_chest_admin',{p_admin:ctx.adminId,p_patch:key==='oceanmaterials'?{equipmentMaterials:value}:value}); }
  catch(e){throw new Error(`KEEP_SESSION::⚠️ Configuração rejeitada: ${esc(e instanceof Error?e.message:'JSON inválido')}`);}
  await send(ctx,'✅ Configuração dos baús salva.');return panel({...ctx,messageId:undefined});
 };
 return {panel,callback,prompt};
}