# Architecture Rules

- Queue credited/paid notices through private triggers and atomic secret-authenticated claims; hold ambiguous sends for review, never change balances or enable financial workers.
- Validate game-bot webhook secrets and reply inline to private starts; native message consent is requested once per session, honoring refusal without affecting gameplay.

- Keep the pirate presentation centralized in semantic CSS tokens and `gameAssets.ts`; gameplay logic and page structure must remain theme-independent.
- Enforce retired creature rarities at database writes and reward-rate settings, deleting their catalogs and owned assets rather than downgrading them; retain legacy schema compatibility and payment replay records so hidden or admin paths cannot recreate retired creatures.
- Keep crew management in CrewDeck with ship-scene selection and semantic crew tokens; map existing archetypes to cosmetic pirate roles, keep XP read-only and equipment server-owned, and omit fusion/inventory navigation so the redesign cannot invent progression or privileges.
- Align the Clan Hall hotspot with the village background's centered cover geometry so building taps stay accurate across viewport sizes without a separate card.
- Isolate crew recruitment presentation in `RecruitCrewView`, passing prices, odds and payment callbacks from the existing shop so visual changes cannot change purchase rules.
- Normalize legacy creature image URLs through `voyageArtReplacement` at the game API response boundary; only artwork fields may change, preserving server-owned gameplay and ownership.
- Keep display branding separate from persistent identifiers, Telegram handles, mission hashtags and payment memos so rebranding cannot break sessions, rewards or transfers.
- Keep profile artwork and styles in `gameAssets.ts` and semantic profile CSS tokens, using container-responsive character/journal layouts so the Telegram panel stays readable; preserve server-owned profile, pass and channel-reward callbacks when changing presentation.
- Keep market analytics read-only in `MarketPulseView`; explicitly label illustrative data and never derive global sales or buyer identities from personal market history.
- Scope community-pool theming to `seas-community` and semantic community tokens so all nested event views share presentation without changing game rules.
- Keep Grand Line sailing in a lightweight illustrated bitmap canvas with a ship-relative camera and bounded deterministic region streaming shared with the service-only naval collision function; clear pointer-captured joystick input on release, cancellation or focus loss and dock into existing Realm callbacks so continuous navigation cannot change progression or rewards. Closing the view must not depend on heartbeat latency or settle a battle.
- Keep naval positions and settlement behind Telegram-authenticated Realm RPCs; interpolate approved poses without prediction. Queue brief joystick gestures and release between polls so input is not lost. Offline sailing grants no rewards. Loot needs configured sources, rates, caps and materials; cosmetics never alter stats.
- Keep islands client-only in React Three Fiber: interpolated orthographic follow camera, memoized scene without shadow passes, reusable ropes and batched hidden Rapier footprints aligned to each bitmap. Preserve level floor and collider-only pier. Replay official Realm results and extract before boarding so cosmetic movement cannot mint rewards. Profile gender is cosmetic.
- Derive harbor ship, pier, gangway and player waypoints from shared world coordinates; advance docking on the Rapier timestep and carry the onboard player with the ship so presentation cannot drift into intersecting geometry or change authoritative sailing rules.
- Gate game API and deposit reconciliation with the server-owned reset state; reject pre-epoch blockchain transactions after a reset to prevent old financial activity from recreating balances.

- Keep PvP presentation scoped to `seas-duels`, with artwork in `gameAssets.ts`; preserve the existing server-owned teams, tickets and battle callbacks.
- Keep PirateActionArena grounded with proportional enemies and gameAssets artwork; selected crew and portraits share grounded voyage identities, defaulting to the first equipped slot. Never use airborne art. Motion is cosmetic; official callbacks own combat. Unsupported powers stay locked.
- Present mascot egg catalogs as mysterious chests through `gameAssets.ts` and `MascotChestCard`; keep egg IDs, purchase actions, odds and settlement unchanged so the nautical theme cannot alter the economy.
- Isolate season-pass presentation in SeasonVoyageView with shared artwork and semantic season tokens; keep official reward titles in details and all prices, claims and delivered reward types server-owned so nautical images cannot promise nonexistent ship or treasure-map utility.
- Hide retired offer items through a shared presentation predicate without deleting ownership or settlement records so historical payments remain replay-safe.
