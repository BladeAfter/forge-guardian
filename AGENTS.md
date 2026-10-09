# Architecture Rules

- Keep the pirate presentation centralized in semantic CSS tokens and `gameAssets.ts`; gameplay logic and page structure must remain theme-independent.
- Enforce retired creature rarities at database writes and reward-rate settings, deleting their catalogs and owned assets rather than downgrading them; retain legacy schema compatibility and payment replay records so hidden or admin paths cannot recreate retired creatures.
- Keep crew management in CrewDeck with ship-scene selection and semantic crew tokens; map existing archetypes to cosmetic pirate roles, keep XP read-only and equipment server-owned, and omit fusion/inventory navigation so the redesign cannot invent progression or privileges.
- Align the Clan Hall hotspot with the village background's centered cover geometry so building taps stay accurate across viewport sizes without a separate card.
- Isolate crew recruitment presentation in `RecruitCrewView`, passing prices, odds and payment callbacks from the existing shop so visual changes cannot change purchase rules.
- Normalize legacy creature image URLs through `voyageArtReplacement` at the game API response boundary; only artwork fields may change, preserving server-owned gameplay and ownership.
- Keep display branding separate from persistent identifiers, Telegram handles, mission hashtags and payment memos so rebranding cannot break sessions, rewards or transfers.
- Keep profile artwork and styles in `gameAssets.ts` and semantic profile CSS tokens; preserve server-owned profile, pass and channel-reward callbacks when changing presentation.
- Keep market analytics read-only in `MarketPulseView`; explicitly label illustrative data and never derive global sales or buyer identities from personal market history.
- Scope community-pool theming to `seas-community` and semantic community tokens so all nested event views share presentation without changing game rules.
- Keep Grand Line sailing and discoveries in a client-only canvas presentation with pointer-captured joystick input cleared on release, cancellation or focus loss; dock into existing Realm callbacks for authoritative progression and rewards so ocean movement cannot change the economy.
- Keep naval multiplayer positions, damage, cooldowns, repairs and settlement behind Telegram-authenticated Realm RPCs; polling publishes server-approved ships only, while unavailable networking falls back to explicitly local navigation without rewards. Never enable loot battles until stake percentage, source, caps and allowlisted ordinary materials are explicitly configured; cosmetic models cannot alter combat stats.
- Keep island terrain and walking client-only in IslandExploration; render only server-available Realm nodes as rewarding encounters and extract through existing callbacks before boarding so physical exploration cannot mint rewards. Profile character selection is a per-player local cosmetic preference shared with island rendering, not a gameplay privilege.
- Gate game API and deposit reconciliation with the server-owned reset state; reject pre-epoch blockchain transactions after a reset to prevent old financial activity from recreating balances.

- Keep PvP presentation scoped to `seas-duels`, with artwork in `gameAssets.ts`; preserve the existing server-owned teams, tickets and battle callbacks.
- Keep global boss presentation in PirateActionArena with semantic action tokens and gameAssets artwork; movement, dodge and phase effects are cosmetic, while only official callbacks change damage, HP and rewards. Unsupported powers stay locked to avoid inventing privileges.
- Present mascot egg catalogs as mysterious chests through `gameAssets.ts` and `MascotChestCard`; keep egg IDs, purchase actions, odds and settlement unchanged so the nautical theme cannot alter the economy.
