# Architecture Rules

- Keep the pirate presentation centralized in semantic CSS tokens and `gameAssets.ts`; gameplay logic and page structure must remain theme-independent.
- Align the Clan Hall hotspot with the village background's centered cover geometry so building taps stay accurate across viewport sizes without a separate card.
- Isolate crew recruitment presentation in `RecruitCrewView`, passing prices, odds and payment callbacks from the existing shop so visual changes cannot change purchase rules.
- Normalize legacy creature image URLs through `voyageArtReplacement` at the game API response boundary; only artwork fields may change, preserving server-owned gameplay and ownership.
- Keep display branding separate from persistent identifiers, Telegram handles, mission hashtags and payment memos so rebranding cannot break sessions, rewards or transfers.
- Keep profile artwork and styles in `gameAssets.ts` and semantic profile CSS tokens; preserve server-owned profile, pass and channel-reward callbacks when changing presentation.
- Keep market analytics read-only in `MarketPulseView`; explicitly label illustrative data and never derive global sales or buyer identities from personal market history.
- Scope community-pool theming to `seas-community` and semantic community tokens so all nested event views share presentation without changing game rules.
- Keep Grand Line sailing and discoveries in a client-only canvas presentation with pointer-captured joystick input cleared on release, cancellation or focus loss; dock into existing Realm callbacks for authoritative progression and rewards so ocean movement cannot change the economy.
- Keep island terrain and walking client-only in IslandExploration; render only server-available Realm nodes as rewarding encounters and extract through existing callbacks before boarding so physical exploration cannot mint rewards. Profile character selection is a per-player local cosmetic preference shared with island rendering, not a gameplay privilege.
- Gate game API and deposit reconciliation with the server-owned reset state; reject pre-epoch blockchain transactions after a reset to prevent old financial activity from recreating balances.

- Keep PvP presentation scoped to `seas-duels`, with artwork in `gameAssets.ts`; preserve the existing server-owned teams, tickets and battle callbacks.
- Present mascot egg catalogs as mysterious chests through `gameAssets.ts` and `MascotChestCard`; keep egg IDs, purchase actions, odds and settlement unchanged so the nautical theme cannot alter the economy.
