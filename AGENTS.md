# Architecture Rules

- Keep the pirate presentation centralized in semantic CSS tokens and `gameAssets.ts`; gameplay logic and page structure must remain theme-independent.
- Align the Clan Hall hotspot with the village background's centered cover geometry so building taps stay accurate across viewport sizes without a separate card.
- Isolate crew recruitment presentation in `RecruitCrewView`, passing prices, odds and payment callbacks from the existing shop so visual changes cannot change purchase rules.
- Normalize legacy creature image URLs through `voyageArtReplacement` at the game API response boundary; only artwork fields may change, preserving server-owned gameplay and ownership.
- Keep display branding separate from persistent identifiers, Telegram handles, mission hashtags and payment memos so rebranding cannot break sessions, rewards or transfers.
- Keep profile artwork and styles in `gameAssets.ts` and semantic profile CSS tokens; preserve server-owned profile, pass and channel-reward callbacks when changing presentation.
