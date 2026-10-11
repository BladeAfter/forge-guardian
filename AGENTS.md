# Architecture Rules

- Queue credited/paid notices via private triggers and atomic secret-authenticated claims; hold ambiguous sends for review. Never change balances or enable financial workers.
- Validate bot secrets; tutorials once per sender language; missing media retains claims; hold uncertain sends. Consent once; honor refusal. Channel claims: fixed chat/user IDs, bot-admin proof; atomic/private, fail closed.

- Use gameAssets/navalMaterialArt and semantic CSS; art never alters gameplay. Grand Line shares server class art/cached paid cosmetics; server gates by price_paid and blocks bypass. Preserve grants/allocations and PortSideMenus/house callbacks. Upgrades use server level quotes and atomic real wood/nails/rope ledger debits.
- Block retired rarities at database writes/reward rates; delete catalogs and owned assets, never downgrade. Preserve legacy schema/payment replay compatibility; hidden/admin paths must not recreate them.
- CrewDeck uses grounded poses on the deck; roles are cosmetic, XP read-only, equipment server-owned; omit fusion/inventory and invented powers.
- Align Clan Hall hotspot to centered-cover village geometry for accurate taps at every viewport; no separate card.
- Recruitment rolls share advertised effective server odds, never hidden rates; independent draws have no pity. UI preserves prices/payment callbacks.
- Resolve hero art by catalog key via pirateHeroArt across API, deck and arena, never by rarity; enforce catalog rarity on owned writes. Equipment art stays cosmetic.
- Separate display branding from persistent IDs, Telegram handles, mission hashtags and payment memos; preserve sessions, rewards and transfers.
- Profile uses gameAssets, semantic CSS and container-responsive character/journal layouts for Telegram; preserve server-owned profile, pass and channel-reward callbacks.
- MarketPulseView is read-only; label illustrations, never infer global sales from personal history.
- Community-pool and nested event theming use `seas-community` and semantic tokens; preserve game rules.
- Keep Grand Line in a lightweight bitmap canvas with ship-relative camera and deterministic streaming shared with service-only collision. Use mirrored water-only art and cached feathered islands; cosmetic sizes never move official docks/collisions. Show only real players. NavalMiniMap is read-only, north-up and shares approved poses/art; zoom never steers. Clear joystick on release/cancel/focus loss; dock through Realm callbacks. Closing never waits for heartbeat or settles combat.
- Naval poses/settlement require Telegram Realm RPCs; interpolate within speed, never predict. Deduplicate captured pointers/non-passive touch fallback; clear outside releases to avoid stuck inputs. Upright masts; no waterline disks. Retain offline poses; RTT-aware polling, urgent sends. Disable swipes only sailing. Offline grants no rewards. Loot needs sources/rates/caps/materials; cosmetics never alter stats.
- Keep islands in R3F: bounded fixed-step Rapier in one frame driver, smoothed actor/camera, shared ropes and bitmap colliders prevent stalled-frame catch-up. Preserve floor, pier, gender, extraction and atomic maps. Ocean painting shares navigation loop; stable Telegram viewport and measured adaptive effects never change speed or approved poses.
- Share harbor waypoints and Rapier docking; sweep character steps against bitmap coastlines and pier/boarding bounds, restoring invalid poses to last safe ground so jumps/dodges cannot enter water or change sailing/rewards.
- Gate game API and reconciliation by server reset; reject pre-epoch transactions to avoid resurrected balances.
- Gate launch server-side by signed admin/tester IDs; tester access never grants admin. Lazy-mount after mobile Telegram auth; device signals aren't attestation. Bind inviter atomically from signed data/bot; rank verified arrivals; no prelaunch referral rewards.

- Scope PvP to `seas-duels` and `gameAssets.ts`; preserve server-owned teams, tickets and battle callbacks.
- Kraken: six owned slots, no fixed captain; monster after equip, art by cycle key. Server caps hits by max HP; observer preserves manual ticks, auto keeps processor. Variants share cooldown; confirmed damage only.
- Egg catalogs use gameAssets/MascotChestCard mysterious chests; preserve egg IDs, purchases, odds and settlement.
- SeasonVoyageView uses shared art and semantic tokens; preserve official reward titles in details and server-owned prices, claims and reward types. Art cannot promise nonexistent ship/map utility.
- Keep retired token/offer presentation separate from settlement and ownership for replay safety.
- Translate literals through LanguageContext and locale catalogs; never mutate DOM text or persistent IDs.
- ReferralDeckView preserves server links, rates and earnings.

- Scope Grand Fleet to semantic tokens/gameAssets; resolve emblems by stored symbol so choices stay distinct. Preserve IDs, membership and anti-hopping. Leader bonuses use atomic settlement/private idempotent records; source allowlists exclude payments, transfers and recursive bonus income.
