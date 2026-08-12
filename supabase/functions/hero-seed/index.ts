// One-off seeding function: signs the uploaded hero art and upserts the expansion roster into hero_catalog.
import { createClient } from 'npm:@supabase/supabase-js@2';
import { corsHeaders } from 'npm:@supabase/supabase-js@2/cors';

type Row = { key: string; name: string; rarity: string; cls: string; atk: number; hp: number; power: number };

const ROSTER: Row[] = [{"key":"mx_bramwel","name":"Bramwel","rarity":"common","cls":"warrior","atk":116,"hp":925,"power":2085},{"key":"mx_hodrik","name":"Hodrik","rarity":"common","cls":"tank","atk":97,"hp":1115,"power":2085},{"key":"mx_perrin","name":"Perrin","rarity":"common","cls":"archer","atk":135,"hp":810,"power":2160},{"key":"mx_lisbet","name":"Lisbet","rarity":"common","cls":"support","atk":97,"hp":1035,"power":2005},{"key":"mx_garrick","name":"Garrick","rarity":"common","cls":"warrior","atk":126,"hp":920,"power":2180},{"key":"mx_ordo","name":"Ordo","rarity":"common","cls":"tank","atk":95,"hp":1210,"power":2160},{"key":"mx_fenna","name":"Fenna","rarity":"common","cls":"archer","atk":125,"hp":820,"power":2070},{"key":"mx_nils","name":"Nils","rarity":"common","cls":"assassin","atk":153,"hp":705,"power":2235},{"key":"mx_marra","name":"Marra","rarity":"common","cls":"mage","atk":137,"hp":815,"power":2185},{"key":"mx_dunhold","name":"Dunhold","rarity":"common","cls":"warrior","atk":116,"hp":945,"power":2105},{"key":"mx_tovin","name":"Tovin","rarity":"common","cls":"assassin","atk":150,"hp":735,"power":2235},{"key":"mx_wyla","name":"Wyla","rarity":"common","cls":"support","atk":93,"hp":1035,"power":1965},{"key":"mx_cregan","name":"Cregan","rarity":"common","cls":"tank","atk":95,"hp":1130,"power":2080},{"key":"mx_ilsa","name":"Ilsa","rarity":"common","cls":"mage","atk":139,"hp":810,"power":2200},{"key":"mx_roeder","name":"Roeder","rarity":"common","cls":"archer","atk":125,"hp":795,"power":2045},{"key":"mx_brannoc","name":"Brannoc","rarity":"uncommon","cls":"warrior","atk":172,"hp":1260,"power":2980},{"key":"mx_sigrun","name":"Sigrun","rarity":"uncommon","cls":"tank","atk":137,"hp":1680,"power":3050},{"key":"mx_elowen","name":"Elowen","rarity":"uncommon","cls":"archer","atk":180,"hp":1115,"power":2915},{"key":"mx_thalric","name":"Thalric","rarity":"uncommon","cls":"mage","atk":203,"hp":1120,"power":3150},{"key":"mx_vespera","name":"Vespera","rarity":"uncommon","cls":"assassin","atk":206,"hp":1050,"power":3110},{"key":"mx_aldric","name":"Aldric","rarity":"uncommon","cls":"support","atk":140,"hp":1545,"power":2945},{"key":"mx_morgane","name":"Morgane","rarity":"uncommon","cls":"mage","atk":205,"hp":1110,"power":3160},{"key":"mx_kestrel","name":"Kestrel","rarity":"uncommon","cls":"archer","atk":181,"hp":1195,"power":3005},{"key":"mx_borund","name":"Borund","rarity":"uncommon","cls":"tank","atk":139,"hp":1650,"power":3040},{"key":"mx_ysolde","name":"Ysolde","rarity":"uncommon","cls":"warrior","atk":178,"hp":1290,"power":3070},{"key":"mx_draveth","name":"Draveth","rarity":"rare","cls":"warrior","atk":230,"hp":1650,"power":3950},{"key":"mx_sylvaine","name":"Sylvaine","rarity":"rare","cls":"mage","atk":262,"hp":1395,"power":4015},{"key":"mx_kaldrin","name":"Kaldrin","rarity":"rare","cls":"tank","atk":193,"hp":2005,"power":3935},{"key":"mx_rowena","name":"Rowena","rarity":"rare","cls":"archer","atk":269,"hp":1535,"power":4225},{"key":"mx_zephiel","name":"Zephiel","rarity":"rare","cls":"assassin","atk":303,"hp":1280,"power":4310},{"key":"mx_malakor","name":"Malakor","rarity":"epic","cls":"warrior","atk":354,"hp":2035,"power":5575},{"key":"mx_isolde","name":"Isolde","rarity":"epic","cls":"mage","atk":379,"hp":1810,"power":5600},{"key":"mx_grimhold","name":"Grimhold","rarity":"epic","cls":"tank","atk":287,"hp":2795,"power":5665},{"key":"mx_aurelith","name":"Aurelith","rarity":"epic","cls":"support","atk":269,"hp":2470,"power":5160},{"key":"mx_nyxaris","name":"Nyxaris","rarity":"epic","cls":"assassin","atk":404,"hp":1745,"power":5785},{"key":"mx_valdrasir","name":"Valdrasir","rarity":"legendary","cls":"warrior","atk":475,"hp":2565,"power":7315},{"key":"mx_seraphine","name":"Seraphine","rarity":"legendary","cls":"mage","atk":586,"hp":2495,"power":8355},{"key":"mx_xandrileth","name":"Xandrileth","rarity":"mythic","cls":"mage","atk":774,"hp":2960,"power":10700},{"key":"mx_thaumgar","name":"Thaumgar","rarity":"mythic","cls":"tank","atk":563,"hp":4350,"power":9980},{"key":"mx_vhalorien","name":"Vhalorien","rarity":"mythic","cls":"warrior","atk":686,"hp":3535,"power":10395},{"key":"mx_nocturnyx","name":"Nocturnyx","rarity":"mythic","cls":"assassin","atk":866,"hp":2665,"power":11325},{"key":"mx_aurenya","name":"Aurenya","rarity":"mythic","cls":"support","atk":517,"hp":4160,"power":9330},{"key":"mx_orovandel","name":"Orovandel","rarity":"ancestral","cls":"warrior","atk":874,"hp":4170,"power":12910},{"key":"mx_zarathis","name":"Zarathis","rarity":"ancestral","cls":"mage","atk":985,"hp":3785,"power":13635},{"key":"mx_kroniel","name":"Kroniel","rarity":"ancestral","cls":"tank","atk":682,"hp":5340,"power":12160},{"key":"mx_umbraxis","name":"Umbraxis","rarity":"ancestral","cls":"assassin","atk":1050,"hp":3270,"power":13770},{"key":"mx_elyndra","name":"Elyndra","rarity":"ancestral","cls":"support","atk":638,"hp":5265,"power":11645}];

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
