# Architecture Rules

- Queue credited/paid notices through private triggers and atomic secret-authenticated claims; hold ambiguous sends for review, never change balances or enable financial workers.
- Validate bot secrets; tutorials once by sender language, missing media never consumes claims, uncertain sends held. Consent once; respect refusal. Channel rewards need fresh membership and private atomic claims.

- Keep pirate artwork in gameAssets and semantic CSS; theming never changes gameplay.
- Enforce retired creature rarities at database writes and reward-rate settings, deleting their catalogs and owned assets rather than downgrading them; retain legacy schema compatibility and payment replay records so hidden or admin paths cannot recreate retired creatures.
- Keep crew management in CrewDeck with ship-scene selection and semantic crew tokens; map existing archetypes to cosmetic pirate roles, keep XP read-only and equipment server-owned, and omit fusion/inventory navigation so the redesign cannot invent progression or privileges.
- Align the Clan Hall hotspot with the village background's centered cover geometry so building taps stay accurate across viewport sizes without a separate card.
- Isolate crew recruitment presentation in `RecruitCrewView`, passing prices, odds and payment callbacks from the existing shop so visual changes cannot change purchase rules.
- Normalize legacy creature image URLs through `voyageArtReplacement` at the game API response boundary; only artwork fields may change, preserving server-owned gameplay and ownership.
- Keep display branding separate from persistent identifiers, Telegram handles, mission hashtags and payment memos so rebranding cannot break sessions, rewards or transfers.
- Keep profile artwork and styles in `gameAssets.ts` and semantic profile CSS tokens, using container-responsive character/journal layouts so the Telegram panel stays readable; preserve server-owned profile, pass and channel-reward callbacks when changing presentation.
- Keep MarketPulseView read-only; label illustrative data, never infer global sales from personal history.
- Scope community-pool theming to `seas-community` and semantic community tokens so all nested event views share presentation without changing game rules.
- Keep Grand Line in a lightweight bitmap canvas with ship-relative camera and deterministic streaming shared with service-only collision. Use mirrored water-only art and cached feathered islands; cosmetic sizes never move official docks/collisions. Show only real players. NavalMiniMap is read-only, north-up and shares approved poses/art; zoom never steers. Clear joystick on release/cancel/focus loss; dock through Realm callbacks. Closing never waits for heartbeat or settles combat.
- Keep naval poses/settlement behind Telegram-authenticated Realm RPCs; interpolate without prediction, holding approved poses offline. Queue joystick/release without postponing urgent sends; disable native Telegram swipes only while sailing to prevent stolen input. Offline grants no rewards. Loot needs sources, rates, caps and materials; cosmetics never alter stats.
- Keep islands client-only in React Three Fiber: interpolated orthographic follow camera, memoized scene without shadow passes, reusable ropes and batched hidden Rapier footprints aligned to each bitmap. Preserve level floor and collider-only pier. Replay official Realm results and extract before boarding so cosmetic movement cannot mint rewards. Profile gender is cosmetic.
- Share harbor waypoints and Rapier docking; sweep character steps against bitmap coastlines and pier/boarding bounds, restoring invalid poses to last safe ground so jumps/dodges cannot enter water or change sailing/rewards.
- Gate game API and reconciliation by server reset; reject pre-epoch transactions to avoid resurrected balances.
- Gate launch server-side; only signed super-admin bypasses it. Lazy-mount after mobile Telegram auth; device signals aren't attestation. Bind inviter atomically from signed data/bot; rank verified arrivals; no prelaunch referral rewards.

- Keep PvP presentation scoped to `seas-duels`, with artwork in `gameAssets.ts`; preserve the existing server-owned teams, tickets and battle callbacks.
- Keep PirateActionArena grounded with proportional enemies and gameAssets artwork; selected crew and portraits share grounded voyage identities, defaulting to the first equipped slot. Never use airborne art. Motion is cosmetic; official callbacks own combat. Unsupported powers stay locked.
- Present mascot egg catalogs as mysterious chests through `gameAssets.ts` and `MascotChestCard`; keep egg IDs, purchase actions, odds and settlement unchanged so the nautical theme cannot alter the economy.
- Isolate season-pass presentation in SeasonVoyageView with shared artwork and semantic season tokens; keep official reward titles in details and all prices, claims and delivered reward types server-owned so nautical images cannot promise nonexistent ship or treasure-map utility.
- Hide retired offers without deleting settlement/ownership to preserve replay safety.
