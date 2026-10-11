# Architecture Rules

- Queue credited/paid notices through private triggers and atomic secret-authenticated claims; hold ambiguous sends for review, never change balances or enable financial workers.
- Validate bot secrets; tutorials once by sender language, missing media never consumes claims, uncertain sends held. Consent once; respect refusal. Channel rewards need fresh membership and private atomic claims.

- Use gameAssets/navalMaterialArt and semantic CSS; only official materials carry balances; art never alters gameplay.
- Enforce retired creature rarities at database writes and reward-rate settings, deleting their catalogs and owned assets rather than downgrading them; retain legacy schema compatibility and payment replay records so hidden or admin paths cannot recreate retired creatures.
- Keep crew management in CrewDeck with ship-scene selection and semantic crew tokens; map existing archetypes to cosmetic pirate roles, keep XP read-only and equipment server-owned, and omit fusion/inventory navigation so the redesign cannot invent progression or privileges.
- Align the Clan Hall hotspot with the village background's centered cover geometry so building taps stay accurate across viewport sizes without a separate card.
- Isolate crew recruitment presentation in `RecruitCrewView`, passing prices, odds and payment callbacks from the existing shop so visual changes cannot change purchase rules.
- Normalize legacy creature image URLs through `voyageArtReplacement` at the game API response boundary; only artwork fields may change, preserving server-owned gameplay and ownership.
- Keep display branding separate from persistent identifiers, Telegram handles, mission hashtags and payment memos so rebranding cannot break sessions, rewards or transfers.
- Keep profile art in gameAssets and semantic profile CSS; container-responsive character/journal layouts keep Telegram readable. Preserve server-owned profile, pass and channel-reward callbacks.
- MarketPulseView is read-only; label illustrations, never infer global sales from personal history.
- Scope community-pool theming to `seas-community` and semantic community tokens so all nested event views share presentation without changing game rules.
- Keep Grand Line in a lightweight bitmap canvas with ship-relative camera and deterministic streaming shared with service-only collision. Use mirrored water-only art and cached feathered islands; cosmetic sizes never move official docks/collisions. Show only real players. NavalMiniMap is read-only, north-up and shares approved poses/art; zoom never steers. Clear joystick on release/cancel/focus loss; dock through Realm callbacks. Closing never waits for heartbeat or settles combat.
- Keep naval poses/settlement behind Telegram-authenticated Realm RPCs; interpolate without prediction, holding approved poses offline. Drain queued input after requests; count RTT in polling cadence to avoid mobile stalls. Never postpone urgent sends. Disable native swipes only while sailing. Offline grants no rewards. Loot needs sources, rates, caps and materials; cosmetics never alter stats.
- Keep islands in R3F: bounded fixed-step Rapier in one frame driver, smoothed actor/camera, shared ropes and bitmap colliders prevent stalled-frame catch-up. Preserve floor, pier, gender, extraction and atomic maps. Ocean painting shares navigation loop; stable Telegram viewport and measured adaptive effects never change speed or approved poses.
- Share harbor waypoints and Rapier docking; sweep character steps against bitmap coastlines and pier/boarding bounds, restoring invalid poses to last safe ground so jumps/dodges cannot enter water or change sailing/rewards.
- Gate game API and reconciliation by server reset; reject pre-epoch transactions to avoid resurrected balances.
- Gate launch server-side; only signed super-admin bypasses it. Lazy-mount after mobile Telegram auth; device signals aren't attestation. Bind inviter atomically from signed data/bot; rank verified arrivals; no prelaunch referral rewards.

- Keep PvP presentation scoped to `seas-duels`, with artwork in `gameAssets.ts`; preserve the existing server-owned teams, tickets and battle callbacks.
- Keep PirateActionArena grounded with proportional enemies and shared crew portraits. Attack variants share the official callback/cooldown; empty teams open equipment. Show damage/counterattacks only from confirmed state, never cosmetic effects.
- Present egg catalogs as mysterious chests via gameAssets and MascotChestCard; preserve egg IDs, purchases, odds and settlement so theming cannot alter the economy.
- Keep season-pass presentation in SeasonVoyageView with shared art and semantic tokens; preserve official reward titles in details and server-owned prices, claims and reward types so art cannot promise nonexistent ship/map utility.
- Keep retired token/offer presentation separate from settlement and ownership for replay safety.
- Translate literals through LanguageContext and locale catalogs; never mutate DOM text or persistent IDs.
- ReferralDeckView preserves server links, rates and earnings.

- Scope Grand Fleet presentation to semantic fleet tokens and shared gameAssets; preserve clan IDs, membership and anti-hopping. Leader bonuses run only inside atomic gameplay settlement with private idempotent records; explicit source allowlists exclude payments, transfers and recursive bonus income.
