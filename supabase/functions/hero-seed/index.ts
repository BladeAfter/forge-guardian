// One-off seeding function: signs the uploaded hero art and upserts the expansion roster into hero_catalog.
import { createClient } from 'npm:@supabase/supabase-js@2';
import { corsHeaders } from 'npm:@supabase/supabase-js@2/cors';

type Row = { key: string; name: string; rarity: string; cls: string; atk: number; hp: number; power: number };

const ROSTER: Row[] = [{"key":"mx_edrin","name":"Edrin","rarity":"common","cls":"warrior","atk":118,"hp":930,"power":2100},{"key":"mx_torvald","name":"Torvald","rarity":"common","cls":"tank","atk":96,"hp":1180,"power":2130},{"key":"mx_pella","name":"Pella","rarity":"common","cls":"archer","atk":132,"hp":805,"power":2135},{"key":"mx_seryn","name":"Seryn","rarity":"common","cls":"support","atk":95,"hp":1050,"power":1990},{"key":"mx_calder","name":"Calder","rarity":"common","cls":"assassin","atk":151,"hp":720,"power":2230},{"key":"mx_ravella","name":"Ravella","rarity":"common","cls":"mage","atk":138,"hp":812,"power":2190},{"key":"mx_hobart","name":"Hobart","rarity":"common","cls":"warrior","atk":124,"hp":905,"power":2150},{"key":"mx_lorwin","name":"Lorwin","rarity":"common","cls":"warrior","atk":115,"hp":950,"power":2105},{"key":"mx_ysra","name":"Ysra","rarity":"common","cls":"archer","atk":127,"hp":800,"power":2065},{"key":"mx_grum","name":"Grum","rarity":"common","cls":"tank","atk":94,"hp":1205,"power":2150},{"key":"mx_odwin","name":"Odwin","rarity":"common","cls":"warrior","atk":120,"hp":935,"power":2120},{"key":"mx_talla","name":"Talla","rarity":"common","cls":"support","atk":92,"hp":1040,"power":1960},{"key":"mx_brek","name":"Brek","rarity":"common","cls":"assassin","atk":154,"hp":700,"power":2240},{"key":"mx_nemra","name":"Nemra","rarity":"common","cls":"mage","atk":140,"hp":805,"power":2205},{"key":"mx_fost","name":"Fost","rarity":"common","cls":"archer","atk":134,"hp":790,"power":2120},{"key":"mx_veyran","name":"Veyran","rarity":"uncommon","cls":"warrior","atk":175,"hp":1275,"power":3020},{"key":"mx_astrilde","name":"Astrilde","rarity":"uncommon","cls":"tank","atk":138,"hp":1690,"power":3065},{"key":"mx_caelith","name":"Caelith","rarity":"uncommon","cls":"archer","atk":183,"hp":1130,"power":2960},{"key":"mx_zorvane","name":"Zorvane","rarity":"uncommon","cls":"mage","atk":206,"hp":1115,"power":3170},{"key":"mx_nyshara","name":"Nyshara","rarity":"uncommon","cls":"assassin","atk":208,"hp":1045,"power":3125},{"key":"mx_ordwen","name":"Ordwen","rarity":"uncommon","cls":"support","atk":141,"hp":1560,"power":2965},{"key":"mx_krellan","name":"Krellan","rarity":"uncommon","cls":"warrior","atk":180,"hp":1250,"power":3040},{"key":"mx_seteran","name":"Seteran","rarity":"uncommon","cls":"tank","atk":136,"hp":1720,"power":3080},{"key":"mx_lunareth","name":"Lunareth","rarity":"uncommon","cls":"mage","atk":204,"hp":1125,"power":3155},{"key":"mx_darvek","name":"Darvek","rarity":"uncommon","cls":"archer","atk":186,"hp":1105,"power":2980},{"key":"mx_bardrum","name":"Bardrum","rarity":"uncommon","cls":"tank","atk":140,"hp":1665,"power":3055},{"key":"mx_vessren","name":"Vessren","rarity":"uncommon","cls":"support","atk":143,"hp":1530,"power":2950},{"key":"mx_isavelle","name":"Isavelle","rarity":"uncommon","cls":"assassin","atk":210,"hp":1030,"power":3135},{"key":"mx_gwynhael","name":"Gwynhael","rarity":"uncommon","cls":"warrior","atk":177,"hp":1295,"power":3075},{"key":"mx_thornelle","name":"Thornelle","rarity":"uncommon","cls":"support","atk":145,"hp":1545,"power":2990}];

const RARITY_SORT: Record<string, number> = { common: 100, uncommon: 200, rare: 300, epic: 400, legendary: 500, mythic: 600, ancestral: 700 };

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  const token = req.headers.get('x-seed-token') ?? '';
  const expected = Deno.env.get('TELEGRAM_GAME_BOT_TOKEN') ?? '';
  if (!expected || token !== expected) {
    return new Response(JSON.stringify({ error: 'forbidden' }), { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  }

  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  const rows: Record<string, unknown>[] = [];
  const failed: string[] = [];
  for (const hero of ROSTER) {
    const path = `heroes/${hero.key}-v1.jpg`;
    const signed = await db.storage.from('hero-images').createSignedUrl(path, 60 * 60 * 24 * 365 * 10);
    if (signed.error || !signed.data?.signedUrl) { failed.push(hero.key); continue; }
    rows.push({
      hero_key: hero.key, name: hero.name, rarity: hero.rarity, hero_class: hero.cls,
      base_atk: hero.atk, base_hp: hero.hp, power: hero.power,
      image: signed.data.signedUrl, enabled: true, in_shop: false, drop_weight: 1,
      fusion_pool_enabled: true, sort_order: RARITY_SORT[hero.rarity] ?? 100,
    });
  }
  const up = await db.from('hero_catalog').upsert(rows, { onConflict: 'hero_key' }).select('hero_key');
  if (up.error) {
    return new Response(JSON.stringify({ error: up.error.message, failed }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  }
  return new Response(JSON.stringify({ upserted: up.data?.length ?? 0, failed }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
});
