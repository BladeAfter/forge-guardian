export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.15"
  }
  public: {
    Tables: {
      boss_combats: {
        Row: {
          boss_attack: number
          boss_attack_interval_seconds: number
          boss_current_hp: number
          boss_id: string | null
          boss_last_attack_at: string
          boss_level: number
          boss_max_hp: number
          boss_name: string
          boss_next_attack_at: string
          created_at: string
          defeated_at: string | null
          id: string
          last_processed_at: string
          next_hero_attack_at: string
          pet_next_skill_at: string | null
          reward_amount: number
          reward_claimed_at: string | null
          started_at: string
          status: string
          team_change_available_at: string | null
          total_damage_dealt: number
          updated_at: string
          user_id: string
        }
        Insert: {
          boss_attack?: number
          boss_attack_interval_seconds?: number
          boss_current_hp?: number
          boss_id?: string | null
          boss_last_attack_at?: string
          boss_level?: number
          boss_max_hp?: number
          boss_name?: string
          boss_next_attack_at?: string
          created_at?: string
          defeated_at?: string | null
          id?: string
          last_processed_at?: string
          next_hero_attack_at?: string
          pet_next_skill_at?: string | null
          reward_amount?: number
          reward_claimed_at?: string | null
          started_at?: string
          status?: string
          team_change_available_at?: string | null
          total_damage_dealt?: number
          updated_at?: string
          user_id: string
        }
        Update: {
          boss_attack?: number
          boss_attack_interval_seconds?: number
          boss_current_hp?: number
          boss_id?: string | null
          boss_last_attack_at?: string
          boss_level?: number
          boss_max_hp?: number
          boss_name?: string
          boss_next_attack_at?: string
          created_at?: string
          defeated_at?: string | null
          id?: string
          last_processed_at?: string
          next_hero_attack_at?: string
          pet_next_skill_at?: string | null
          reward_amount?: number
          reward_claimed_at?: string | null
          started_at?: string
          status?: string
          team_change_available_at?: string | null
          total_damage_dealt?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "boss_combats_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      boss_reward_transactions: {
        Row: {
          amount: number
          combat_id: string
          created_at: string
          currency: string
          id: string
          idempotency_key: string
          user_id: string
        }
        Insert: {
          amount: number
          combat_id: string
          created_at?: string
          currency?: string
          id?: string
          idempotency_key: string
          user_id: string
        }
        Update: {
          amount?: number
          combat_id?: string
          created_at?: string
          currency?: string
          id?: string
          idempotency_key?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "boss_reward_transactions_combat_id_fkey"
            columns: ["combat_id"]
            isOneToOne: false
            referencedRelation: "boss_combats"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "boss_reward_transactions_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      calendar_chest_open_history: {
        Row: {
          created_at: string
          id: string
          idempotency_key: string
          inventory_item_id: string
          result_hero_id: string
          result_rarity: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          idempotency_key: string
          inventory_item_id: string
          result_hero_id: string
          result_rarity: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          idempotency_key?: string
          inventory_item_id?: string
          result_hero_id?: string
          result_rarity?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "calendar_chest_open_history_inventory_item_id_fkey"
            columns: ["inventory_item_id"]
            isOneToOne: false
            referencedRelation: "player_inventory"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "calendar_chest_open_history_result_hero_id_fkey"
            columns: ["result_hero_id"]
            isOneToOne: false
            referencedRelation: "player_heroes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "calendar_chest_open_history_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      calendar_reward_config: {
        Row: {
          amount_fc: number
          day: number
          enabled: boolean
          item_code: string | null
          rarity_rates: Json | null
          reward_type: string
          subtitle: string | null
          title: string
          updated_at: string
        }
        Insert: {
          amount_fc?: number
          day: number
          enabled?: boolean
          item_code?: string | null
          rarity_rates?: Json | null
          reward_type: string
          subtitle?: string | null
          title: string
          updated_at?: string
        }
        Update: {
          amount_fc?: number
          day?: number
          enabled?: boolean
          item_code?: string | null
          rarity_rates?: Json | null
          reward_type?: string
          subtitle?: string | null
          title?: string
          updated_at?: string
        }
        Relationships: []
      }
      calendar_reward_history: {
        Row: {
          amount_fc: number
          created_at: string
          day: number
          id: string
          idempotency_key: string
          result_data: Json | null
          reward_code: string | null
          reward_type: string
          user_id: string
        }
        Insert: {
          amount_fc?: number
          created_at?: string
          day: number
          id?: string
          idempotency_key: string
          result_data?: Json | null
          reward_code?: string | null
          reward_type: string
          user_id: string
        }
        Update: {
          amount_fc?: number
          created_at?: string
          day?: number
          id?: string
          idempotency_key?: string
          result_data?: Json | null
          reward_code?: string | null
          reward_type?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "calendar_reward_history_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      daily_calendar_claims: {
        Row: {
          amount_fc: number
          calendar_cycle: string
          claimed_at: string
          created_at: string
          day: number
          id: string
          idempotency_key: string
          reward_code: string | null
          reward_type: string
          user_id: string
        }
        Insert: {
          amount_fc?: number
          calendar_cycle: string
          claimed_at?: string
          created_at?: string
          day: number
          id?: string
          idempotency_key: string
          reward_code?: string | null
          reward_type: string
          user_id: string
        }
        Update: {
          amount_fc?: number
          calendar_cycle?: string
          claimed_at?: string
          created_at?: string
          day?: number
          id?: string
          idempotency_key?: string
          reward_code?: string | null
          reward_type?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "daily_calendar_claims_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      economy_settings: {
        Row: {
          key: string
          updated_at: string
          value_numeric: number
        }
        Insert: {
          key: string
          updated_at?: string
          value_numeric: number
        }
        Update: {
          key?: string
          updated_at?: string
          value_numeric?: number
        }
        Relationships: []
      }
      game_players: {
        Row: {
          avatar_url: string | null
          boss_defeats: number
          created_at: string
          display_name: string | null
          first_name: string | null
          forge_coins: number
          id: string
          last_name: string | null
          last_seen_at: string
          pvp_banned: boolean
          pvp_losses: number
          pvp_tickets: number
          pvp_trophies: number
          pvp_wins: number
          telegram_id: number
          updated_at: string
          username: string | null
        }
        Insert: {
          avatar_url?: string | null
          boss_defeats?: number
          created_at?: string
          display_name?: string | null
          first_name?: string | null
          forge_coins?: number
          id?: string
          last_name?: string | null
          last_seen_at?: string
          pvp_banned?: boolean
          pvp_losses?: number
          pvp_tickets?: number
          pvp_trophies?: number
          pvp_wins?: number
          telegram_id: number
          updated_at?: string
          username?: string | null
        }
        Update: {
          avatar_url?: string | null
          boss_defeats?: number
          created_at?: string
          display_name?: string | null
          first_name?: string | null
          forge_coins?: number
          id?: string
          last_name?: string | null
          last_seen_at?: string
          pvp_banned?: boolean
          pvp_losses?: number
          pvp_tickets?: number
          pvp_trophies?: number
          pvp_wins?: number
          telegram_id?: number
          updated_at?: string
          username?: string | null
        }
        Relationships: []
      }
      hero_catalog: {
        Row: {
          enabled: boolean
          hero_key: string
          image: string
          name: string
          rarity: string
        }
        Insert: {
          enabled?: boolean
          hero_key: string
          image: string
          name: string
          rarity: string
        }
        Update: {
          enabled?: boolean
          hero_key?: string
          image?: string
          name?: string
          rarity?: string
        }
        Relationships: []
      }
      hero_combat_state: {
        Row: {
          base_atk: number
          base_hp: number
          combat_id: string
          created_at: string
          current_hp: number
          final_atk: number
          hero_id: string
          id: string
          is_alive: boolean
          knocked_out_at: string | null
          level: number
          max_hp: number
          rarity: string
          revive_at: string | null
          slot: number | null
          updated_at: string
        }
        Insert: {
          base_atk: number
          base_hp: number
          combat_id: string
          created_at?: string
          current_hp: number
          final_atk: number
          hero_id: string
          id?: string
          is_alive?: boolean
          knocked_out_at?: string | null
          level: number
          max_hp: number
          rarity: string
          revive_at?: string | null
          slot?: number | null
          updated_at?: string
        }
        Update: {
          base_atk?: number
          base_hp?: number
          combat_id?: string
          created_at?: string
          current_hp?: number
          final_atk?: number
          hero_id?: string
          id?: string
          is_alive?: boolean
          knocked_out_at?: string | null
          level?: number
          max_hp?: number
          rarity?: string
          revive_at?: string | null
          slot?: number | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "hero_combat_state_combat_id_fkey"
            columns: ["combat_id"]
            isOneToOne: false
            referencedRelation: "boss_combats"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "hero_combat_state_hero_id_fkey"
            columns: ["hero_id"]
            isOneToOne: false
            referencedRelation: "player_heroes"
            referencedColumns: ["id"]
          },
        ]
      }
      pet_egg_orders: {
        Row: {
          amount_nano: string
          created_at: string
          delivered_at: string | null
          egg_id: string
          expires_at: string
          id: string
          idempotency_key: string
          paid_at: string | null
          payment_address: string
          payment_comment: string
          price_ton: number
          status: string
          tx_hash: string | null
          user_id: string
        }
        Insert: {
          amount_nano: string
          created_at?: string
          delivered_at?: string | null
          egg_id: string
          expires_at?: string
          id?: string
          idempotency_key: string
          paid_at?: string | null
          payment_address: string
          payment_comment: string
          price_ton: number
          status?: string
          tx_hash?: string | null
          user_id: string
        }
        Update: {
          amount_nano?: string
          created_at?: string
          delivered_at?: string | null
          egg_id?: string
          expires_at?: string
          id?: string
          idempotency_key?: string
          paid_at?: string | null
          payment_address?: string
          payment_comment?: string
          price_ton?: number
          status?: string
          tx_hash?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "pet_egg_orders_egg_id_fkey"
            columns: ["egg_id"]
            isOneToOne: false
            referencedRelation: "pet_eggs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pet_egg_orders_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      pet_eggs: {
        Row: {
          allowed_pet_categories: Json | null
          availability_label: string | null
          created_at: string
          daily_quantity: number | null
          id: string
          image_url: string | null
          is_enabled: boolean
          is_purchasable: boolean
          name: string
          per_player_limit: number | null
          premium_only: boolean
          price_fc: number | null
          price_ton: number | null
          rarity_rates: Json
          slug: string
          updated_at: string
        }
        Insert: {
          allowed_pet_categories?: Json | null
          availability_label?: string | null
          created_at?: string
          daily_quantity?: number | null
          id?: string
          image_url?: string | null
          is_enabled?: boolean
          is_purchasable?: boolean
          name: string
          per_player_limit?: number | null
          premium_only?: boolean
          price_fc?: number | null
          price_ton?: number | null
          rarity_rates: Json
          slug: string
          updated_at?: string
        }
        Update: {
          allowed_pet_categories?: Json | null
          availability_label?: string | null
          created_at?: string
          daily_quantity?: number | null
          id?: string
          image_url?: string | null
          is_enabled?: boolean
          is_purchasable?: boolean
          name?: string
          per_player_limit?: number | null
          premium_only?: boolean
          price_fc?: number | null
          price_ton?: number | null
          rarity_rates?: Json
          slug?: string
          updated_at?: string
        }
        Relationships: []
      }
      pet_hatch_history: {
        Row: {
          created_at: string
          duplicate_fragments: number
          egg_id: string
          id: string
          idempotency_key: string
          result_pet_id: string | null
          result_rarity: string | null
          seed_hash: string
          user_id: string
        }
        Insert: {
          created_at?: string
          duplicate_fragments?: number
          egg_id: string
          id?: string
          idempotency_key: string
          result_pet_id?: string | null
          result_rarity?: string | null
          seed_hash: string
          user_id: string
        }
        Update: {
          created_at?: string
          duplicate_fragments?: number
          egg_id?: string
          id?: string
          idempotency_key?: string
          result_pet_id?: string | null
          result_rarity?: string | null
          seed_hash?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "pet_hatch_history_egg_id_fkey"
            columns: ["egg_id"]
            isOneToOne: false
            referencedRelation: "pet_eggs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pet_hatch_history_result_pet_id_fkey"
            columns: ["result_pet_id"]
            isOneToOne: false
            referencedRelation: "pets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pet_hatch_history_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      pet_settings: {
        Row: {
          key: string
          updated_at: string
          value: Json
        }
        Insert: {
          key: string
          updated_at?: string
          value: Json
        }
        Update: {
          key?: string
          updated_at?: string
          value?: Json
        }
        Relationships: []
      }
      pet_upgrade_history: {
        Row: {
          created_at: string
          fc_spent: number
          food_spent: number
          fragments_spent: number
          id: string
          new_level: number | null
          old_level: number | null
          player_pet_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          fc_spent?: number
          food_spent?: number
          fragments_spent?: number
          id?: string
          new_level?: number | null
          old_level?: number | null
          player_pet_id: string
          user_id: string
        }
        Update: {
          created_at?: string
          fc_spent?: number
          food_spent?: number
          fragments_spent?: number
          id?: string
          new_level?: number | null
          old_level?: number | null
          player_pet_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "pet_upgrade_history_player_pet_id_fkey"
            columns: ["player_pet_id"]
            isOneToOne: false
            referencedRelation: "player_pets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pet_upgrade_history_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      pets: {
        Row: {
          active_skill: Json | null
          base_passives: Json
          category: string
          created_at: string
          description: string | null
          id: string
          image_adult_url: string | null
          image_ancestral_url: string | null
          image_baby_url: string | null
          image_young_url: string | null
          is_enabled: boolean
          name: string
          slug: string
          species: string
          updated_at: string
        }
        Insert: {
          active_skill?: Json | null
          base_passives?: Json
          category: string
          created_at?: string
          description?: string | null
          id?: string
          image_adult_url?: string | null
          image_ancestral_url?: string | null
          image_baby_url?: string | null
          image_young_url?: string | null
          is_enabled?: boolean
          name: string
          slug: string
          species: string
          updated_at?: string
        }
        Update: {
          active_skill?: Json | null
          base_passives?: Json
          category?: string
          created_at?: string
          description?: string | null
          id?: string
          image_adult_url?: string | null
          image_ancestral_url?: string | null
          image_baby_url?: string | null
          image_young_url?: string | null
          is_enabled?: boolean
          name?: string
          slug?: string
          species?: string
          updated_at?: string
        }
        Relationships: []
      }
      player_heroes: {
        Row: {
          archetype: string
          attack_growth: number
          attribute_seed: string | null
          base_atk: number
          base_hp: number
          bonus_atk: number
          bonus_hp: number
          created_at: string
          final_atk: number
          final_hp: number
          hero_key: string
          hero_template_id: string | null
          hp_growth: number
          id: string
          image: string | null
          level: number
          name: string
          rarity: string
          stats_generated_at: string | null
          stats_seed: string
          updated_at: string
          user_id: string
        }
        Insert: {
          archetype: string
          attack_growth: number
          attribute_seed?: string | null
          base_atk: number
          base_hp: number
          bonus_atk?: number
          bonus_hp?: number
          created_at?: string
          final_atk: number
          final_hp: number
          hero_key: string
          hero_template_id?: string | null
          hp_growth: number
          id?: string
          image?: string | null
          level?: number
          name: string
          rarity: string
          stats_generated_at?: string | null
          stats_seed: string
          updated_at?: string
          user_id: string
        }
        Update: {
          archetype?: string
          attack_growth?: number
          attribute_seed?: string | null
          base_atk?: number
          base_hp?: number
          bonus_atk?: number
          bonus_hp?: number
          created_at?: string
          final_atk?: number
          final_hp?: number
          hero_key?: string
          hero_template_id?: string | null
          hp_growth?: number
          id?: string
          image?: string | null
          level?: number
          name?: string
          rarity?: string
          stats_generated_at?: string | null
          stats_seed?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "player_heroes_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      player_inventory: {
        Row: {
          id: string
          item_code: string
          item_type: string
          quantity: number
          updated_at: string
          user_id: string
        }
        Insert: {
          id?: string
          item_code: string
          item_type: string
          quantity?: number
          updated_at?: string
          user_id: string
        }
        Update: {
          id?: string
          item_code?: string
          item_type?: string
          quantity?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "player_inventory_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      player_notifications: {
        Row: {
          amount_fc: number | null
          created_at: string
          id: string
          message: string
          metadata: Json
          read_at: string | null
          title: string
          type: string
          user_id: string
        }
        Insert: {
          amount_fc?: number | null
          created_at?: string
          id?: string
          message: string
          metadata?: Json
          read_at?: string | null
          title: string
          type: string
          user_id: string
        }
        Update: {
          amount_fc?: number | null
          created_at?: string
          id?: string
          message?: string
          metadata?: Json
          read_at?: string | null
          title?: string
          type?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "player_notifications_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      player_pet_inventory: {
        Row: {
          id: string
          item_id: string | null
          item_type: string
          quantity: number
          updated_at: string
          user_id: string
        }
        Insert: {
          id?: string
          item_id?: string | null
          item_type: string
          quantity?: number
          updated_at?: string
          user_id: string
        }
        Update: {
          id?: string
          item_id?: string | null
          item_type?: string
          quantity?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "player_pet_inventory_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "pet_eggs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "player_pet_inventory_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      player_pets: {
        Row: {
          created_at: string
          evolution_stage: string
          fragments: number
          id: string
          is_active: boolean
          level: number
          obtained_at: string
          pet_id: string
          rarity: string
          updated_at: string
          user_id: string
          xp: number
        }
        Insert: {
          created_at?: string
          evolution_stage?: string
          fragments?: number
          id?: string
          is_active?: boolean
          level?: number
          obtained_at?: string
          pet_id: string
          rarity: string
          updated_at?: string
          user_id: string
          xp?: number
        }
        Update: {
          created_at?: string
          evolution_stage?: string
          fragments?: number
          id?: string
          is_active?: boolean
          level?: number
          obtained_at?: string
          pet_id?: string
          rarity?: string
          updated_at?: string
          user_id?: string
          xp?: number
        }
        Relationships: [
          {
            foreignKeyName: "player_pets_pet_id_fkey"
            columns: ["pet_id"]
            isOneToOne: false
            referencedRelation: "pets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "player_pets_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      player_season_pass: {
        Row: {
          adventurer_owned: boolean
          legendary_owned: boolean
          season_id: string
          updated_at: string
          user_id: string
          xp: number
        }
        Insert: {
          adventurer_owned?: boolean
          legendary_owned?: boolean
          season_id: string
          updated_at?: string
          user_id: string
          xp?: number
        }
        Update: {
          adventurer_owned?: boolean
          legendary_owned?: boolean
          season_id?: string
          updated_at?: string
          user_id?: string
          xp?: number
        }
        Relationships: [
          {
            foreignKeyName: "player_season_pass_season_id_fkey"
            columns: ["season_id"]
            isOneToOne: false
            referencedRelation: "season_pass_seasons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "player_season_pass_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      pvp_battles: {
        Row: {
          attacker_id: string
          attacker_power: number
          attacker_team_snapshot: Json
          battle_log: Json
          completed_at: string
          created_at: string
          defender_id: string
          defender_power: number
          defender_team_snapshot: Json
          id: string
          result: string
          reward_fc: number
          total_turns: number
          trophy_change: number
          winner_id: string | null
        }
        Insert: {
          attacker_id: string
          attacker_power: number
          attacker_team_snapshot: Json
          battle_log?: Json
          completed_at?: string
          created_at?: string
          defender_id: string
          defender_power: number
          defender_team_snapshot: Json
          id?: string
          result: string
          reward_fc?: number
          total_turns: number
          trophy_change?: number
          winner_id?: string | null
        }
        Update: {
          attacker_id?: string
          attacker_power?: number
          attacker_team_snapshot?: Json
          battle_log?: Json
          completed_at?: string
          created_at?: string
          defender_id?: string
          defender_power?: number
          defender_team_snapshot?: Json
          id?: string
          result?: string
          reward_fc?: number
          total_turns?: number
          trophy_change?: number
          winner_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "pvp_battles_attacker_id_fkey"
            columns: ["attacker_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pvp_battles_defender_id_fkey"
            columns: ["defender_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pvp_battles_winner_id_fkey"
            columns: ["winner_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      pvp_opponent_impressions: {
        Row: {
          last_shown_at: string
          opponent_id: string
          shown_count: number
          user_id: string
        }
        Insert: {
          last_shown_at?: string
          opponent_id: string
          shown_count?: number
          user_id: string
        }
        Update: {
          last_shown_at?: string
          opponent_id?: string
          shown_count?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "pvp_opponent_impressions_opponent_id_fkey"
            columns: ["opponent_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pvp_opponent_impressions_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      pvp_team_slots: {
        Row: {
          created_at: string
          hero_id: string
          id: string
          slot: number
          team_type: string
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          hero_id: string
          id?: string
          slot: number
          team_type: string
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          hero_id?: string
          id?: string
          slot?: number
          team_type?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "pvp_team_slots_hero_id_fkey"
            columns: ["hero_id"]
            isOneToOne: false
            referencedRelation: "player_heroes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pvp_team_slots_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      referral_bonus_claims: {
        Row: {
          amount_fc: number
          created_at: string
          id: string
          milestone: number
          user_id: string
        }
        Insert: {
          amount_fc: number
          created_at?: string
          id?: string
          milestone: number
          user_id: string
        }
        Update: {
          amount_fc?: number
          created_at?: string
          id?: string
          milestone?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "referral_bonus_claims_milestone_fkey"
            columns: ["milestone"]
            isOneToOne: false
            referencedRelation: "referral_bonus_rules"
            referencedColumns: ["milestone"]
          },
          {
            foreignKeyName: "referral_bonus_claims_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      referral_bonus_rules: {
        Row: {
          bonus_fc: number
          enabled: boolean
          milestone: number
          updated_at: string
        }
        Insert: {
          bonus_fc?: number
          enabled?: boolean
          milestone: number
          updated_at?: string
        }
        Update: {
          bonus_fc?: number
          enabled?: boolean
          milestone?: number
          updated_at?: string
        }
        Relationships: []
      }
      referral_commission_settings: {
        Row: {
          level: number
          percent: number
          updated_at: string
        }
        Insert: {
          level: number
          percent: number
          updated_at?: string
        }
        Update: {
          level?: number
          percent?: number
          updated_at?: string
        }
        Relationships: []
      }
      referral_commissions: {
        Row: {
          amount_fc: number
          created_at: string
          from_user: string
          id: string
          idempotency_key: string | null
          level: number
          purchase_id: string
          user_id: string
        }
        Insert: {
          amount_fc: number
          created_at?: string
          from_user: string
          id?: string
          idempotency_key?: string | null
          level: number
          purchase_id: string
          user_id: string
        }
        Update: {
          amount_fc?: number
          created_at?: string
          from_user?: string
          id?: string
          idempotency_key?: string | null
          level?: number
          purchase_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "referral_commissions_from_user_fkey"
            columns: ["from_user"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "referral_commissions_purchase_id_fkey"
            columns: ["purchase_id"]
            isOneToOne: false
            referencedRelation: "referral_purchase_events"
            referencedColumns: ["purchase_id"]
          },
          {
            foreignKeyName: "referral_commissions_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      referral_purchase_events: {
        Row: {
          amount_fc: number
          buyer_id: string
          created_at: string
          eligible: boolean
          event_type: string
          id: string
          purchase_id: string
          source_amount: number | null
          source_currency: string
        }
        Insert: {
          amount_fc: number
          buyer_id: string
          created_at?: string
          eligible: boolean
          event_type: string
          id?: string
          purchase_id: string
          source_amount?: number | null
          source_currency?: string
        }
        Update: {
          amount_fc?: number
          buyer_id?: string
          created_at?: string
          eligible?: boolean
          event_type?: string
          id?: string
          purchase_id?: string
          source_amount?: number | null
          source_currency?: string
        }
        Relationships: [
          {
            foreignKeyName: "referral_purchase_events_buyer_id_fkey"
            columns: ["buyer_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      referrals: {
        Row: {
          created_at: string
          id: string
          inviter_id: string
          level: number
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          inviter_id: string
          level?: number
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          inviter_id?: string
          level?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "referrals_inviter_id_fkey"
            columns: ["inviter_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "referrals_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      season_pass_claims: {
        Row: {
          claimed_at: string
          id: string
          idempotency_key: string
          reward_id: string
          user_id: string
        }
        Insert: {
          claimed_at?: string
          id?: string
          idempotency_key: string
          reward_id: string
          user_id: string
        }
        Update: {
          claimed_at?: string
          id?: string
          idempotency_key?: string
          reward_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "season_pass_claims_reward_id_fkey"
            columns: ["reward_id"]
            isOneToOne: false
            referencedRelation: "season_pass_rewards"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "season_pass_claims_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      season_pass_orders: {
        Row: {
          activated_at: string | null
          amount_nano: string
          created_at: string
          expires_at: string
          id: string
          idempotency_key: string
          paid_at: string | null
          payment_address: string
          payment_comment: string
          price_ton: number
          season_id: string
          status: string
          tier: string
          tx_hash: string | null
          user_id: string
        }
        Insert: {
          activated_at?: string | null
          amount_nano: string
          created_at?: string
          expires_at?: string
          id?: string
          idempotency_key: string
          paid_at?: string | null
          payment_address: string
          payment_comment: string
          price_ton: number
          season_id: string
          status?: string
          tier: string
          tx_hash?: string | null
          user_id: string
        }
        Update: {
          activated_at?: string | null
          amount_nano?: string
          created_at?: string
          expires_at?: string
          id?: string
          idempotency_key?: string
          paid_at?: string | null
          payment_address?: string
          payment_comment?: string
          price_ton?: number
          season_id?: string
          status?: string
          tier?: string
          tx_hash?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "season_pass_orders_season_id_fkey"
            columns: ["season_id"]
            isOneToOne: false
            referencedRelation: "season_pass_seasons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "season_pass_orders_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      season_pass_rewards: {
        Row: {
          amount: number
          enabled: boolean
          id: string
          level: number
          reward_code: string | null
          reward_type: string
          season_id: string
          tier: string
          title: string
          updated_at: string
        }
        Insert: {
          amount?: number
          enabled?: boolean
          id?: string
          level: number
          reward_code?: string | null
          reward_type: string
          season_id: string
          tier: string
          title: string
          updated_at?: string
        }
        Update: {
          amount?: number
          enabled?: boolean
          id?: string
          level?: number
          reward_code?: string | null
          reward_type?: string
          season_id?: string
          tier?: string
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "season_pass_rewards_season_id_fkey"
            columns: ["season_id"]
            isOneToOne: false
            referencedRelation: "season_pass_seasons"
            referencedColumns: ["id"]
          },
        ]
      }
      season_pass_seasons: {
        Row: {
          active: boolean
          adventurer_price_ton: number
          created_at: string
          end_at: string
          id: string
          legendary_price_ton: number
          levels: number
          name: string
          start_at: string
          updated_at: string
          xp_per_level: number
        }
        Insert: {
          active?: boolean
          adventurer_price_ton?: number
          created_at?: string
          end_at: string
          id?: string
          legendary_price_ton?: number
          levels?: number
          name: string
          start_at: string
          updated_at?: string
          xp_per_level?: number
        }
        Update: {
          active?: boolean
          adventurer_price_ton?: number
          created_at?: string
          end_at?: string
          id?: string
          legendary_price_ton?: number
          levels?: number
          name?: string
          start_at?: string
          updated_at?: string
          xp_per_level?: number
        }
        Relationships: []
      }
      wallet_deposits: {
        Row: {
          amount_fc: number
          amount_ton: number
          confirmed_at: string | null
          created_at: string
          credited_at: string | null
          expires_at: string
          from_wallet: string | null
          id: string
          idempotency_key: string
          payment_comment: string
          status: string
          tx_hash: string | null
          user_id: string
        }
        Insert: {
          amount_fc: number
          amount_ton: number
          confirmed_at?: string | null
          created_at?: string
          credited_at?: string | null
          expires_at?: string
          from_wallet?: string | null
          id?: string
          idempotency_key: string
          payment_comment: string
          status?: string
          tx_hash?: string | null
          user_id: string
        }
        Update: {
          amount_fc?: number
          amount_ton?: number
          confirmed_at?: string | null
          created_at?: string
          credited_at?: string | null
          expires_at?: string
          from_wallet?: string | null
          id?: string
          idempotency_key?: string
          payment_comment?: string
          status?: string
          tx_hash?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "wallet_deposits_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      wallet_settings: {
        Row: {
          key: string
          updated_at: string
          value_numeric: number | null
          value_text: string | null
        }
        Insert: {
          key: string
          updated_at?: string
          value_numeric?: number | null
          value_text?: string | null
        }
        Update: {
          key?: string
          updated_at?: string
          value_numeric?: number | null
          value_text?: string | null
        }
        Relationships: []
      }
      wallet_withdrawals: {
        Row: {
          amount_fc: number
          amount_ton: number
          created_at: string
          id: string
          idempotency_key: string
          processed_at: string | null
          status: string
          tx_hash: string | null
          user_id: string
          wallet_address: string
        }
        Insert: {
          amount_fc: number
          amount_ton: number
          created_at?: string
          id?: string
          idempotency_key: string
          processed_at?: string | null
          status?: string
          tx_hash?: string | null
          user_id: string
          wallet_address: string
        }
        Update: {
          amount_fc?: number
          amount_ton?: number
          created_at?: string
          id?: string
          idempotency_key?: string
          processed_at?: string | null
          status?: string
          tx_hash?: string | null
          user_id?: string
          wallet_address?: string
        }
        Relationships: [
          {
            foreignKeyName: "wallet_withdrawals_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      activate_pet: {
        Args: { p_player_pet_id: string; p_telegram_id: number }
        Returns: Json
      }
      admin_grant_pet_item: {
        Args: {
          p_item_id: string
          p_item_type: string
          p_quantity: number
          p_telegram_id: number
        }
        Returns: Json
      }
      admin_set_pet_enabled: {
        Args: { p_enabled: boolean; p_pet_id: string }
        Returns: undefined
      }
      admin_update_pet_egg_economy: {
        Args: {
          p_daily_quantity: number
          p_egg_id: string
          p_enabled: boolean
          p_label: string
          p_player_limit: number
          p_premium_only: boolean
          p_price_fc: number
          p_price_ton: number
          p_purchasable: boolean
          p_rates: Json
        }
        Returns: {
          allowed_pet_categories: Json | null
          availability_label: string | null
          created_at: string
          daily_quantity: number | null
          id: string
          image_url: string | null
          is_enabled: boolean
          is_purchasable: boolean
          name: string
          per_player_limit: number | null
          premium_only: boolean
          price_fc: number | null
          price_ton: number | null
          rarity_rates: Json
          slug: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "pet_eggs"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      admin_update_season_pass: {
        Args: {
          p_active: boolean
          p_adventurer_price: number
          p_end_at: string
          p_legendary_price: number
          p_levels: number
          p_name: string
          p_season_id: string
          p_start_at: string
          p_xp_per_level: number
        }
        Returns: undefined
      }
      admin_update_season_reward: {
        Args: {
          p_amount: number
          p_code: string
          p_enabled: boolean
          p_level: number
          p_reward_id: string
          p_title: string
          p_type: string
        }
        Returns: undefined
      }
      bind_referral: {
        Args: { p_inviter_telegram_id: number; p_telegram_id: number }
        Returns: Json
      }
      calculate_pet_reward: {
        Args: {
          p_base: number
          p_eligible: boolean
          p_kind: string
          p_user: string
        }
        Returns: Json
      }
      claim_boss_reward: { Args: { p_telegram_id: number }; Returns: Json }
      claim_calendar_day: {
        Args: { p_day: number; p_telegram_id: number }
        Returns: Json
      }
      claim_season_pass_reward: {
        Args: { p_reward_id: string; p_telegram_id: number }
        Returns: Json
      }
      confirm_pet_egg_order: {
        Args: { p_amount_nano: string; p_order_id: string; p_tx_hash: string }
        Returns: undefined
      }
      confirm_season_pass_order: {
        Args: { p_amount_nano: string; p_order_id: string; p_tx_hash: string }
        Returns: undefined
      }
      confirm_wallet_deposit: {
        Args: { p_amount_nano: string; p_deposit_id: string; p_tx_hash: string }
        Returns: undefined
      }
      create_pet_egg_order: {
        Args: {
          p_egg_id: string
          p_idempotency_key: string
          p_telegram_id: number
        }
        Returns: Json
      }
      create_season_pass_order: {
        Args: {
          p_idempotency_key: string
          p_telegram_id: number
          p_tier: string
        }
        Returns: Json
      }
      create_wallet_deposit: {
        Args: {
          p_amount_ton: number
          p_from_wallet: string
          p_idempotency_key: string
          p_telegram_id: number
        }
        Returns: Json
      }
      distribute_referral_commission: {
        Args: {
          p_amount_fc: number
          p_buyer_id: string
          p_eligible: boolean
          p_event_type: string
          p_purchase_id: string
          p_source_amount?: number
          p_source_currency?: string
        }
        Returns: Json
      }
      ensure_boss_combat: { Args: { p_telegram_id: number }; Returns: string }
      equip_combat_hero: {
        Args: { p_hero_id: string; p_slot: number; p_telegram_id: number }
        Returns: Json
      }
      feed_pet: {
        Args: { p_food: number; p_player_pet_id: string; p_telegram_id: number }
        Returns: Json
      }
      finish_wallet_withdrawal: {
        Args: { p_status: string; p_tx_hash?: string; p_withdrawal_id: string }
        Returns: undefined
      }
      generate_missing_hero_stats: { Args: never; Returns: number }
      get_boss_combat: { Args: { p_telegram_id: number }; Returns: Json }
      get_calendar_dashboard: { Args: { p_telegram_id: number }; Returns: Json }
      get_pet_admin_stats: { Args: never; Returns: Json }
      get_pet_bonuses: { Args: { p_user: string }; Returns: Json }
      get_pet_dashboard: { Args: { p_telegram_id: number }; Returns: Json }
      get_pet_egg_store: { Args: { p_telegram_id: number }; Returns: Json }
      get_pet_pvp_snapshot: { Args: { p_user: string }; Returns: Json }
      get_pvp_dashboard: { Args: { p_telegram_id: number }; Returns: Json }
      get_pvp_history: { Args: { p_telegram_id: number }; Returns: Json }
      get_pvp_ranking: { Args: never; Returns: Json }
      get_referral_admin_stats: { Args: never; Returns: Json }
      get_referral_dashboard: { Args: { p_telegram_id: number }; Returns: Json }
      get_referral_dashboard_v2: {
        Args: {
          p_level?: number
          p_limit?: number
          p_offset?: number
          p_telegram_id: number
        }
        Returns: Json
      }
      get_season_pass_dashboard: {
        Args: { p_telegram_id: number }
        Returns: Json
      }
      get_wallet_summary: { Args: { p_telegram_id: number }; Returns: Json }
      grant_referral_milestones: {
        Args: { p_user_id: string }
        Returns: undefined
      }
      hatch_pet_egg: {
        Args: {
          p_egg_id: string
          p_idempotency_key: string
          p_telegram_id: number
        }
        Returns: Json
      }
      normalize_hero_rarity: { Args: { value: string }; Returns: string }
      normalize_pet_rarity: { Args: { v: string }; Returns: string }
      open_calendar_hero_chest: {
        Args: { p_inventory_item_id: string; p_telegram_id: number }
        Returns: Json
      }
      pet_evolution_stage: { Args: { v: number }; Returns: string }
      pet_rarity_multiplier: { Args: { v: string }; Returns: number }
      process_boss_combat: {
        Args: { p_now?: string; p_telegram_id: number }
        Returns: Json
      }
      pvp_hero_json: {
        Args: { h: Database["public"]["Tables"]["player_heroes"]["Row"] }
        Returns: Json
      }
      pvp_league: { Args: { t: number }; Returns: string }
      pvp_stat_unit: { Args: { v: string }; Returns: number }
      pvp_team_json: { Args: { p_type: string; p_user: string }; Returns: Json }
      pvp_team_power: {
        Args: { p_type: string; p_user: string }
        Returns: number
      }
      rarity_base_atk: { Args: { r: string }; Returns: number }
      rarity_base_hp: { Args: { r: string }; Returns: number }
      rarity_resistance: { Args: { r: string }; Returns: number }
      record_eligible_purchase: {
        Args: {
          p_amount: number
          p_buyer_id: string
          p_currency: string
          p_eligible?: boolean
          p_event_type: string
          p_purchase_id: string
        }
        Returns: Json
      }
      recruit_heroes: {
        Args: { p_count: number; p_telegram_id: number }
        Returns: Json
      }
      remove_pvp_team_slot: {
        Args: { p_slot: number; p_team_type: string; p_telegram_id: number }
        Returns: Json
      }
      request_wallet_withdrawal: {
        Args: {
          p_amount_fc: number
          p_idempotency_key: string
          p_telegram_id: number
          p_wallet_address: string
        }
        Returns: Json
      }
      save_pvp_team_slot: {
        Args: {
          p_hero_id: string
          p_slot: number
          p_team_type: string
          p_telegram_id: number
        }
        Returns: Json
      }
      search_pvp_opponents: { Args: { p_telegram_id: number }; Returns: Json }
      set_boss_team: {
        Args: { p_hero_ids: string[]; p_telegram_id: number }
        Returns: Json
      }
      simulate_pvp_battle: {
        Args: { a: Json; d: Json; seed: string }
        Returns: Json
      }
      start_pvp_battle: {
        Args: { p_opponent_id: string; p_telegram_id: number }
        Returns: Json
      }
      touch_referral_player: {
        Args: {
          p_avatar: string
          p_name: string
          p_telegram_id: number
          p_username: string
        }
        Returns: string
      }
      upgrade_pet: {
        Args: { p_player_pet_id: string; p_telegram_id: number }
        Returns: Json
      }
      upsert_telegram_player_profile: {
        Args: {
          p_first_name: string
          p_last_name?: string
          p_photo_url?: string
          p_telegram_id: number
          p_username?: string
        }
        Returns: Json
      }
      wallet_hot_address: { Args: never; Returns: string }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {},
  },
} as const
