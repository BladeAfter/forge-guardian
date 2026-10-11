# Architecture Rules

- Queue credited/paid notices through private triggers and atomic secret-authenticated claims; hold ambiguous sends for review, never change balances or enable financial workers.
- Validate bot secrets; tutorials once by sender language, missing media never consumes claims, uncertain sends held. Consent once; respect refusal. Channel rewards need fresh membership and private atomic claims.

- Use gameAssets/navalMaterialArt and semantic CSS; only official materials carry balances; art never alters gameplay. PortSideMenus shares edge-rail sizing and official callbacks to keep the house accessible.
- Block retired rarities at database writes/reward rates; delete catalogs and owned assets, never downgrade. Preserve legacy schema/payment replay compatibility; hidden/admin paths must not recreate them.
- CrewDeck uses grounded poses on the deck; roles are cosmetic, XP read-only, equipment server-owned; omit fusion/inventory and invented powers.
- Align Clan Hall hotspot to centered-cover village geometry for accurate taps at every viewport; no separate card.
- Recruitment rolls share advertised effective server odds, never hidden rates; independent draws have no pity. UI preserves prices/payment callbacks.
- Normalize creature/equipment art at the API boundary with voyageArtReplacement and pirateEquipmentArt; stable kinds resolve art only, never ownership/stats.
- Separate display branding from persistent IDs, Telegram handles, mission hashtags and payment memos; preserve sessions, rewards and transfers.
- Profile uses gameAssets, semantic CSS and container-responsive character/journal layouts for Telegram; preserve server-owned profile, pass and channel-reward callbacks.
- MarketPulseView is read-only; label illustrations, never infer global sales from personal history.
- Community-pool and nested event theming use `seas-community` and semantic tokens; preserve game rules.
- Keep Grand Line in a lightweight bitmap canvas with ship-relative camera and deterministic streaming shared with service-only collision. Use mirrored water-only art and cached feathered islands; cosmetic sizes never move official docks/collisions. Show only real players. NavalMiniMap is read-only, north-up and shares approved poses/art; zoom never steers. Clear joystick on release/cancel/focus loss; dock through Realm callbacks. Closing never waits for heartbeat or settles combat.
- Keep naval poses/settlement behind Telegram-authenticated Realm RPCs; interpolate without prediction, holding approved poses offline. Drain queued input after requests; count RTT in polling cadence to avoid mobile stalls. Never postpone urgent sends. Disable native swipes only while sailing. Offline grants no rewards. Loot needs sources, rates, caps and materials; cosmetics never alter stats.
- Keep islands in R3F: bounded fixed-step Rapier in one frame driver, smoothed actor/camera, shared ropes and bitmap colliders prevent stalled-frame catch-up. Preserve floor, pier, gender, extraction and atomic maps. Ocean painting shares navigation loop; stable Telegram viewport and measured adaptive effects never change speed or approved poses.
- Share harbor waypoints and Rapier docking; sweep character steps against bitmap coastlines and pier/boarding bounds, restoring invalid poses to last safe ground so jumps/dodges cannot enter water or change sailing/rewards.
- Gate game API and reconciliation by server reset; reject pre-epoch transactions to avoid resurrected balances.
- Gate launch server-side; only signed super-admin bypasses it. Lazy-mount after mobile Telegram auth; device signals aren't attestation. Bind inviter atomically from signed data/bot; rank verified arrivals; no prelaunch referral rewards.

- Keep PvP presentation scoped to `seas-duels`, with artwork in `gameAssets.ts`; preserve the existing server-owned teams, tickets and battle callbacks.
- Keep PirateActionArena grounded with proportional enemies and shared crew portraits. Attack variants share the official callback/cooldown; empty teams open equipment. Show damage/counterattacks only from confirmed state, never cosmetic effects.
- Egg catalogs use gameAssets/MascotChestCard mysterious chests; preserve egg IDs, purchases, odds and settlement.
- SeasonVoyageView uses shared art and semantic tokens; preserve official reward titles in details and server-owned prices, claims and reward types. Art cannot promise nonexistent ship/map utility.
- Keep retired token/offer presentation separate from settlement and ownership for replay safety.
- Translate literals through LanguageContext and locale catalogs; never mutate DOM text or persistent IDs.
- ReferralDeckView preserves server links, rates and earnings.

- Scope Grand Fleet presentation to semantic fleet tokens and shared gameAssets; preserve clan IDs, membership and anti-hopping. Leader bonuses run only inside atomic gameplay settlement with private idempotent records; explicit source allowlists exclude payments, transfers and recursive bonus income.
