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
      ad_providers: {
        Row: {
          code: string
          config: Json
          cooldown_seconds: number
          daily_limit: number
          enabled: boolean
          name: string
          reward_fc: number
          updated_at: string
        }
        Insert: {
          code: string
          config?: Json
          cooldown_seconds?: number
          daily_limit?: number
          enabled?: boolean
          name: string
          reward_fc?: number
          updated_at?: string
        }
        Update: {
          code?: string
          config?: Json
          cooldown_seconds?: number
          daily_limit?: number
          enabled?: boolean
          name?: string
          reward_fc?: number
          updated_at?: string
        }
        Relationships: []
      }
      admin_audit_logs: {
        Row: {
          action: string
          admin_id: number
          context: Json
          created_at: string
          id: string
          new_value: Json | null
          old_value: Json | null
          reason: string | null
          target_id: string | null
          target_type: string
        }
        Insert: {
          action: string
          admin_id: number
          context?: Json
          created_at?: string
          id?: string
          new_value?: Json | null
          old_value?: Json | null
          reason?: string | null
          target_id?: string | null
          target_type?: string
        }
        Update: {
          action?: string
          admin_id?: number
          context?: Json
          created_at?: string
          id?: string
          new_value?: Json | null
          old_value?: Json | null
          reason?: string | null
          target_id?: string | null
          target_type?: string
        }
        Relationships: []
      }
      admin_snapshots: {
        Row: {
          admin_id: number
          created_at: string
          id: string
          label: string
          payload: Json
        }
        Insert: {
          admin_id: number
          created_at?: string
          id?: string
          label: string
          payload: Json
        }
        Update: {
          admin_id?: number
          created_at?: string
          id?: string
          label?: string
          payload?: Json
        }
        Relationships: []
      }
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
      boss_templates: {
        Row: {
          active: boolean
          attack: number
          attack_interval_seconds: number
          attack_limit: number | null
          code: string
          cooldown_seconds: number
          created_at: string
          defense: number
          difficulty: string
          ends_at: string | null
          id: string
          image_url: string | null
          level: number
          max_hp: number
          name: string
          reward_amount: number
          starts_at: string | null
          ticket_cost: number
          updated_at: string
        }
        Insert: {
          active?: boolean
          attack?: number
          attack_interval_seconds?: number
          attack_limit?: number | null
          code: string
          cooldown_seconds?: number
          created_at?: string
          defense?: number
          difficulty?: string
          ends_at?: string | null
          id?: string
          image_url?: string | null
          level?: number
          max_hp?: number
          name: string
          reward_amount?: number
          starts_at?: string | null
          ticket_cost?: number
          updated_at?: string
        }
        Update: {
          active?: boolean
          attack?: number
          attack_interval_seconds?: number
          attack_limit?: number | null
          code?: string
          cooldown_seconds?: number
          created_at?: string
          defense?: number
          difficulty?: string
          ends_at?: string | null
          id?: string
          image_url?: string | null
          level?: number
          max_hp?: number
          name?: string
          reward_amount?: number
          starts_at?: string | null
          ticket_cost?: number
          updated_at?: string
        }
        Relationships: []
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
      game_missions: {
        Row: {
          code: string
          daily_limit: number | null
          description: string | null
          enabled: boolean
          reward_amount: number
          reward_code: string | null
          reward_type: string
          reward_xp: number
          scope: string
          sort_order: number
          target_amount: number
          target_metric: string
          title: string
          updated_at: string
        }
        Insert: {
          code: string
          daily_limit?: number | null
          description?: string | null
          enabled?: boolean
          reward_amount?: number
          reward_code?: string | null
          reward_type?: string
          reward_xp?: number
          scope?: string
          sort_order?: number
          target_amount?: number
          target_metric?: string
          title: string
          updated_at?: string
        }
        Update: {
          code?: string
          daily_limit?: number | null
          description?: string | null
          enabled?: boolean
          reward_amount?: number
          reward_code?: string | null
          reward_type?: string
          reward_xp?: number
          scope?: string
          sort_order?: number
          target_amount?: number
          target_metric?: string
          title?: string
          updated_at?: string
        }
        Relationships: []
      }
      game_players: {
        Row: {
          avatar_url: string | null
          ban_reason: string | null
          banned: boolean
          banned_at: string | null
          boss_defeats: number
          created_at: string
          display_name: string | null
          first_name: string | null
          forge_coins: number
          id: string
          last_name: string | null
          last_seen_at: string
          premium_until: string | null
          pvp_banned: boolean
          pvp_losses: number
          pvp_tickets: number
          pvp_trophies: number
          pvp_wins: number
          telegram_id: number
          ton_balance: number
          updated_at: string
          username: string | null
          vip_until: string | null
        }
        Insert: {
          avatar_url?: string | null
          ban_reason?: string | null
          banned?: boolean
          banned_at?: string | null
          boss_defeats?: number
          created_at?: string
          display_name?: string | null
          first_name?: string | null
          forge_coins?: number
          id?: string
          last_name?: string | null
          last_seen_at?: string
          premium_until?: string | null
          pvp_banned?: boolean
          pvp_losses?: number
          pvp_tickets?: number
          pvp_trophies?: number
          pvp_wins?: number
          telegram_id: number
          ton_balance?: number
          updated_at?: string
          username?: string | null
          vip_until?: string | null
        }
        Update: {
          avatar_url?: string | null
          ban_reason?: string | null
          banned?: boolean
          banned_at?: string | null
          boss_defeats?: number
          created_at?: string
          display_name?: string | null
          first_name?: string | null
          forge_coins?: number
          id?: string
          last_name?: string | null
          last_seen_at?: string
          premium_until?: string | null
          pvp_banned?: boolean
          pvp_losses?: number
          pvp_tickets?: number
          pvp_trophies?: number
          pvp_wins?: number
          telegram_id?: number
          ton_balance?: number
          updated_at?: string
          username?: string | null
          vip_until?: string | null
        }
        Relationships: []
      }
      game_settings: {
        Row: {
          category: string
          key: string
          label: string
          updated_at: string
          updated_by: number | null
          value: Json
        }
        Insert: {
          category?: string
          key: string
          label?: string
          updated_at?: string
          updated_by?: number | null
          value?: Json
        }
        Update: {
          category?: string
          key?: string
          label?: string
          updated_at?: string
          updated_by?: number | null
          value?: Json
        }
        Relationships: []
      }
      hero_catalog: {
        Row: {
          available_from: string | null
          available_until: string | null
          base_atk: number | null
          base_hp: number | null
          battle_image: string | null
          buffs: Json
          description: string | null
          discount_percent: number
          drop_weight: number
          enabled: boolean
          featured: boolean
          hero_class: string
          hero_key: string
          image: string
          in_shop: boolean
          max_level: number
          name: string
          per_player_limit: number | null
          power: number | null
          price_fc: number | null
          price_ton: number | null
          rarity: string
          skills: Json
          sort_order: number
          start_level: number
          stock: number | null
          updated_at: string
        }
        Insert: {
          available_from?: string | null
          available_until?: string | null
          base_atk?: number | null
          base_hp?: number | null
          battle_image?: string | null
          buffs?: Json
          description?: string | null
          discount_percent?: number
          drop_weight?: number
          enabled?: boolean
          featured?: boolean
          hero_class?: string
          hero_key: string
          image: string
          in_shop?: boolean
          max_level?: number
          name: string
          per_player_limit?: number | null
          power?: number | null
          price_fc?: number | null
          price_ton?: number | null
          rarity: string
          skills?: Json
          sort_order?: number
          start_level?: number
          stock?: number | null
          updated_at?: string
        }
        Update: {
          available_from?: string | null
          available_until?: string | null
          base_atk?: number | null
          base_hp?: number | null
          battle_image?: string | null
          buffs?: Json
          description?: string | null
          discount_percent?: number
          drop_weight?: number
          enabled?: boolean
          featured?: boolean
          hero_class?: string
          hero_key?: string
          image?: string
          in_shop?: boolean
          max_level?: number
          name?: string
          per_player_limit?: number | null
          power?: number | null
          price_fc?: number | null
          price_ton?: number | null
          rarity?: string
          skills?: Json
          sort_order?: number
          start_level?: number
          stock?: number | null
          updated_at?: string
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
      pet_action_idempotency: {
        Row: {
          action: string
          created_at: string
          idempotency_key: string
          player_pet_id: string
          result: Json | null
          user_id: string
        }
        Insert: {
          action: string
          created_at?: string
          idempotency_key: string
          player_pet_id: string
          result?: Json | null
          user_id: string
        }
        Update: {
          action?: string
          created_at?: string
          idempotency_key?: string
          player_pet_id?: string
          result?: Json | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "pet_action_idempotency_player_pet_id_fkey"
            columns: ["player_pet_id"]
            isOneToOne: false
            referencedRelation: "player_pets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pet_action_idempotency_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      pet_buff_pool: {
        Row: {
          buff_key: string
          categories: Json
          enabled: boolean
          updated_at: string
        }
        Insert: {
          buff_key: string
          categories?: Json
          enabled?: boolean
          updated_at?: string
        }
        Update: {
          buff_key?: string
          categories?: Json
          enabled?: boolean
          updated_at?: string
        }
        Relationships: []
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
      pet_evolution_history: {
        Row: {
          created_at: string
          fc_cost: number
          id: string
          idempotency_key: string
          new_level: number
          new_stage: string | null
          old_level: number
          old_stage: string | null
          player_pet_id: string
          rarity: string
          user_id: string
          xp_after: number
          xp_before: number
          xp_spent: number
        }
        Insert: {
          created_at?: string
          fc_cost: number
          id?: string
          idempotency_key: string
          new_level: number
          new_stage?: string | null
          old_level: number
          old_stage?: string | null
          player_pet_id: string
          rarity: string
          user_id: string
          xp_after: number
          xp_before: number
          xp_spent: number
        }
        Update: {
          created_at?: string
          fc_cost?: number
          id?: string
          idempotency_key?: string
          new_level?: number
          new_stage?: string | null
          old_level?: number
          old_stage?: string | null
          player_pet_id?: string
          rarity?: string
          user_id?: string
          xp_after?: number
          xp_before?: number
          xp_spent?: number
        }
        Relationships: [
          {
            foreignKeyName: "pet_evolution_history_player_pet_id_fkey"
            columns: ["player_pet_id"]
            isOneToOne: false
            referencedRelation: "player_pets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pet_evolution_history_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      pet_evolution_tiers: {
        Row: {
          enabled: boolean
          evolution_stage: string
          fc_cost: number
          fragment_cost: number
          label: string
          max_secondary_buffs: number
          new_buff_chance: number
          primary_multiplier: number
          required_level: number
          tier: number
          updated_at: string
        }
        Insert: {
          enabled?: boolean
          evolution_stage?: string
          fc_cost?: number
          fragment_cost?: number
          label: string
          max_secondary_buffs?: number
          new_buff_chance?: number
          primary_multiplier?: number
          required_level: number
          tier: number
          updated_at?: string
        }
        Update: {
          enabled?: boolean
          evolution_stage?: string
          fc_cost?: number
          fragment_cost?: number
          label?: string
          max_secondary_buffs?: number
          new_buff_chance?: number
          primary_multiplier?: number
          required_level?: number
          tier?: number
          updated_at?: string
        }
        Relationships: []
      }
      pet_evolutions: {
        Row: {
          created_at: string
          evolution_from: number
          evolution_to: number
          fc_spent: number
          fragments_spent: number
          id: string
          idempotency_key: string
          level_at_evolution: number
          player_pet_id: string
          unlocked_buff: string | null
          unlocked_buff_rarity: string | null
          unlocked_buff_value: number | null
          user_id: string
        }
        Insert: {
          created_at?: string
          evolution_from: number
          evolution_to: number
          fc_spent?: number
          fragments_spent?: number
          id?: string
          idempotency_key: string
          level_at_evolution: number
          player_pet_id: string
          unlocked_buff?: string | null
          unlocked_buff_rarity?: string | null
          unlocked_buff_value?: number | null
          user_id: string
        }
        Update: {
          created_at?: string
          evolution_from?: number
          evolution_to?: number
          fc_spent?: number
          fragments_spent?: number
          id?: string
          idempotency_key?: string
          level_at_evolution?: number
          player_pet_id?: string
          unlocked_buff?: string | null
          unlocked_buff_rarity?: string | null
          unlocked_buff_value?: number | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "pet_evolutions_player_pet_id_fkey"
            columns: ["player_pet_id"]
            isOneToOne: false
            referencedRelation: "player_pets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pet_evolutions_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      pet_food_items: {
        Row: {
          code: string
          enabled: boolean
          icon: string
          name: string
          rarity: string
          sort_order: number
          updated_at: string
          xp_value: number
        }
        Insert: {
          code: string
          enabled?: boolean
          icon?: string
          name: string
          rarity?: string
          sort_order?: number
          updated_at?: string
          xp_value?: number
        }
        Update: {
          code?: string
          enabled?: boolean
          icon?: string
          name?: string
          rarity?: string
          sort_order?: number
          updated_at?: string
          xp_value?: number
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
          exclusive_badge: string | null
          exclusive_pass_tier: string | null
          exclusive_passive: Json
          exclusive_season_id: string | null
          id: string
          image_adult_url: string | null
          image_ancestral_url: string | null
          image_baby_url: string | null
          image_young_url: string | null
          is_enabled: boolean
          is_season_exclusive: boolean
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
          exclusive_badge?: string | null
          exclusive_pass_tier?: string | null
          exclusive_passive?: Json
          exclusive_season_id?: string | null
          id?: string
          image_adult_url?: string | null
          image_ancestral_url?: string | null
          image_baby_url?: string | null
          image_young_url?: string | null
          is_enabled?: boolean
          is_season_exclusive?: boolean
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
          exclusive_badge?: string | null
          exclusive_pass_tier?: string | null
          exclusive_passive?: Json
          exclusive_season_id?: string | null
          id?: string
          image_adult_url?: string | null
          image_ancestral_url?: string | null
          image_baby_url?: string | null
          image_young_url?: string | null
          is_enabled?: boolean
          is_season_exclusive?: boolean
          name?: string
          slug?: string
          species?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "pets_exclusive_season_id_fkey"
            columns: ["exclusive_season_id"]
            isOneToOne: false
            referencedRelation: "season_pass_seasons"
            referencedColumns: ["id"]
          },
        ]
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
          exclusive_badge: string | null
          exclusive_pass_tier: string | null
          exclusive_passive: Json
          exclusive_season_id: string | null
          final_atk: number
          final_hp: number
          hero_key: string
          hero_template_id: string | null
          hp_growth: number
          id: string
          image: string | null
          is_season_exclusive: boolean
          level: number
          name: string
          rarity: string
          stats_generated_at: string | null
          stats_seed: string
          tradable: boolean
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
          exclusive_badge?: string | null
          exclusive_pass_tier?: string | null
          exclusive_passive?: Json
          exclusive_season_id?: string | null
          final_atk: number
          final_hp: number
          hero_key: string
          hero_template_id?: string | null
          hp_growth: number
          id?: string
          image?: string | null
          is_season_exclusive?: boolean
          level?: number
          name: string
          rarity: string
          stats_generated_at?: string | null
          stats_seed: string
          tradable?: boolean
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
          exclusive_badge?: string | null
          exclusive_pass_tier?: string | null
          exclusive_passive?: Json
          exclusive_season_id?: string | null
          final_atk?: number
          final_hp?: number
          hero_key?: string
          hero_template_id?: string | null
          hp_growth?: number
          id?: string
          image?: string | null
          is_season_exclusive?: boolean
          level?: number
          name?: string
          rarity?: string
          stats_generated_at?: string | null
          stats_seed?: string
          tradable?: boolean
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "player_heroes_exclusive_season_id_fkey"
            columns: ["exclusive_season_id"]
            isOneToOne: false
            referencedRelation: "season_pass_seasons"
            referencedColumns: ["id"]
          },
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
          exclusive_reward_code: string | null
          id: string
          is_exclusive: boolean
          item_code: string
          item_type: string
          pass_tier: string | null
          quantity: number
          season_id: string | null
          tradable: boolean
          updated_at: string
          user_id: string
        }
        Insert: {
          exclusive_reward_code?: string | null
          id?: string
          is_exclusive?: boolean
          item_code: string
          item_type: string
          pass_tier?: string | null
          quantity?: number
          season_id?: string | null
          tradable?: boolean
          updated_at?: string
          user_id: string
        }
        Update: {
          exclusive_reward_code?: string | null
          id?: string
          is_exclusive?: boolean
          item_code?: string
          item_type?: string
          pass_tier?: string | null
          quantity?: number
          season_id?: string | null
          tradable?: boolean
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "player_inventory_season_id_fkey"
            columns: ["season_id"]
            isOneToOne: false
            referencedRelation: "season_pass_seasons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "player_inventory_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      player_mission_progress: {
        Row: {
          claimed_at: string | null
          completed_at: string | null
          cycle: string
          id: string
          mission_code: string
          progress: number
          updated_at: string
          user_id: string
        }
        Insert: {
          claimed_at?: string | null
          completed_at?: string | null
          cycle: string
          id?: string
          mission_code: string
          progress?: number
          updated_at?: string
          user_id: string
        }
        Update: {
          claimed_at?: string | null
          completed_at?: string | null
          cycle?: string
          id?: string
          mission_code?: string
          progress?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "player_mission_progress_mission_code_fkey"
            columns: ["mission_code"]
            isOneToOne: false
            referencedRelation: "game_missions"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "player_mission_progress_user_id_fkey"
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
      player_pet_food: {
        Row: {
          food_code: string
          quantity: number
          updated_at: string
          user_id: string
        }
        Insert: {
          food_code: string
          quantity?: number
          updated_at?: string
          user_id: string
        }
        Update: {
          food_code?: string
          quantity?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "player_pet_food_food_code_fkey"
            columns: ["food_code"]
            isOneToOne: false
            referencedRelation: "pet_food_items"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "player_pet_food_user_id_fkey"
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
          evolution_tier: number
          exclusive_badge: string | null
          exclusive_season_id: string | null
          fragments: number
          id: string
          is_active: boolean
          is_season_exclusive: boolean
          level: number
          obtained_at: string
          pet_id: string
          rarity: string
          secondary_buffs: Json
          tradable: boolean
          updated_at: string
          user_id: string
          xp: number
        }
        Insert: {
          created_at?: string
          evolution_stage?: string
          evolution_tier?: number
          exclusive_badge?: string | null
          exclusive_season_id?: string | null
          fragments?: number
          id?: string
          is_active?: boolean
          is_season_exclusive?: boolean
          level?: number
          obtained_at?: string
          pet_id: string
          rarity: string
          secondary_buffs?: Json
          tradable?: boolean
          updated_at?: string
          user_id: string
          xp?: number
        }
        Update: {
          created_at?: string
          evolution_stage?: string
          evolution_tier?: number
          exclusive_badge?: string | null
          exclusive_season_id?: string | null
          fragments?: number
          id?: string
          is_active?: boolean
          is_season_exclusive?: boolean
          level?: number
          obtained_at?: string
          pet_id?: string
          rarity?: string
          secondary_buffs?: Json
          tradable?: boolean
          updated_at?: string
          user_id?: string
          xp?: number
        }
        Relationships: [
          {
            foreignKeyName: "player_pets_exclusive_season_id_fkey"
            columns: ["exclusive_season_id"]
            isOneToOne: false
            referencedRelation: "season_pass_seasons"
            referencedColumns: ["id"]
          },
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
          purchased_at: string | null
          season_id: string
          tier: string
          updated_at: string
          upgraded_at: string | null
          user_id: string
          xp: number
        }
        Insert: {
          adventurer_owned?: boolean
          legendary_owned?: boolean
          purchased_at?: string | null
          season_id: string
          tier?: string
          updated_at?: string
          upgraded_at?: string | null
          user_id: string
          xp?: number
        }
        Update: {
          adventurer_owned?: boolean
          legendary_owned?: boolean
          purchased_at?: string | null
          season_id?: string
          tier?: string
          updated_at?: string
          upgraded_at?: string | null
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
      pool_balance: {
        Row: {
          balance_ton: number
          created_at: string
          distribution_key: string | null
          ends_at: string
          id: string
          starts_at: string
          status: string
          updated_at: string
          week_label: string
        }
        Insert: {
          balance_ton?: number
          created_at?: string
          distribution_key?: string | null
          ends_at: string
          id?: string
          starts_at: string
          status?: string
          updated_at?: string
          week_label: string
        }
        Update: {
          balance_ton?: number
          created_at?: string
          distribution_key?: string | null
          ends_at?: string
          id?: string
          starts_at?: string
          status?: string
          updated_at?: string
          week_label?: string
        }
        Relationships: []
      }
      pool_history: {
        Row: {
          amount_ton: number
          distributed_at: string
          id: string
          pool_id: string
          seed_hash: string
          week_label: string
          winner_count: number
        }
        Insert: {
          amount_ton: number
          distributed_at?: string
          id?: string
          pool_id: string
          seed_hash: string
          week_label: string
          winner_count: number
        }
        Update: {
          amount_ton?: number
          distributed_at?: string
          id?: string
          pool_id?: string
          seed_hash?: string
          week_label?: string
          winner_count?: number
        }
        Relationships: [
          {
            foreignKeyName: "pool_history_pool_id_fkey"
            columns: ["pool_id"]
            isOneToOne: true
            referencedRelation: "pool_balance"
            referencedColumns: ["id"]
          },
        ]
      }
      pool_points: {
        Row: {
          activity_type: string
          created_at: string
          id: string
          idempotency_key: string
          points: number
          pool_id: string
          source_id: string
          user_id: string
        }
        Insert: {
          activity_type: string
          created_at?: string
          id?: string
          idempotency_key: string
          points: number
          pool_id: string
          source_id: string
          user_id: string
        }
        Update: {
          activity_type?: string
          created_at?: string
          id?: string
          idempotency_key?: string
          points?: number
          pool_id?: string
          source_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "pool_points_pool_id_fkey"
            columns: ["pool_id"]
            isOneToOne: false
            referencedRelation: "pool_balance"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pool_points_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      pool_revenue: {
        Row: {
          amount_ton: number
          base_amount_ton: number
          created_at: string
          id: string
          idempotency_key: string
          percent: number
          pool_id: string
          source_id: string
          source_type: string
          user_id: string | null
        }
        Insert: {
          amount_ton: number
          base_amount_ton: number
          created_at?: string
          id?: string
          idempotency_key: string
          percent: number
          pool_id: string
          source_id: string
          source_type: string
          user_id?: string | null
        }
        Update: {
          amount_ton?: number
          base_amount_ton?: number
          created_at?: string
          id?: string
          idempotency_key?: string
          percent?: number
          pool_id?: string
          source_id?: string
          source_type?: string
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "pool_revenue_pool_id_fkey"
            columns: ["pool_id"]
            isOneToOne: false
            referencedRelation: "pool_balance"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pool_revenue_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      pool_rewards: {
        Row: {
          amount_ton: number
          created_at: string
          history_id: string
          id: string
          idempotency_key: string
          paid_at: string | null
          position: number | null
          reward_type: string
          status: string
          tx_hash: string | null
          user_id: string
        }
        Insert: {
          amount_ton: number
          created_at?: string
          history_id: string
          id?: string
          idempotency_key: string
          paid_at?: string | null
          position?: number | null
          reward_type: string
          status?: string
          tx_hash?: string | null
          user_id: string
        }
        Update: {
          amount_ton?: number
          created_at?: string
          history_id?: string
          id?: string
          idempotency_key?: string
          paid_at?: string | null
          position?: number | null
          reward_type?: string
          status?: string
          tx_hash?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "pool_rewards_history_id_fkey"
            columns: ["history_id"]
            isOneToOne: false
            referencedRelation: "pool_history"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pool_rewards_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      pool_settings: {
        Row: {
          activity_points: Json
          id: boolean
          lottery_share_percent: number
          lottery_winner_count: number
          minimum_points: number
          ranking_percentages: Json
          ranking_share_percent: number
          ranking_winner_limit: number
          revenue_percentages: Json
          season_days: number
          updated_at: string
        }
        Insert: {
          activity_points?: Json
          id?: boolean
          lottery_share_percent?: number
          lottery_winner_count?: number
          minimum_points?: number
          ranking_percentages?: Json
          ranking_share_percent?: number
          ranking_winner_limit?: number
          revenue_percentages?: Json
          season_days?: number
          updated_at?: string
        }
        Update: {
          activity_points?: Json
          id?: boolean
          lottery_share_percent?: number
          lottery_winner_count?: number
          minimum_points?: number
          ranking_percentages?: Json
          ranking_share_percent?: number
          ranking_winner_limit?: number
          revenue_percentages?: Json
          season_days?: number
          updated_at?: string
        }
        Relationships: []
      }
      pool_wallets: {
        Row: {
          connected_at: string
          updated_at: string
          user_id: string
          wallet_address: string
        }
        Insert: {
          connected_at?: string
          updated_at?: string
          user_id: string
          wallet_address: string
        }
        Update: {
          connected_at?: string
          updated_at?: string
          user_id?: string
          wallet_address?: string
        }
        Relationships: [
          {
            foreignKeyName: "pool_wallets_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      pool_winners: {
        Row: {
          created_at: string
          history_id: string
          id: string
          points: number
          position: number | null
          user_id: string
          winner_type: string
        }
        Insert: {
          created_at?: string
          history_id: string
          id?: string
          points: number
          position?: number | null
          user_id: string
          winner_type: string
        }
        Update: {
          created_at?: string
          history_id?: string
          id?: string
          points?: number
          position?: number | null
          user_id?: string
          winner_type?: string
        }
        Relationships: [
          {
            foreignKeyName: "pool_winners_history_id_fkey"
            columns: ["history_id"]
            isOneToOne: false
            referencedRelation: "pool_history"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pool_winners_user_id_fkey"
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
      pvp_leagues: {
        Row: {
          code: string
          enabled: boolean
          icon: string
          max_trophies: number | null
          min_trophies: number
          name: string
          reward: Json
          sort_order: number
          updated_at: string
        }
        Insert: {
          code: string
          enabled?: boolean
          icon?: string
          max_trophies?: number | null
          min_trophies?: number
          name: string
          reward?: Json
          sort_order?: number
          updated_at?: string
        }
        Update: {
          code?: string
          enabled?: boolean
          icon?: string
          max_trophies?: number | null
          min_trophies?: number
          name?: string
          reward?: Json
          sort_order?: number
          updated_at?: string
        }
        Relationships: []
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
      season_exclusive_deliveries: {
        Row: {
          created_at: string
          delivery_kind: string
          id: string
          idempotency_key: string
          reward_id: string
          season_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          delivery_kind: string
          id?: string
          idempotency_key: string
          reward_id: string
          season_id: string
          user_id: string
        }
        Update: {
          created_at?: string
          delivery_kind?: string
          id?: string
          idempotency_key?: string
          reward_id?: string
          season_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "season_exclusive_deliveries_reward_id_fkey"
            columns: ["reward_id"]
            isOneToOne: false
            referencedRelation: "season_exclusive_rewards"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "season_exclusive_deliveries_season_id_fkey"
            columns: ["season_id"]
            isOneToOne: false
            referencedRelation: "season_pass_seasons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "season_exclusive_deliveries_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      season_exclusive_rewards: {
        Row: {
          badge: string
          created_at: string
          display_name: string
          enabled: boolean
          id: string
          image_url: string
          pass_tier: string
          passive: Json
          reward_code: string
          reward_kind: string
          season_id: string
          target_pet_id: string | null
          updated_at: string
        }
        Insert: {
          badge: string
          created_at?: string
          display_name: string
          enabled?: boolean
          id?: string
          image_url: string
          pass_tier: string
          passive?: Json
          reward_code: string
          reward_kind: string
          season_id: string
          target_pet_id?: string | null
          updated_at?: string
        }
        Update: {
          badge?: string
          created_at?: string
          display_name?: string
          enabled?: boolean
          id?: string
          image_url?: string
          pass_tier?: string
          passive?: Json
          reward_code?: string
          reward_kind?: string
          season_id?: string
          target_pet_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "season_exclusive_rewards_season_id_fkey"
            columns: ["season_id"]
            isOneToOne: false
            referencedRelation: "season_pass_seasons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "season_exclusive_rewards_target_pet_id_fkey"
            columns: ["target_pet_id"]
            isOneToOne: false
            referencedRelation: "pets"
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
      admin_adjust_balance: {
        Args: {
          p_admin_id: number
          p_amount: number
          p_currency: string
          p_mode: string
          p_reason?: string
          p_ref: string
        }
        Returns: Json
      }
      admin_adjust_pool_balance: {
        Args: { p_amount: number; p_reason: string }
        Returns: number
      }
      admin_adjust_pvp_stat: {
        Args: {
          p_admin_id: number
          p_amount: number
          p_mode: string
          p_reason?: string
          p_ref: string
          p_stat: string
        }
        Returns: Json
      }
      admin_ads_overview: { Args: { p_admin_id: number }; Returns: Json }
      admin_assert: { Args: { p_admin_id: number }; Returns: undefined }
      admin_boss_control: {
        Args: {
          p_action: string
          p_admin_id: number
          p_code?: string
          p_reason?: string
        }
        Returns: Json
      }
      admin_boss_overview: { Args: { p_admin_id: number }; Returns: Json }
      admin_broadcast_targets: {
        Args: { p_admin_id: number; p_limit?: number; p_segment: string }
        Returns: Json
      }
      admin_bump_settings_version: { Args: never; Returns: number }
      admin_cancel_pool: { Args: never; Returns: undefined }
      admin_create_snapshot: {
        Args: { p_admin_id: number; p_label: string }
        Returns: Json
      }
      admin_get_settings: {
        Args: { p_admin_id: number; p_category?: string }
        Returns: Json
      }
      admin_grant_hero: {
        Args: {
          p_admin_id: number
          p_hero_key: string
          p_level?: number
          p_reason?: string
          p_ref: string
        }
        Returns: Json
      }
      admin_grant_pet: {
        Args: {
          p_admin_id: number
          p_level?: number
          p_pet_slug: string
          p_rarity?: string
          p_reason?: string
          p_ref: string
        }
        Returns: Json
      }
      admin_grant_pet_food: {
        Args: { p_code: string; p_quantity: number; p_telegram_id: number }
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
      admin_hero_detail: {
        Args: { p_admin_id: number; p_hero_key: string }
        Returns: Json
      }
      admin_list_audit: {
        Args: { p_admin_id: number; p_limit?: number; p_offset?: number }
        Returns: Json
      }
      admin_list_heroes: {
        Args: { p_admin_id: number; p_limit?: number; p_offset?: number }
        Returns: Json
      }
      admin_list_pets: {
        Args: { p_admin_id: number; p_limit?: number; p_offset?: number }
        Returns: Json
      }
      admin_list_transactions: {
        Args: {
          p_admin_id: number
          p_kind: string
          p_limit?: number
          p_status?: string
        }
        Returns: Json
      }
      admin_log: {
        Args: {
          p_action: string
          p_admin_id: number
          p_context?: Json
          p_new: Json
          p_old: Json
          p_reason?: string
          p_target_id: string
          p_target_type: string
        }
        Returns: string
      }
      admin_missions_overview: { Args: { p_admin_id: number }; Returns: Json }
      admin_pass_overview: { Args: { p_admin_id: number }; Returns: Json }
      admin_pet_config: { Args: { p_admin_id: number }; Returns: Json }
      admin_player_detail: {
        Args: { p_admin_id: number; p_ref: string }
        Returns: Json
      }
      admin_player_history: {
        Args: { p_admin_id: number; p_limit?: number; p_ref: string }
        Returns: Json
      }
      admin_pool_overview: { Args: { p_admin_id: number }; Returns: Json }
      admin_pvp_overview: {
        Args: { p_admin_id: number; p_top?: number }
        Returns: Json
      }
      admin_referral_tree: {
        Args: { p_admin_id: number; p_ref: string }
        Returns: Json
      }
      admin_remove_hero: {
        Args: { p_admin_id: number; p_hero_id: string; p_reason?: string }
        Returns: Json
      }
      admin_remove_pet: {
        Args: { p_admin_id: number; p_player_pet_id: string; p_reason?: string }
        Returns: Json
      }
      admin_reset_account: {
        Args: { p_admin_id: number; p_reason: string; p_ref: string }
        Returns: Json
      }
      admin_reset_missions: {
        Args: { p_admin_id: number; p_reason: string; p_scope: string }
        Returns: Json
      }
      admin_reset_pvp_season: {
        Args: { p_admin_id: number; p_reason: string }
        Returns: Json
      }
      admin_resolve_player: { Args: { p_ref: string }; Returns: string }
      admin_review_deposit: {
        Args: {
          p_admin_id: number
          p_approve: boolean
          p_deposit_id: string
          p_reason?: string
          p_tx_hash?: string
        }
        Returns: Json
      }
      admin_review_withdrawal: {
        Args: {
          p_admin_id: number
          p_reason?: string
          p_status: string
          p_tx_hash?: string
          p_withdrawal_id: string
        }
        Returns: Json
      }
      admin_search_players: {
        Args: { p_admin_id: number; p_limit?: number; p_query: string }
        Returns: Json
      }
      admin_set_ban: {
        Args: {
          p_admin_id: number
          p_banned: boolean
          p_reason: string
          p_ref: string
        }
        Returns: Json
      }
      admin_set_hero_rarity_rates: {
        Args: {
          p_admin_id: number
          p_normalize?: boolean
          p_rates: Json
          p_reason?: string
        }
        Returns: Json
      }
      admin_set_membership: {
        Args: {
          p_admin_id: number
          p_days: number
          p_reason?: string
          p_ref: string
          p_tier: string
        }
        Returns: Json
      }
      admin_set_pet_enabled: {
        Args: { p_enabled: boolean; p_pet_id: string }
        Returns: undefined
      }
      admin_set_pet_setting: {
        Args: { p_key: string; p_value: Json }
        Returns: undefined
      }
      admin_set_referral_percent: {
        Args: {
          p_admin_id: number
          p_level: number
          p_percent: number
          p_reason?: string
        }
        Returns: Json
      }
      admin_set_setting: {
        Args: {
          p_admin_id: number
          p_key: string
          p_reason?: string
          p_value: Json
        }
        Returns: Json
      }
      admin_status_overview: { Args: { p_admin_id: number }; Returns: Json }
      admin_super_id: { Args: never; Returns: number }
      admin_unlink_referral: {
        Args: { p_admin_id: number; p_reason: string; p_ref: string }
        Returns: Json
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
      admin_update_pet_evolution_tier: {
        Args: {
          p_chance: number
          p_enabled: boolean
          p_fc: number
          p_fragments: number
          p_max_buffs: number
          p_multiplier: number
          p_required_level: number
          p_tier: number
        }
        Returns: {
          enabled: boolean
          evolution_stage: string
          fc_cost: number
          fragment_cost: number
          label: string
          max_secondary_buffs: number
          new_buff_chance: number
          primary_multiplier: number
          required_level: number
          tier: number
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "pet_evolution_tiers"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      admin_update_pet_food: {
        Args: {
          p_code: string
          p_enabled: boolean
          p_name: string
          p_rarity: string
          p_xp: number
        }
        Returns: {
          code: string
          enabled: boolean
          icon: string
          name: string
          rarity: string
          sort_order: number
          updated_at: string
          xp_value: number
        }
        SetofOptions: {
          from: "*"
          to: "pet_food_items"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      admin_update_pool_settings: {
        Args: {
          p_days: number
          p_lottery: number
          p_minimum: number
          p_points: Json
          p_ranking: number
          p_ranking_config: Json
          p_revenue: Json
          p_winners: number
        }
        Returns: undefined
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
          p_tier: string
          p_title: string
          p_type: string
        }
        Returns: undefined
      }
      admin_upsert_ad_provider: {
        Args: {
          p_admin_id: number
          p_code: string
          p_patch: Json
          p_reason?: string
        }
        Returns: Json
      }
      admin_upsert_boss: {
        Args: {
          p_admin_id: number
          p_code: string
          p_patch: Json
          p_reason?: string
        }
        Returns: Json
      }
      admin_upsert_hero: {
        Args: {
          p_admin_id: number
          p_hero_key: string
          p_patch: Json
          p_reason?: string
        }
        Returns: Json
      }
      admin_upsert_league: {
        Args: {
          p_admin_id: number
          p_code: string
          p_patch: Json
          p_reason?: string
        }
        Returns: Json
      }
      admin_upsert_mission: {
        Args: {
          p_admin_id: number
          p_code: string
          p_patch: Json
          p_reason?: string
        }
        Returns: Json
      }
      admin_upsert_pet: {
        Args: {
          p_admin_id: number
          p_patch: Json
          p_reason?: string
          p_slug: string
        }
        Returns: Json
      }
      admin_upsert_pet_food: {
        Args: {
          p_admin_id: number
          p_code: string
          p_patch: Json
          p_reason?: string
        }
        Returns: Json
      }
      award_pool_points: {
        Args: { p_activity: string; p_source_id: string; p_user_id: string }
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
      distribute_community_pool: {
        Args: { p_force?: boolean }
        Returns: string
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
      evolve_pet: {
        Args: {
          p_idempotency_key: string
          p_player_pet_id: string
          p_telegram_id: number
        }
        Returns: Json
      }
      feed_pet: {
        Args: { p_food: number; p_player_pet_id: string; p_telegram_id: number }
        Returns: Json
      }
      feed_pet_item: {
        Args: {
          p_food_code: string
          p_idempotency_key: string
          p_player_pet_id: string
          p_quantity: number
          p_telegram_id: number
        }
        Returns: Json
      }
      feed_pet_v2: {
        Args: {
          p_food: number
          p_idempotency_key: string
          p_player_pet_id: string
          p_telegram_id: number
        }
        Returns: Json
      }
      finish_wallet_withdrawal: {
        Args: { p_status: string; p_tx_hash?: string; p_withdrawal_id: string }
        Returns: undefined
      }
      generate_missing_hero_stats: { Args: never; Returns: number }
      get_boss_combat: { Args: { p_telegram_id: number }; Returns: Json }
      get_calendar_dashboard: { Args: { p_telegram_id: number }; Returns: Json }
      get_community_pool_dashboard: {
        Args: { p_telegram_id: number }
        Returns: Json
      }
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
      get_runtime_config: { Args: { p_telegram_id?: number }; Returns: Json }
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
      open_season_mythic_egg: {
        Args: { p_item_id: string; p_telegram_id: number }
        Returns: Json
      }
      pet_evolution_cost: { Args: { r: string; v: number }; Returns: number }
      pet_evolution_stage: { Args: { v: number }; Returns: string }
      pet_level_xp_required: { Args: { p_level: number }; Returns: number }
      pet_max_level: { Args: never; Returns: number }
      pet_rarity_multiplier: { Args: { v: string }; Returns: number }
      pet_tier_multiplier: { Args: { p_tier: number }; Returns: number }
      pet_xp_required: { Args: { v: number }; Returns: number }
      player_pet_buffs: { Args: { p_player_pet_id: string }; Returns: Json }
      player_pet_json: { Args: { p_player_pet_id: string }; Returns: Json }
      pool_record_revenue: {
        Args: {
          p_amount_ton: number
          p_source_id: string
          p_source_type: string
          p_user_id: string
        }
        Returns: undefined
      }
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
      setting_bool: {
        Args: { p_default: boolean; p_key: string }
        Returns: boolean
      }
      setting_json: { Args: { p_key: string }; Returns: Json }
      setting_num: {
        Args: { p_default: number; p_key: string }
        Returns: number
      }
      setting_text: {
        Args: { p_default: string; p_key: string }
        Returns: string
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
      upgrade_pet_v2: {
        Args: {
          p_idempotency_key: string
          p_player_pet_id: string
          p_telegram_id: number
        }
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
