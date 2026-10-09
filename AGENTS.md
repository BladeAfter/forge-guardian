# Architecture Rules

- Keep the pirate presentation centralized in semantic CSS tokens and `gameAssets.ts`; gameplay logic and page structure must remain theme-independent.
- Isolate crew recruitment presentation in `RecruitCrewView`, passing prices, odds and payment callbacks from the existing shop so visual changes cannot change purchase rules.
- Normalize legacy creature image URLs through `voyageArtReplacement` at the game API response boundary; only artwork fields may change, preserving server-owned gameplay and ownership.