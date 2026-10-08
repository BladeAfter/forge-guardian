// MYTHREON :: one-off broadcast blast (temporary helper).
// Protected by Supabase JWT verification (verify_jwt = true): only service-level callers
// can invoke it. Sends a message via the GAME bot to a chunk of non-banned players.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const GAME_TOKEN = (
  Deno.env.get("TELEGRAM_BOT_TOKEN_GAME") ||
  Deno.env.get("TELEGRAM_GAME_BOT_TOKEN") ||
  ""
).trim();

Deno.serve(async (req) => {
  const url = new URL(req.url);
  const text = String(url.searchParams.get("text") || "");
  const offset = Math.max(0, Number(url.searchParams.get("offset") || 0));
  const limit = Math.min(1000, Math.max(1, Number(url.searchParams.get("limit") || 500)));
  if (!text) return new Response(JSON.stringify({ error: "missing text" }), { status: 400 });
  if (!GAME_TOKEN) return new Response(JSON.stringify({ error: "game bot token not configured" }), { status: 500 });

  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data, error } = await db
    .from("game_players")
    .select("telegram_id")
    .eq("banned", false)
    .order("telegram_id", { ascending: true })
    .range(offset, offset + limit - 1);
  if (error) return new Response(JSON.stringify({ error: error.message }), { status: 500 });

  const rows = data ?? [];
  let sent = 0;
  let failed = 0;
  const failures: Record<string, number> = {};

  const CONCURRENCY = 8;
  for (let i = 0; i < rows.length; i += CONCURRENCY) {
    const batch = rows.slice(i, i + CONCURRENCY);
    await Promise.all(batch.map(async (row) => {
      let lastErr = "";
      for (let attempt = 0; attempt < 4; attempt++) {
        try {
          const r = await fetch(`https://api.telegram.org/bot${GAME_TOKEN}/sendMessage`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ chat_id: row.telegram_id, text }),
          });
          const j = await r.json().catch(() => ({}));
          if (j?.ok) { sent += 1; return; }
          lastErr = String(j?.description ?? `http_${r.status}`);
          if (r.status === 429) {
            const wait = Number(j?.parameters?.retry_after ?? 3);
            await new Promise((res) => setTimeout(res, Math.min(wait, 30) * 1000 + 250));
            continue;
          }
          break; // permanent error (chat not found, blocked, etc.)
        } catch (e) {
          lastErr = `network:${e instanceof Error ? e.message : String(e)}`;
          await new Promise((res) => setTimeout(res, 1000));
        }
      }
      failed += 1;
      failures[lastErr || "unknown"] = (failures[lastErr || "unknown"] || 0) + 1;
    }));
  }

  return new Response(
    JSON.stringify({ ok: true, offset, processed: rows.length, sent, failed, failures }),
    { headers: { "Content-Type": "application/json" } },
  );
});
