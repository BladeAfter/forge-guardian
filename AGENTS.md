# Architecture Rules

- Keep the pirate presentation centralized in semantic CSS tokens and `gameAssets.ts`; gameplay logic and page structure must remain theme-independent.
- Isolate crew recruitment presentation in `RecruitCrewView`, passing prices, odds and payment callbacks from the existing shop so visual changes cannot change purchase rules.