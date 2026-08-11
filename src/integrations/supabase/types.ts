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
      admin_bot_sessions: {
        Row: {
          action: string
          admin_telegram_id: number
          chat_id: number
          context: Json
          created_at: string
          expires_at: string
          id: string
          step: string
          updated_at: string
        }
        Insert: {
          action: string
          admin_telegram_id: number
          chat_id: number
          context?: Json
          created_at?: string
          expires_at?: string
          id?: string
          step?: string
          updated_at?: string
        }
        Update: {
          action?: string
          admin_telegram_id?: number
          chat_id?: number
          context?: Json
          created_at?: string
          expires_at?: string
          id?: string
          step?: string
          updated_at?: string
        }
        Relationships: []
      }
      admin_gifts: {
        Row: {
          admin_id: number
          created_at: string
          fc_amount: number
          gift_code: string
          gift_type: string
          id: string
          item_key: string | null
          item_label: string | null
          quantity: number
          result: Json
          status: string
          telegram_id: number | null
          user_id: string
        }
        Insert: {
          admin_id: number
          created_at?: string
          fc_amount?: number
          gift_code: string
          gift_type: string
          id?: string
          item_key?: string | null
          item_label?: string | null
          quantity?: number
          result?: Json
          status?: string
          telegram_id?: number | null
          user_id: string
        }
        Update: {
          admin_id?: number
          created_at?: string
          fc_amount?: number
          gift_code?: string
          gift_type?: string
          id?: string
          item_key?: string | null
          item_label?: string | null
          quantity?: number
          result?: Json
          status?: string
          telegram_id?: number | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "admin_gifts_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
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
          cycle_id: string | null
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
          cycle_id?: string | null
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
          cycle_id?: string | null
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
            foreignKeyName: "boss_combats_cycle_id_fkey"
            columns: ["cycle_id"]
            isOneToOne: false
            referencedRelation: "global_boss_cycles"
            referencedColumns: ["id"]
          },
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
      boss_team_slots: {
        Row: {
          created_at: string
          player_hero_id: string
          slot: number
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          player_hero_id: string
          slot: number
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          player_hero_id?: string
          slot?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "boss_team_slots_player_hero_id_fkey"
            columns: ["player_hero_id"]
            isOneToOne: false
            referencedRelation: "player_heroes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "boss_team_slots_user_id_fkey"
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
          duration_seconds: number
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
          duration_seconds?: number
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
          duration_seconds?: number
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
          result_hero_id: string | null
          result_hero_image: string | null
          result_hero_key: string | null
          result_hero_name: string | null
          result_rarity: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          idempotency_key: string
          inventory_item_id: string
          result_hero_id?: string | null
          result_hero_image?: string | null
          result_hero_key?: string | null
          result_hero_name?: string | null
          result_rarity: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          idempotency_key?: string
          inventory_item_id?: string
          result_hero_id?: string | null
          result_hero_image?: string | null
          result_hero_key?: string | null
          result_hero_name?: string | null
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
      calendar_repair_audit: {
        Row: {
          calendar_cycle: string
          claim_id: string
          claimed_at: string
          created_at: string
          day: number
          game_day: string | null
          id: string
          reason: string
          user_id: string
        }
        Insert: {
          calendar_cycle: string
          claim_id: string
          claimed_at: string
          created_at?: string
          day: number
          game_day?: string | null
          id?: string
          reason: string
          user_id: string
        }
        Update: {
          calendar_cycle?: string
          claim_id?: string
          claimed_at?: string
          created_at?: string
          day?: number
          game_day?: string | null
          id?: string
          reason?: string
          user_id?: string
        }
        Relationships: []
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
      channel_reward_config: {
        Row: {
          channel_key: string
          chat_ref: string | null
          created_at: string
          enabled: boolean
          reward_fc: number
          sort_order: number
          subtitle: string
          title: string
          updated_at: string
          url: string
        }
        Insert: {
          channel_key: string
          chat_ref?: string | null
          created_at?: string
          enabled?: boolean
          reward_fc?: number
          sort_order?: number
          subtitle: string
          title: string
          updated_at?: string
          url: string
        }
        Update: {
          channel_key?: string
          chat_ref?: string | null
          created_at?: string
          enabled?: boolean
          reward_fc?: number
          sort_order?: number
          subtitle?: string
          title?: string
          updated_at?: string
          url?: string
        }
        Relationships: []
      }
      chest_reward_tables: {
        Row: {
          chest_code: string
          created_at: string
          enabled: boolean
          name: string
          rarity_rates: Json
          subtitle: string
          updated_at: string
        }
        Insert: {
          chest_code: string
          created_at?: string
          enabled?: boolean
          name: string
          rarity_rates: Json
          subtitle?: string
          updated_at?: string
        }
        Update: {
          chest_code?: string
          created_at?: string
          enabled?: boolean
          name?: string
          rarity_rates?: Json
          subtitle?: string
          updated_at?: string
        }
        Relationships: []
      }
      clan_boss_cycles: {
        Row: {
          clan_id: string
          current_health: number
          ends_at: string
          finished_at: string | null
          id: string
          max_health: number
          name: string
          reward_points: number
          started_at: string
          status: string
        }
        Insert: {
          clan_id: string
          current_health?: number
          ends_at?: string
          finished_at?: string | null
          id?: string
          max_health?: number
          name?: string
          reward_points?: number
          started_at?: string
          status?: string
        }
        Update: {
          clan_id?: string
          current_health?: number
          ends_at?: string
          finished_at?: string | null
          id?: string
          max_health?: number
          name?: string
          reward_points?: number
          started_at?: string
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "clan_boss_cycles_clan_id_fkey"
            columns: ["clan_id"]
            isOneToOne: false
            referencedRelation: "clans"
            referencedColumns: ["id"]
          },
        ]
      }
      clan_boss_participants: {
        Row: {
          attacks: number
          cycle_id: string
          damage: number
          id: string
          last_attack_at: string | null
          user_id: string
        }
        Insert: {
          attacks?: number
          cycle_id: string
          damage?: number
          id?: string
          last_attack_at?: string | null
          user_id: string
        }
        Update: {
          attacks?: number
          cycle_id?: string
          damage?: number
          id?: string
          last_attack_at?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "clan_boss_participants_cycle_id_fkey"
            columns: ["cycle_id"]
            isOneToOne: false
            referencedRelation: "clan_boss_cycles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "clan_boss_participants_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      clan_join_requests: {
        Row: {
          clan_id: string
          created_at: string
          id: string
          status: string
          user_id: string
        }
        Insert: {
          clan_id: string
          created_at?: string
          id?: string
          status?: string
          user_id: string
        }
        Update: {
          clan_id?: string
          created_at?: string
          id?: string
          status?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "clan_join_requests_clan_id_fkey"
            columns: ["clan_id"]
            isOneToOne: false
            referencedRelation: "clans"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "clan_join_requests_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      clan_members: {
        Row: {
          clan_id: string
          clan_points: number
          contribution: number
          id: string
          joined_at: string
          role: string
          updated_at: string
          user_id: string
        }
        Insert: {
          clan_id: string
          clan_points?: number
          contribution?: number
          id?: string
          joined_at?: string
          role?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          clan_id?: string
          clan_points?: number
          contribution?: number
          id?: string
          joined_at?: string
          role?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "clan_members_clan_id_fkey"
            columns: ["clan_id"]
            isOneToOne: false
            referencedRelation: "clans"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "clan_members_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      clan_messages: {
        Row: {
          author_avatar: string | null
          author_name: string
          body: string
          clan_id: string
          created_at: string
          deleted: boolean
          id: string
          user_id: string | null
        }
        Insert: {
          author_avatar?: string | null
          author_name?: string
          body: string
          clan_id: string
          created_at?: string
          deleted?: boolean
          id?: string
          user_id?: string | null
        }
        Update: {
          author_avatar?: string | null
          author_name?: string
          body?: string
          clan_id?: string
          created_at?: string
          deleted?: boolean
          id?: string
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "clan_messages_clan_id_fkey"
            columns: ["clan_id"]
            isOneToOne: false
            referencedRelation: "clans"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "clan_messages_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      clan_mission_progress: {
        Row: {
          clan_id: string
          completed: boolean
          completed_at: string | null
          id: string
          mission_code: string
          progress: number
          updated_at: string
          week_key: string
        }
        Insert: {
          clan_id: string
          completed?: boolean
          completed_at?: string | null
          id?: string
          mission_code: string
          progress?: number
          updated_at?: string
          week_key: string
        }
        Update: {
          clan_id?: string
          completed?: boolean
          completed_at?: string | null
          id?: string
          mission_code?: string
          progress?: number
          updated_at?: string
          week_key?: string
        }
        Relationships: [
          {
            foreignKeyName: "clan_mission_progress_clan_id_fkey"
            columns: ["clan_id"]
            isOneToOne: false
            referencedRelation: "clans"
            referencedColumns: ["id"]
          },
        ]
      }
      clan_missions: {
        Row: {
          active: boolean
          code: string
          created_at: string
          id: string
          metric: string
          reward_points: number
          reward_xp: number
          target: number
          title: string
          updated_at: string
        }
        Insert: {
          active?: boolean
          code: string
          created_at?: string
          id?: string
          metric: string
          reward_points?: number
          reward_xp?: number
          target: number
          title: string
          updated_at?: string
        }
        Update: {
          active?: boolean
          code?: string
          created_at?: string
          id?: string
          metric?: string
          reward_points?: number
          reward_xp?: number
          target?: number
          title?: string
          updated_at?: string
        }
        Relationships: []
      }
      clan_points_ledger: {
        Row: {
          amount: number
          clan_id: string
          created_at: string
          id: string
          reason: string
          user_id: string | null
        }
        Insert: {
          amount: number
          clan_id: string
          created_at?: string
          id?: string
          reason: string
          user_id?: string | null
        }
        Update: {
          amount?: number
          clan_id?: string
          created_at?: string
          id?: string
          reason?: string
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "clan_points_ledger_clan_id_fkey"
            columns: ["clan_id"]
            isOneToOne: false
            referencedRelation: "clans"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "clan_points_ledger_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      clan_wars: {
        Row: {
          clan_a: string | null
          clan_b: string | null
          created_at: string
          ends_at: string | null
          id: string
          score_a: number
          score_b: number
          starts_at: string | null
          status: string
        }
        Insert: {
          clan_a?: string | null
          clan_b?: string | null
          created_at?: string
          ends_at?: string | null
          id?: string
          score_a?: number
          score_b?: number
          starts_at?: string | null
          status?: string
        }
        Update: {
          clan_a?: string | null
          clan_b?: string | null
          created_at?: string
          ends_at?: string | null
          id?: string
          score_a?: number
          score_b?: number
          starts_at?: string | null
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "clan_wars_clan_a_fkey"
            columns: ["clan_a"]
            isOneToOne: false
            referencedRelation: "clans"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "clan_wars_clan_b_fkey"
            columns: ["clan_b"]
            isOneToOne: false
            referencedRelation: "clans"
            referencedColumns: ["id"]
          },
        ]
      }
      clan_xp_ledger: {
        Row: {
          clan_id: string
          created_at: string
          game_day: string
          id: string
          reference_id: string | null
          source: string
          user_id: string | null
          xp_amount: number
        }
        Insert: {
          clan_id: string
          created_at?: string
          game_day?: string
          id?: string
          reference_id?: string | null
          source: string
          user_id?: string | null
          xp_amount: number
        }
        Update: {
          clan_id?: string
          created_at?: string
          game_day?: string
          id?: string
          reference_id?: string | null
          source?: string
          user_id?: string | null
          xp_amount?: number
        }
        Relationships: [
          {
            foreignKeyName: "clan_xp_ledger_clan_id_fkey"
            columns: ["clan_id"]
            isOneToOne: false
            referencedRelation: "clans"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "clan_xp_ledger_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      clans: {
        Row: {
          clan_points: number
          created_at: string
          description: string
          emblem_config: Json
          id: string
          join_type: string
          leader_user_id: string
          level: number
          member_limit: number
          minimum_trophies: number
          name: string
          suspended: boolean
          tag: string
          total_power: number
          updated_at: string
          xp: number
        }
        Insert: {
          clan_points?: number
          created_at?: string
          description?: string
          emblem_config?: Json
          id?: string
          join_type?: string
          leader_user_id: string
          level?: number
          member_limit?: number
          minimum_trophies?: number
          name: string
          suspended?: boolean
          tag: string
          total_power?: number
          updated_at?: string
          xp?: number
        }
        Update: {
          clan_points?: number
          created_at?: string
          description?: string
          emblem_config?: Json
          id?: string
          join_type?: string
          leader_user_id?: string
          level?: number
          member_limit?: number
          minimum_trophies?: number
          name?: string
          suspended?: boolean
          tag?: string
          total_power?: number
          updated_at?: string
          xp?: number
        }
        Relationships: [
          {
            foreignKeyName: "clans_leader_user_id_fkey"
            columns: ["leader_user_id"]
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
          game_day: string
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
          game_day?: string
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
          game_day?: string
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
      event_results: {
        Row: {
          created_at: string
          event_id: string
          final_rank: number
          id: string
          note: string | null
          paid_at: string | null
          reward_ton: number
          status: string
          updated_at: string
          user_id: string
          valid_referrals: number
        }
        Insert: {
          created_at?: string
          event_id: string
          final_rank: number
          id?: string
          note?: string | null
          paid_at?: string | null
          reward_ton?: number
          status?: string
          updated_at?: string
          user_id: string
          valid_referrals?: number
        }
        Update: {
          created_at?: string
          event_id?: string
          final_rank?: number
          id?: string
          note?: string | null
          paid_at?: string | null
          reward_ton?: number
          status?: string
          updated_at?: string
          user_id?: string
          valid_referrals?: number
        }
        Relationships: [
          {
            foreignKeyName: "event_results_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "special_events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_results_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
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
          language: string
          language_locked: boolean
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
          language?: string
          language_locked?: boolean
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
          language?: string
          language_locked?: boolean
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
      global_boss_cycles: {
        Row: {
          boss_image: string | null
          boss_key: string
          boss_level: number
          boss_name: string
          created_at: string
          current_hp: number
          cycle_number: number
          defeated_at: string | null
          distributed_at: string | null
          ends_at: string | null
          id: string
          max_hp: number
          minimum_damage_fixed: number
          minimum_damage_percent: number
          minimum_reward_fc: number
          participants: number
          rank_bonus: Json
          rank_bonus_enabled: boolean
          reward_pool_fc: number
          starts_at: string
          status: string
          total_damage: number
          updated_at: string
        }
        Insert: {
          boss_image?: string | null
          boss_key: string
          boss_level?: number
          boss_name: string
          created_at?: string
          current_hp: number
          cycle_number: number
          defeated_at?: string | null
          distributed_at?: string | null
          ends_at?: string | null
          id?: string
          max_hp: number
          minimum_damage_fixed?: number
          minimum_damage_percent?: number
          minimum_reward_fc?: number
          participants?: number
          rank_bonus?: Json
          rank_bonus_enabled?: boolean
          reward_pool_fc?: number
          starts_at?: string
          status?: string
          total_damage?: number
          updated_at?: string
        }
        Update: {
          boss_image?: string | null
          boss_key?: string
          boss_level?: number
          boss_name?: string
          created_at?: string
          current_hp?: number
          cycle_number?: number
          defeated_at?: string | null
          distributed_at?: string | null
          ends_at?: string | null
          id?: string
          max_hp?: number
          minimum_damage_fixed?: number
          minimum_damage_percent?: number
          minimum_reward_fc?: number
          participants?: number
          rank_bonus?: Json
          rank_bonus_enabled?: boolean
          reward_pool_fc?: number
          starts_at?: string
          status?: string
          total_damage?: number
          updated_at?: string
        }
        Relationships: []
      }
      global_boss_participants: {
        Row: {
          attacks: number
          boss_cycle_id: string
          created_at: string
          damage_total: number
          final_rank: number | null
          id: string
          last_attack_at: string | null
          reward_amount: number
          reward_claimed: boolean
          telegram_id: number | null
          updated_at: string
          user_id: string
        }
        Insert: {
          attacks?: number
          boss_cycle_id: string
          created_at?: string
          damage_total?: number
          final_rank?: number | null
          id?: string
          last_attack_at?: string | null
          reward_amount?: number
          reward_claimed?: boolean
          telegram_id?: number | null
          updated_at?: string
          user_id: string
        }
        Update: {
          attacks?: number
          boss_cycle_id?: string
          created_at?: string
          damage_total?: number
          final_rank?: number | null
          id?: string
          last_attack_at?: string | null
          reward_amount?: number
          reward_claimed?: boolean
          telegram_id?: number | null
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "global_boss_participants_boss_cycle_id_fkey"
            columns: ["boss_cycle_id"]
            isOneToOne: false
            referencedRelation: "global_boss_cycles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "global_boss_participants_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      global_boss_reward_ledger: {
        Row: {
          boss_cycle_id: string
          damage_total: number
          distributed_at: string
          id: string
          rank: number | null
          reward_fc: number
          share_percent: number
          user_id: string
        }
        Insert: {
          boss_cycle_id: string
          damage_total?: number
          distributed_at?: string
          id?: string
          rank?: number | null
          reward_fc?: number
          share_percent?: number
          user_id: string
        }
        Update: {
          boss_cycle_id?: string
          damage_total?: number
          distributed_at?: string
          id?: string
          rank?: number | null
          reward_fc?: number
          share_percent?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "global_boss_reward_ledger_boss_cycle_id_fkey"
            columns: ["boss_cycle_id"]
            isOneToOne: false
            referencedRelation: "global_boss_cycles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "global_boss_reward_ledger_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
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
          fusion_pool_enabled: boolean
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
          fusion_pool_enabled?: boolean
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
          fusion_pool_enabled?: boolean
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
      hero_fusion_history: {
        Row: {
          atk_after: number
          atk_before: number
          cost_fc: number
          created_at: string
          from_stars: number
          hero_id: string
          hero_key: string
          hp_after: number
          hp_before: number
          id: string
          material_ids: string[]
          materials_consumed: number
          to_stars: number
          user_id: string
        }
        Insert: {
          atk_after: number
          atk_before: number
          cost_fc?: number
          created_at?: string
          from_stars: number
          hero_id: string
          hero_key: string
          hp_after: number
          hp_before: number
          id?: string
          material_ids?: string[]
          materials_consumed: number
          to_stars: number
          user_id: string
        }
        Update: {
          atk_after?: number
          atk_before?: number
          cost_fc?: number
          created_at?: string
          from_stars?: number
          hero_id?: string
          hero_key?: string
          hp_after?: number
          hp_before?: number
          id?: string
          material_ids?: string[]
          materials_consumed?: number
          to_stars?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "hero_fusion_history_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      hero_rarity_fusion_history: {
        Row: {
          created_at: string
          fragment_reward: number
          fusion_cost_fc: number
          id: string
          reward_hero_id: string | null
          reward_hero_key: string | null
          reward_hero_name: string | null
          rng_roll: number
          selected_hero_ids: string[]
          selected_hero_keys: string[]
          source_rarity: string
          success: boolean
          success_chance: number
          target_rarity: string
          user_id: string
        }
        Insert: {
          created_at?: string
          fragment_reward?: number
          fusion_cost_fc?: number
          id?: string
          reward_hero_id?: string | null
          reward_hero_key?: string | null
          reward_hero_name?: string | null
          rng_roll?: number
          selected_hero_ids?: string[]
          selected_hero_keys?: string[]
          source_rarity: string
          success?: boolean
          success_chance?: number
          target_rarity: string
          user_id: string
        }
        Update: {
          created_at?: string
          fragment_reward?: number
          fusion_cost_fc?: number
          id?: string
          reward_hero_id?: string | null
          reward_hero_key?: string | null
          reward_hero_name?: string | null
          rng_roll?: number
          selected_hero_ids?: string[]
          selected_hero_keys?: string[]
          source_rarity?: string
          success?: boolean
          success_chance?: number
          target_rarity?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "hero_rarity_fusion_history_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      hero_rarity_fusion_idempotency: {
        Row: {
          created_at: string
          key: string
          result: Json
          user_id: string
        }
        Insert: {
          created_at?: string
          key: string
          result?: Json
          user_id: string
        }
        Update: {
          created_at?: string
          key?: string
          result?: Json
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "hero_rarity_fusion_idempotency_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      payment_recovery_audit: {
        Row: {
          action: string
          admin_id: number
          amount_ton: number | null
          approved_at: string
          created_at: string
          id: string
          new_status: string | null
          order_id: string
          previous_status: string | null
          reason: string | null
          result: Json
          reward_amount: number | null
          reward_type: string | null
          transaction_type: string
          tx_hash: string | null
          user_id: string | null
        }
        Insert: {
          action: string
          admin_id: number
          amount_ton?: number | null
          approved_at?: string
          created_at?: string
          id?: string
          new_status?: string | null
          order_id: string
          previous_status?: string | null
          reason?: string | null
          result?: Json
          reward_amount?: number | null
          reward_type?: string | null
          transaction_type: string
          tx_hash?: string | null
          user_id?: string | null
        }
        Update: {
          action?: string
          admin_id?: number
          amount_ton?: number | null
          approved_at?: string
          created_at?: string
          id?: string
          new_status?: string | null
          order_id?: string
          previous_status?: string | null
          reason?: string | null
          result?: Json
          reward_amount?: number | null
          reward_type?: string | null
          transaction_type?: string
          tx_hash?: string | null
          user_id?: string | null
        }
        Relationships: []
      }
      payout_announcements: {
        Row: {
          attempts: number
          channel_id: string | null
          created_at: string
          last_error: string | null
          message_id: number | null
          sent_at: string | null
          status: string
          tx_hash: string | null
          updated_at: string
          withdrawal_id: string
        }
        Insert: {
          attempts?: number
          channel_id?: string | null
          created_at?: string
          last_error?: string | null
          message_id?: number | null
          sent_at?: string | null
          status?: string
          tx_hash?: string | null
          updated_at?: string
          withdrawal_id: string
        }
        Update: {
          attempts?: number
          channel_id?: string | null
          created_at?: string
          last_error?: string | null
          message_id?: number | null
          sent_at?: string | null
          status?: string
          tx_hash?: string | null
          updated_at?: string
          withdrawal_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "payout_announcements_withdrawal_id_fkey"
            columns: ["withdrawal_id"]
            isOneToOne: true
            referencedRelation: "wallet_withdrawals"
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
          approval_reason: string | null
          approved_at: string | null
          approved_by_admin: number | null
          confirmed_at: string | null
          created_at: string
          delivered_at: string | null
          egg_id: string
          expires_at: string
          id: string
          idempotency_key: string
          manually_approved: boolean
          paid_at: string | null
          payment_address: string
          payment_comment: string
          price_ton: number
          status: string
          tx_hash: string | null
          user_id: string
          verification_method: string
        }
        Insert: {
          amount_nano: string
          approval_reason?: string | null
          approved_at?: string | null
          approved_by_admin?: number | null
          confirmed_at?: string | null
          created_at?: string
          delivered_at?: string | null
          egg_id: string
          expires_at?: string
          id?: string
          idempotency_key: string
          manually_approved?: boolean
          paid_at?: string | null
          payment_address: string
          payment_comment: string
          price_ton: number
          status?: string
          tx_hash?: string | null
          user_id: string
          verification_method?: string
        }
        Update: {
          amount_nano?: string
          approval_reason?: string | null
          approved_at?: string | null
          approved_by_admin?: number | null
          confirmed_at?: string | null
          created_at?: string
          delivered_at?: string | null
          egg_id?: string
          expires_at?: string
          id?: string
          idempotency_key?: string
          manually_approved?: boolean
          paid_at?: string | null
          payment_address?: string
          payment_comment?: string
          price_ton?: number
          status?: string
          tx_hash?: string | null
          user_id?: string
          verification_method?: string
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
          player_pet_id: string | null
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
          player_pet_id?: string | null
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
          player_pet_id?: string | null
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
          price_fc: number
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
          price_fc?: number
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
          price_fc?: number
          rarity?: string
          sort_order?: number
          updated_at?: string
          xp_value?: number
        }
        Relationships: []
      }
      pet_hatch_history: {
        Row: {
          completed_at: string | null
          created_at: string
          duplicate_fragments: number
          egg_id: string
          failure_reason: string | null
          id: string
          idempotency_key: string
          is_new: boolean
          opening_id: string
          result_pet_id: string | null
          result_player_pet_id: string | null
          result_rarity: string | null
          seed_hash: string
          status: string
          user_id: string
        }
        Insert: {
          completed_at?: string | null
          created_at?: string
          duplicate_fragments?: number
          egg_id: string
          failure_reason?: string | null
          id?: string
          idempotency_key: string
          is_new?: boolean
          opening_id: string
          result_pet_id?: string | null
          result_player_pet_id?: string | null
          result_rarity?: string | null
          seed_hash: string
          status?: string
          user_id: string
        }
        Update: {
          completed_at?: string | null
          created_at?: string
          duplicate_fragments?: number
          egg_id?: string
          failure_reason?: string | null
          id?: string
          idempotency_key?: string
          is_new?: boolean
          opening_id?: string
          result_pet_id?: string | null
          result_player_pet_id?: string | null
          result_rarity?: string | null
          seed_hash?: string
          status?: string
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
      pet_purchase_idempotency: {
        Row: {
          created_at: string
          idempotency_key: string
          user_id: string
        }
        Insert: {
          created_at?: string
          idempotency_key: string
          user_id: string
        }
        Update: {
          created_at?: string
          idempotency_key?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "pet_purchase_idempotency_user_id_fkey"
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
      pet_transactions: {
        Row: {
          balance_after: number | null
          balance_before: number | null
          created_at: string
          event: string
          fc_cost: number
          id: string
          item_name: string | null
          item_ref: string | null
          item_type: string | null
          metadata: Json
          quantity: number
          telegram_id: number | null
          user_id: string
        }
        Insert: {
          balance_after?: number | null
          balance_before?: number | null
          created_at?: string
          event: string
          fc_cost?: number
          id?: string
          item_name?: string | null
          item_ref?: string | null
          item_type?: string | null
          metadata?: Json
          quantity?: number
          telegram_id?: number | null
          user_id: string
        }
        Update: {
          balance_after?: number | null
          balance_before?: number | null
          created_at?: string
          event?: string
          fc_cost?: number
          id?: string
          item_name?: string | null
          item_ref?: string | null
          item_type?: string | null
          metadata?: Json
          quantity?: number
          telegram_id?: number | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "pet_transactions_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      pet_upgrade_history: {
        Row: {
          action: string
          created_at: string
          fc_spent: number
          food_code: string | null
          food_spent: number
          fragments_spent: number
          id: string
          new_level: number | null
          old_level: number | null
          player_pet_id: string | null
          user_id: string
          xp_added: number | null
          xp_after: number | null
          xp_before: number | null
        }
        Insert: {
          action?: string
          created_at?: string
          fc_spent?: number
          food_code?: string | null
          food_spent?: number
          fragments_spent?: number
          id?: string
          new_level?: number | null
          old_level?: number | null
          player_pet_id?: string | null
          user_id: string
          xp_added?: number | null
          xp_after?: number | null
          xp_before?: number | null
        }
        Update: {
          action?: string
          created_at?: string
          fc_spent?: number
          food_code?: string | null
          food_spent?: number
          fragments_spent?: number
          id?: string
          new_level?: number | null
          old_level?: number | null
          player_pet_id?: string | null
          user_id?: string
          xp_added?: number | null
          xp_after?: number | null
          xp_before?: number | null
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
          fusion_level: number
          hero_key: string
          hero_template_id: string | null
          hp_growth: number
          id: string
          image: string | null
          is_season_exclusive: boolean
          level: number
          locked: boolean
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
          fusion_level?: number
          hero_key: string
          hero_template_id?: string | null
          hp_growth: number
          id?: string
          image?: string | null
          is_season_exclusive?: boolean
          level?: number
          locked?: boolean
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
          fusion_level?: number
          hero_key?: string
          hero_template_id?: string | null
          hp_growth?: number
          id?: string
          image?: string | null
          is_season_exclusive?: boolean
          level?: number
          locked?: boolean
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
          dedupe_key: string | null
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
          dedupe_key?: string | null
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
          dedupe_key?: string | null
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
      player_quest_bonus: {
        Row: {
          claimed_at: string
          id: string
          item_code: string
          item_type: string
          quantity: number
          quest_date: string
          user_id: string
        }
        Insert: {
          claimed_at?: string
          id?: string
          item_code: string
          item_type: string
          quantity?: number
          quest_date: string
          user_id: string
        }
        Update: {
          claimed_at?: string
          id?: string
          item_code?: string
          item_type?: string
          quantity?: number
          quest_date?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "player_quest_bonus_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      player_quest_progress: {
        Row: {
          claimed_at: string | null
          completed_at: string | null
          id: string
          progress: number
          quest_code: string
          quest_date: string
          updated_at: string
          user_id: string
        }
        Insert: {
          claimed_at?: string | null
          completed_at?: string | null
          id?: string
          progress?: number
          quest_code: string
          quest_date: string
          updated_at?: string
          user_id: string
        }
        Update: {
          claimed_at?: string | null
          completed_at?: string | null
          id?: string
          progress?: number
          quest_code?: string
          quest_date?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "player_quest_progress_quest_code_fkey"
            columns: ["quest_code"]
            isOneToOne: false
            referencedRelation: "quest_definitions"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "player_quest_progress_user_id_fkey"
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
          tx_hash: string | null
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
          tx_hash?: string | null
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
          tx_hash?: string | null
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
          community_pool_percent: number
          id: boolean
          lottery_share_percent: number
          lottery_winner_count: number
          minimum_heroes: number
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
          community_pool_percent?: number
          id?: boolean
          lottery_share_percent?: number
          lottery_winner_count?: number
          minimum_heroes?: number
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
          community_pool_percent?: number
          id?: boolean
          lottery_share_percent?: number
          lottery_winner_count?: number
          minimum_heroes?: number
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
      processed_ton_transactions: {
        Row: {
          amount_nano: number
          processed_at: string
          reference_id: string
          transaction_type: string
          tx_hash: string
          user_id: string | null
        }
        Insert: {
          amount_nano: number
          processed_at?: string
          reference_id: string
          transaction_type: string
          tx_hash: string
          user_id?: string | null
        }
        Update: {
          amount_nano?: number
          processed_at?: string
          reference_id?: string
          transaction_type?: string
          tx_hash?: string
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "processed_ton_transactions_user_id_fkey"
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
      pvp_ticket_purchases: {
        Row: {
          amount_fc: number
          created_at: string
          daily_count_after: number
          daily_count_before: number
          id: string
          idempotency_key: string
          purchase_date: string
          tickets: number
          updated_at: string
          user_id: string
        }
        Insert: {
          amount_fc: number
          created_at?: string
          daily_count_after?: number
          daily_count_before?: number
          id?: string
          idempotency_key: string
          purchase_date: string
          tickets: number
          updated_at?: string
          user_id: string
        }
        Update: {
          amount_fc?: number
          created_at?: string
          daily_count_after?: number
          daily_count_before?: number
          id?: string
          idempotency_key?: string
          purchase_date?: string
          tickets?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "pvp_ticket_purchases_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      quest_definitions: {
        Row: {
          code: string
          description: string
          enabled: boolean
          event_key: string
          icon: string | null
          reward_fc: number
          reward_item_code: string | null
          reward_item_quantity: number
          reward_item_type: string | null
          sort_order: number
          target_amount: number
          title: string
          updated_at: string
        }
        Insert: {
          code: string
          description?: string
          enabled?: boolean
          event_key: string
          icon?: string | null
          reward_fc?: number
          reward_item_code?: string | null
          reward_item_quantity?: number
          reward_item_type?: string | null
          sort_order?: number
          target_amount?: number
          title: string
          updated_at?: string
        }
        Update: {
          code?: string
          description?: string
          enabled?: boolean
          event_key?: string
          icon?: string | null
          reward_fc?: number
          reward_item_code?: string | null
          reward_item_quantity?: number
          reward_item_type?: string | null
          sort_order?: number
          target_amount?: number
          title?: string
          updated_at?: string
        }
        Relationships: []
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
      referral_event_entries: {
        Row: {
          created_at: string
          event_id: string
          id: string
          invalid_reason: string | null
          is_valid: boolean
          referred_at: string
          referred_user_id: string
          referrer_user_id: string
        }
        Insert: {
          created_at?: string
          event_id: string
          id?: string
          invalid_reason?: string | null
          is_valid?: boolean
          referred_at?: string
          referred_user_id: string
          referrer_user_id: string
        }
        Update: {
          created_at?: string
          event_id?: string
          id?: string
          invalid_reason?: string | null
          is_valid?: boolean
          referred_at?: string
          referred_user_id?: string
          referrer_user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "referral_event_entries_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "special_events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "referral_event_entries_referred_user_id_fkey"
            columns: ["referred_user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "referral_event_entries_referrer_user_id_fkey"
            columns: ["referrer_user_id"]
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
      reward_open_logs: {
        Row: {
          created_at: string
          fallback_from: string | null
          id: string
          item_key: string
          item_type: string
          reward_id: string | null
          reward_name: string | null
          rolled_rarity: string | null
          source: string
          telegram_id: number | null
          user_id: string
        }
        Insert: {
          created_at?: string
          fallback_from?: string | null
          id?: string
          item_key: string
          item_type: string
          reward_id?: string | null
          reward_name?: string | null
          rolled_rarity?: string | null
          source?: string
          telegram_id?: number | null
          user_id: string
        }
        Update: {
          created_at?: string
          fallback_from?: string | null
          id?: string
          item_key?: string
          item_type?: string
          reward_id?: string | null
          reward_name?: string | null
          rolled_rarity?: string | null
          source?: string
          telegram_id?: number | null
          user_id?: string
        }
        Relationships: []
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
      season_pass_level_purchases: {
        Row: {
          created_at: string
          fc_spent: number
          id: string
          idempotency_key: string
          level_after: number
          level_before: number
          levels_bought: number
          purchase_date: string
          season_id: string | null
          user_id: string
          xp_after: number
          xp_before: number
        }
        Insert: {
          created_at?: string
          fc_spent: number
          id?: string
          idempotency_key: string
          level_after: number
          level_before: number
          levels_bought: number
          purchase_date: string
          season_id?: string | null
          user_id: string
          xp_after: number
          xp_before: number
        }
        Update: {
          created_at?: string
          fc_spent?: number
          id?: string
          idempotency_key?: string
          level_after?: number
          level_before?: number
          levels_bought?: number
          purchase_date?: string
          season_id?: string | null
          user_id?: string
          xp_after?: number
          xp_before?: number
        }
        Relationships: [
          {
            foreignKeyName: "season_pass_level_purchases_season_id_fkey"
            columns: ["season_id"]
            isOneToOne: false
            referencedRelation: "season_pass_seasons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "season_pass_level_purchases_user_id_fkey"
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
          approval_reason: string | null
          approved_at: string | null
          approved_by_admin: number | null
          created_at: string
          expires_at: string
          id: string
          idempotency_key: string
          manually_approved: boolean
          paid_at: string | null
          payment_address: string
          payment_comment: string
          price_ton: number
          season_id: string
          status: string
          tier: string
          tx_hash: string | null
          user_id: string
          verification_method: string
        }
        Insert: {
          activated_at?: string | null
          amount_nano: string
          approval_reason?: string | null
          approved_at?: string | null
          approved_by_admin?: number | null
          created_at?: string
          expires_at?: string
          id?: string
          idempotency_key: string
          manually_approved?: boolean
          paid_at?: string | null
          payment_address: string
          payment_comment: string
          price_ton: number
          season_id: string
          status?: string
          tier: string
          tx_hash?: string | null
          user_id: string
          verification_method?: string
        }
        Update: {
          activated_at?: string | null
          amount_nano?: string
          approval_reason?: string | null
          approved_at?: string | null
          approved_by_admin?: number | null
          created_at?: string
          expires_at?: string
          id?: string
          idempotency_key?: string
          manually_approved?: boolean
          paid_at?: string | null
          payment_address?: string
          payment_comment?: string
          price_ton?: number
          season_id?: string
          status?: string
          tier?: string
          tx_hash?: string | null
          user_id?: string
          verification_method?: string
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
          base_amount: number | null
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
          base_amount?: number | null
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
          base_amount?: number | null
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
      season_pass_xp_ledger: {
        Row: {
          base_xp: number | null
          created_at: string
          game_day: string | null
          id: string
          level_after: number
          level_before: number
          multiplier: number
          reference_id: string | null
          season_id: string
          source: string
          user_id: string
          xp_after: number
          xp_amount: number
          xp_before: number
        }
        Insert: {
          base_xp?: number | null
          created_at?: string
          game_day?: string | null
          id?: string
          level_after: number
          level_before: number
          multiplier?: number
          reference_id?: string | null
          season_id: string
          source: string
          user_id: string
          xp_after: number
          xp_amount: number
          xp_before: number
        }
        Update: {
          base_xp?: number | null
          created_at?: string
          game_day?: string | null
          id?: string
          level_after?: number
          level_before?: number
          multiplier?: number
          reference_id?: string | null
          season_id?: string
          source?: string
          user_id?: string
          xp_after?: number
          xp_amount?: number
          xp_before?: number
        }
        Relationships: [
          {
            foreignKeyName: "season_pass_xp_ledger_season_id_fkey"
            columns: ["season_id"]
            isOneToOne: false
            referencedRelation: "season_pass_seasons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "season_pass_xp_ledger_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      special_events: {
        Row: {
          created_at: string
          ends_at: string
          event_end_at: string | null
          event_key: string
          event_start_at: string | null
          id: string
          name: string
          prize_pool_ton: number
          rules_json: Json
          starts_at: string
          status: string
          type: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          ends_at: string
          event_end_at?: string | null
          event_key: string
          event_start_at?: string | null
          id?: string
          name: string
          prize_pool_ton?: number
          rules_json?: Json
          starts_at?: string
          status?: string
          type?: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          ends_at?: string
          event_end_at?: string | null
          event_key?: string
          event_start_at?: string | null
          id?: string
          name?: string
          prize_pool_ton?: number
          rules_json?: Json
          starts_at?: string
          status?: string
          type?: string
          updated_at?: string
        }
        Relationships: []
      }
      ton_payment_logs: {
        Row: {
          blockchain_status: string | null
          created_at: string
          destination_wallet: string | null
          error_detail: string | null
          expected_amount_nano: string | null
          fulfillment_status: string | null
          id: string
          order_id: string | null
          order_kind: string
          payment_reference: string | null
          product_id: string | null
          received_amount_nano: string | null
          telegram_id: number | null
          tx_hash: string | null
          user_id: string | null
        }
        Insert: {
          blockchain_status?: string | null
          created_at?: string
          destination_wallet?: string | null
          error_detail?: string | null
          expected_amount_nano?: string | null
          fulfillment_status?: string | null
          id?: string
          order_id?: string | null
          order_kind: string
          payment_reference?: string | null
          product_id?: string | null
          received_amount_nano?: string | null
          telegram_id?: number | null
          tx_hash?: string | null
          user_id?: string | null
        }
        Update: {
          blockchain_status?: string | null
          created_at?: string
          destination_wallet?: string | null
          error_detail?: string | null
          expected_amount_nano?: string | null
          fulfillment_status?: string | null
          id?: string
          order_id?: string | null
          order_kind?: string
          payment_reference?: string | null
          product_id?: string | null
          received_amount_nano?: string | null
          telegram_id?: number | null
          tx_hash?: string | null
          user_id?: string | null
        }
        Relationships: []
      }
      user_channel_rewards: {
        Row: {
          channel_key: string
          claimed_at: string | null
          created_at: string
          id: string
          joined_verified: boolean
          reward_amount: number
          reward_claimed: boolean
          telegram_id: number
          updated_at: string
          user_id: string
          verified_at: string | null
        }
        Insert: {
          channel_key: string
          claimed_at?: string | null
          created_at?: string
          id?: string
          joined_verified?: boolean
          reward_amount?: number
          reward_claimed?: boolean
          telegram_id: number
          updated_at?: string
          user_id: string
          verified_at?: string | null
        }
        Update: {
          channel_key?: string
          claimed_at?: string | null
          created_at?: string
          id?: string
          joined_verified?: boolean
          reward_amount?: number
          reward_claimed?: boolean
          telegram_id?: number
          updated_at?: string
          user_id?: string
          verified_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "user_channel_rewards_channel_key_fkey"
            columns: ["channel_key"]
            isOneToOne: false
            referencedRelation: "channel_reward_config"
            referencedColumns: ["channel_key"]
          },
          {
            foreignKeyName: "user_channel_rewards_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      wallet_deposits: {
        Row: {
          amount_fc: number
          amount_ton: number
          approval_reason: string | null
          approved_at: string | null
          approved_by_admin: number | null
          confirmed_at: string | null
          conversion_rate: number
          created_at: string
          credited_at: string | null
          expires_at: string
          from_wallet: string | null
          id: string
          idempotency_key: string
          manually_approved: boolean
          payment_comment: string
          status: string
          tx_hash: string | null
          user_id: string
          verification_method: string
        }
        Insert: {
          amount_fc: number
          amount_ton: number
          approval_reason?: string | null
          approved_at?: string | null
          approved_by_admin?: number | null
          confirmed_at?: string | null
          conversion_rate?: number
          created_at?: string
          credited_at?: string | null
          expires_at?: string
          from_wallet?: string | null
          id?: string
          idempotency_key: string
          manually_approved?: boolean
          payment_comment: string
          status?: string
          tx_hash?: string | null
          user_id: string
          verification_method?: string
        }
        Update: {
          amount_fc?: number
          amount_ton?: number
          approval_reason?: string | null
          approved_at?: string | null
          approved_by_admin?: number | null
          confirmed_at?: string | null
          conversion_rate?: number
          created_at?: string
          credited_at?: string | null
          expires_at?: string
          from_wallet?: string | null
          id?: string
          idempotency_key?: string
          manually_approved?: boolean
          payment_comment?: string
          status?: string
          tx_hash?: string | null
          user_id?: string
          verification_method?: string
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
      wallet_ledger: {
        Row: {
          amount_fc: number
          amount_ton: number | null
          balance_after: number
          balance_before: number
          conversion_rate: number | null
          created_at: string
          id: string
          reference_id: string | null
          tx_hash: string | null
          type: string
          user_id: string
        }
        Insert: {
          amount_fc?: number
          amount_ton?: number | null
          balance_after?: number
          balance_before?: number
          conversion_rate?: number | null
          created_at?: string
          id?: string
          reference_id?: string | null
          tx_hash?: string | null
          type: string
          user_id: string
        }
        Update: {
          amount_fc?: number
          amount_ton?: number | null
          balance_after?: number
          balance_before?: number
          conversion_rate?: number | null
          created_at?: string
          id?: string
          reference_id?: string | null
          tx_hash?: string | null
          type?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "wallet_ledger_user_id_fkey"
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
          admin_id: number | null
          amount_fc: number
          amount_ton: number
          created_at: string
          fee_percent: number
          fee_ton: number
          gross_ton: number | null
          id: string
          idempotency_key: string
          net_ton: number | null
          paid_at: string | null
          processed_at: string | null
          refunded_at: string | null
          status: string
          telegram_id: number | null
          tx_hash: string | null
          user_id: string
          username: string | null
          wallet_address: string | null
          wallet_resolution_required: boolean
        }
        Insert: {
          admin_id?: number | null
          amount_fc: number
          amount_ton: number
          created_at?: string
          fee_percent?: number
          fee_ton?: number
          gross_ton?: number | null
          id?: string
          idempotency_key: string
          net_ton?: number | null
          paid_at?: string | null
          processed_at?: string | null
          refunded_at?: string | null
          status?: string
          telegram_id?: number | null
          tx_hash?: string | null
          user_id: string
          username?: string | null
          wallet_address?: string | null
          wallet_resolution_required?: boolean
        }
        Update: {
          admin_id?: number | null
          amount_fc?: number
          amount_ton?: number
          created_at?: string
          fee_percent?: number
          fee_ton?: number
          gross_ton?: number | null
          id?: string
          idempotency_key?: string
          net_ton?: number | null
          paid_at?: string | null
          processed_at?: string | null
          refunded_at?: string | null
          status?: string
          telegram_id?: number | null
          tx_hash?: string | null
          user_id?: string
          username?: string | null
          wallet_address?: string | null
          wallet_resolution_required?: boolean
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
      payment_recovery_orders: {
        Row: {
          amount_ton: number | null
          approval_reason: string | null
          approved_at: string | null
          approved_by_admin: number | null
          created_at: string | null
          delivered_at: string | null
          finished: boolean | null
          kind: string | null
          manually_approved: boolean | null
          order_id: string | null
          paid_at: string | null
          product_label: string | null
          status: string | null
          tx_hash: string | null
          type_label: string | null
          user_id: string | null
          verification_method: string | null
        }
        Relationships: []
      }
    }
    Functions: {
      activate_pet: {
        Args: { p_player_pet_id: string; p_telegram_id: number }
        Returns: Json
      }
      active_boss_template: {
        Args: never
        Returns: {
          active: boolean
          attack: number
          attack_interval_seconds: number
          attack_limit: number | null
          code: string
          cooldown_seconds: number
          created_at: string
          defense: number
          difficulty: string
          duration_seconds: number
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
        SetofOptions: {
          from: "*"
          to: "boss_templates"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      add_universal_fragments: {
        Args: { p_quantity: number; p_user_id: string }
        Returns: number
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
      admin_adjust_pass_xp: {
        Args: {
          p_admin_id: number
          p_delta: number
          p_reason?: string
          p_ref: string
        }
        Returns: Json
      }
      admin_adjust_player_item: {
        Args: {
          p_admin_id: number
          p_delta: number
          p_item_key: string
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
          p_value?: number
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
      admin_channel_rewards_overview: {
        Args: { p_admin_id: number }
        Returns: Json
      }
      admin_channels_overview: { Args: { p_admin_id: number }; Returns: Json }
      admin_chest_diagnostics: { Args: { p_admin_id: number }; Returns: Json }
      admin_clan_settings: {
        Args: { p_action?: string; p_admin_id: number; p_value?: number }
        Returns: Json
      }
      admin_clans: {
        Args: {
          p_action?: string
          p_admin_id: number
          p_payload?: Json
          p_ref?: string
        }
        Returns: Json
      }
      admin_connected_wallets: {
        Args: { p_admin_id: number; p_limit?: number; p_query?: string }
        Returns: Json
      }
      admin_create_snapshot: {
        Args: { p_admin_id: number; p_label: string }
        Returns: Json
      }
      admin_delete_catalog_hero: {
        Args: { p_admin_id: number; p_hero_key: string; p_reason?: string }
        Returns: Json
      }
      admin_events: {
        Args: {
          p_action: string
          p_admin_id: number
          p_payload?: Json
          p_ref?: string
        }
        Returns: Json
      }
      admin_game_day_state: { Args: { p_admin_id: number }; Returns: Json }
      admin_get_settings: {
        Args: { p_admin_id: number; p_category?: string }
        Returns: Json
      }
      admin_gift_catalog: {
        Args: { p_admin_id: number; p_kind: string; p_rarity?: string }
        Returns: Json
      }
      admin_gift_history: {
        Args: { p_admin_id: number; p_limit?: number }
        Returns: Json
      }
      admin_global_boss: {
        Args: {
          p_action?: string
          p_admin_id: number
          p_code?: string
          p_reason?: string
          p_text?: string
          p_value?: number
        }
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
      admin_hero_shop_overview: { Args: { p_admin_id: number }; Returns: Json }
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
      admin_list_withdrawals: {
        Args: { p_admin_id: number; p_limit?: number; p_status?: string }
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
      admin_next_hero_key: {
        Args: { p_admin_id: number; p_name: string }
        Returns: string
      }
      admin_pass_history: {
        Args: { p_admin_id: number; p_limit?: number }
        Returns: Json
      }
      admin_pass_overview: { Args: { p_admin_id: number }; Returns: Json }
      admin_payment_recovery: {
        Args: {
          p_action: string
          p_admin_id: number
          p_payload?: Json
          p_ref?: string
        }
        Returns: Json
      }
      admin_payout_announcement_claim: {
        Args: { p_admin_id: number; p_withdrawal_id: string }
        Returns: Json
      }
      admin_payout_announcement_record: {
        Args: {
          p_admin_id: number
          p_channel_id?: string
          p_error?: string
          p_message_id?: number
          p_status: string
          p_withdrawal_id: string
        }
        Returns: Json
      }
      admin_payout_announcements: {
        Args: { p_admin_id: number; p_limit?: number }
        Returns: Json
      }
      admin_pet_config: { Args: { p_admin_id: number }; Returns: Json }
      admin_player_channel_claims: {
        Args: { p_admin_id: number; p_player: string }
        Returns: Json
      }
      admin_player_detail: {
        Args: { p_admin_id: number; p_ref: string }
        Returns: Json
      }
      admin_player_heroes: {
        Args: {
          p_admin_id: number
          p_limit?: number
          p_offset?: number
          p_rarity?: string
          p_ref: string
        }
        Returns: Json
      }
      admin_player_history: {
        Args: { p_admin_id: number; p_limit?: number; p_ref: string }
        Returns: Json
      }
      admin_player_items: {
        Args: { p_admin_id: number; p_ref: string }
        Returns: Json
      }
      admin_player_pass: {
        Args: { p_admin_id: number; p_ref: string }
        Returns: Json
      }
      admin_player_pets: {
        Args: { p_admin_id: number; p_ref: string }
        Returns: Json
      }
      admin_pool_overview: { Args: { p_admin_id: number }; Returns: Json }
      admin_pvp_overview: {
        Args: { p_admin_id: number; p_top?: number }
        Returns: Json
      }
      admin_quests_overview: { Args: { p_admin_id: number }; Returns: Json }
      admin_rarity_fusion_audit: {
        Args: { p_admin_id: number; p_limit?: number; p_ref?: string }
        Returns: Json
      }
      admin_rarity_fusion_overview: {
        Args: { p_admin_id: number }
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
      admin_remove_player_hero: {
        Args: { p_admin_id: number; p_hero_id: string; p_reason?: string }
        Returns: Json
      }
      admin_repair_daily_quests: { Args: { p_admin_id: number }; Returns: Json }
      admin_reset_account: {
        Args: { p_admin_id: number; p_reason: string; p_ref: string }
        Returns: Json
      }
      admin_reset_channel_claim: {
        Args: { p_admin_id: number; p_channel_key: string; p_player: string }
        Returns: Json
      }
      admin_reset_hero_shop: {
        Args: { p_admin_id: number; p_scope?: string }
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
      admin_reset_quests: {
        Args: { p_admin_id: number; p_reason?: string }
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
      admin_search_heroes: {
        Args: { p_admin_id: number; p_limit?: number; p_query?: string }
        Returns: Json
      }
      admin_search_players:
        | {
            Args: { p_admin_id: number; p_limit?: number; p_query: string }
            Returns: Json
          }
        | {
            Args: {
              p_admin_id: number
              p_limit?: number
              p_offset?: number
              p_query: string
            }
            Returns: Json
          }
      admin_send_gift: {
        Args: {
          p_admin_id: number
          p_gift_code: string
          p_item_key: string
          p_quantity: number
          p_ref: string
          p_type: string
        }
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
      admin_set_channel_chat_ref: {
        Args: { p_admin_id: number; p_channel_key: string; p_chat_ref: string }
        Returns: Json
      }
      admin_set_channel_reward: {
        Args: {
          p_admin_id: number
          p_channel_key: string
          p_enabled?: boolean
          p_reward_fc?: number
        }
        Returns: Json
      }
      admin_set_fragment_config: {
        Args: { p_admin_id: number; p_quantity?: number; p_rates?: Json }
        Returns: Json
      }
      admin_set_fusion_config: {
        Args: { p_admin_id: number; p_patch: Json; p_reason?: string }
        Returns: Json
      }
      admin_set_global_boss_reward: {
        Args: {
          p_admin_id: number
          p_code?: string
          p_reason?: string
          p_scope: string
          p_value: number
        }
        Returns: Json
      }
      admin_set_hero_fusion_pool: {
        Args: { p_admin_id: number; p_enabled: boolean; p_hero_key: string }
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
      admin_set_hero_recruit_price: {
        Args: {
          p_admin_id: number
          p_count: number
          p_price: number
          p_reason?: string
        }
        Returns: Json
      }
      admin_set_hero_summon_rates: {
        Args: { p_admin_id: number; p_rates: Json; p_reason?: string }
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
      admin_set_pass_fc_multiplier: {
        Args: { p_admin_id: number; p_multiplier: number }
        Returns: Json
      }
      admin_set_pass_level: {
        Args: {
          p_admin_id: number
          p_level: number
          p_reason?: string
          p_ref: string
        }
        Returns: Json
      }
      admin_set_pass_level_purchase: {
        Args: { p_admin_id: number; p_patch: Json; p_reason?: string }
        Returns: Json
      }
      admin_set_pass_xp_caps: {
        Args: { p_admin_id: number; p_patch: Json; p_reason?: string }
        Returns: Json
      }
      admin_set_pass_xp_multipliers: {
        Args: { p_admin_id: number; p_patch: Json; p_reason?: string }
        Returns: Json
      }
      admin_set_pass_xp_settings: {
        Args: { p_admin_id: number; p_patch: Json; p_reason?: string }
        Returns: Json
      }
      admin_set_pet_enabled: {
        Args: { p_enabled: boolean; p_pet_id: string }
        Returns: undefined
      }
      admin_set_pet_food_price: {
        Args: { p_admin_id: number; p_code: string; p_price: number }
        Returns: {
          code: string
          enabled: boolean
          icon: string
          name: string
          price_fc: number
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
      admin_set_pet_setting: {
        Args: { p_key: string; p_value: Json }
        Returns: undefined
      }
      admin_set_player_active_pet: {
        Args: { p_admin_id: number; p_player_pet_id: string; p_reason?: string }
        Returns: Json
      }
      admin_set_player_pass: {
        Args: {
          p_admin_id: number
          p_reason?: string
          p_ref: string
          p_tier: string
        }
        Returns: Json
      }
      admin_set_pool_contribution_percent: {
        Args: { p_admin_id: number; p_percent: number }
        Returns: Json
      }
      admin_set_pvp_ticket_pack: {
        Args: { p_admin_id: number; p_price_fc: number; p_quantity: number }
        Returns: Json
      }
      admin_set_quest_bonus: {
        Args: {
          p_admin_id: number
          p_item_code: string
          p_item_type: string
          p_name: string
          p_quantity?: number
        }
        Returns: Json
      }
      admin_set_quest_timezone: {
        Args: { p_admin_id: number; p_timezone: string }
        Returns: Json
      }
      admin_set_rarity_fusion_enabled: {
        Args: { p_admin_id: number; p_enabled: boolean }
        Returns: Json
      }
      admin_set_rarity_fusion_tier: {
        Args: {
          p_admin_id: number
          p_chance?: number
          p_cost?: number
          p_fragments?: number
          p_source: string
        }
        Returns: Json
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
      admin_set_withdraw_fee_percent: {
        Args: { p_admin_id: number; p_percent: number }
        Returns: Json
      }
      admin_status_overview: { Args: { p_admin_id: number }; Returns: Json }
      admin_super_id: { Args: never; Returns: number }
      admin_unlink_referral: {
        Args: { p_admin_id: number; p_reason: string; p_ref: string }
        Returns: Json
      }
      admin_update_channel: {
        Args: { p_admin_id: number; p_channel_key: string; p_patch: Json }
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
          price_fc: number
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
      admin_upsert_quest: {
        Args: {
          p_admin_id: number
          p_code: string
          p_patch: Json
          p_reason?: string
        }
        Returns: Json
      }
      admin_withdrawal_detail: {
        Args: { p_admin_id: number; p_withdrawal_id: string }
        Returns: Json
      }
      admin_withdrawal_lock: {
        Args: { p_admin_id: number; p_withdrawal_id: string }
        Returns: Json
      }
      admin_withdrawal_mark_paid: {
        Args: { p_admin_id: number; p_tx_hash: string; p_withdrawal_id: string }
        Returns: Json
      }
      admin_withdrawal_reject: {
        Args: { p_admin_id: number; p_reason?: string; p_withdrawal_id: string }
        Returns: Json
      }
      admin_withdrawal_unlock: {
        Args: { p_admin_id: number; p_reason?: string; p_withdrawal_id: string }
        Returns: Json
      }
      attack_boss: { Args: { p_telegram_id: number }; Returns: Json }
      audit_player_deposits: { Args: { p_telegram_id: number }; Returns: Json }
      award_pool_points: {
        Args: { p_activity: string; p_source_id: string; p_user_id: string }
        Returns: undefined
      }
      bind_referral: {
        Args: { p_inviter_telegram_id: number; p_telegram_id: number }
        Returns: Json
      }
      boss_team_json: { Args: { p_user: string }; Returns: Json }
      buy_pet_egg: {
        Args: {
          p_egg_id: string
          p_idempotency_key?: string
          p_quantity?: number
          p_telegram_id: number
        }
        Returns: Json
      }
      buy_pet_food: {
        Args: {
          p_food_code: string
          p_idempotency_key?: string
          p_quantity?: number
          p_telegram_id: number
        }
        Returns: Json
      }
      buy_pvp_tickets: {
        Args: {
          p_idempotency_key: string
          p_quantity: number
          p_telegram_id: number
        }
        Returns: Json
      }
      buy_season_pass_levels: {
        Args: {
          p_idempotency_key: string
          p_levels: number
          p_telegram_id: number
        }
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
      chest_rates_sum_ok: { Args: { p_rates: Json }; Returns: boolean }
      claim_boss_reward: { Args: { p_telegram_id: number }; Returns: Json }
      claim_calendar_day: {
        Args: { p_day: number; p_telegram_id: number }
        Returns: Json
      }
      claim_channel_reward: {
        Args: {
          p_channel_key: string
          p_membership_ok?: boolean
          p_telegram_id: number
        }
        Returns: Json
      }
      claim_daily_quest: {
        Args: { p_quest_code: string; p_telegram_id: number }
        Returns: Json
      }
      claim_daily_quest_chest: {
        Args: { p_telegram_id: number }
        Returns: Json
      }
      claim_season_pass_reward: {
        Args: { p_reward_id: string; p_telegram_id: number }
        Returns: Json
      }
      clan_boss_attack: { Args: { p_telegram_id: number }; Returns: Json }
      clan_chat: {
        Args: {
          p_action?: string
          p_body?: string
          p_message_id?: string
          p_telegram_id: number
        }
        Returns: Json
      }
      clan_level_xp: { Args: { p_level: number }; Returns: number }
      clan_manage: {
        Args: {
          p_action: string
          p_payload?: Json
          p_target?: string
          p_telegram_id: number
        }
        Returns: Json
      }
      clan_member_limit: { Args: { p_level: number }; Returns: number }
      clan_player_power: { Args: { p_user_id: string }; Returns: number }
      clan_public: {
        Args: { p_clan: Database["public"]["Tables"]["clans"]["Row"] }
        Returns: Json
      }
      clan_resolve_user: { Args: { p_telegram_id: number }; Returns: string }
      clan_role_rank: { Args: { p_role: string }; Returns: number }
      clan_shop_buy: {
        Args: { p_item: string; p_quantity?: number; p_telegram_id: number }
        Returns: Json
      }
      clan_week_key: { Args: never; Returns: string }
      confirm_pet_egg_order: {
        Args: { p_amount_nano: string; p_order_id: string; p_tx_hash: string }
        Returns: undefined
      }
      confirm_pet_egg_purchase: {
        Args: { p_amount_nano: string; p_order_id: string; p_tx_hash: string }
        Returns: Json
      }
      confirm_season_pass_order: {
        Args: { p_amount_nano: string; p_order_id: string; p_tx_hash: string }
        Returns: Json
      }
      confirm_wallet_deposit: {
        Args: { p_amount_nano: string; p_deposit_id: string; p_tx_hash: string }
        Returns: Json
      }
      create_clan: {
        Args: {
          p_description: string
          p_emblem: Json
          p_join_type: string
          p_min_trophies: number
          p_name: string
          p_tag: string
          p_telegram_id: number
        }
        Returns: Json
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
      current_ton_fc_rate: { Args: never; Returns: number }
      deliver_pet_egg_order: { Args: { p_order_id: string }; Returns: Json }
      distribute_community_pool: {
        Args: { p_force?: boolean }
        Returns: string
      }
      distribute_global_boss_rewards: {
        Args: { p_cycle_id: string }
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
      ensure_active_pool: { Args: never; Returns: string }
      ensure_boss_combat: { Args: { p_telegram_id: number }; Returns: string }
      ensure_global_boss_cycle: {
        Args: never
        Returns: {
          boss_image: string | null
          boss_key: string
          boss_level: number
          boss_name: string
          created_at: string
          current_hp: number
          cycle_number: number
          defeated_at: string | null
          distributed_at: string | null
          ends_at: string | null
          id: string
          max_hp: number
          minimum_damage_fixed: number
          minimum_damage_percent: number
          minimum_reward_fc: number
          participants: number
          rank_bonus: Json
          rank_bonus_enabled: boolean
          reward_pool_fc: number
          starts_at: string
          status: string
          total_damage: number
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "global_boss_cycles"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      equip_combat_hero: {
        Args: { p_hero_id: string; p_slot: number; p_telegram_id: number }
        Returns: Json
      }
      event_default_rules: { Args: never; Returns: Json }
      event_distribute: { Args: { p_event_id: string }; Returns: Json }
      event_finalize: { Args: { p_event_id: string }; Returns: Json }
      event_referral_ranking: {
        Args: { p_event_id: string; p_limit?: number }
        Returns: {
          avatar_url: string
          name: string
          rank_no: number
          user_id: string
          username: string
          valid_referrals: number
        }[]
      }
      event_reward_for_rank: {
        Args: {
          p_prize: number
          p_rank: number
          p_rules: Json
          p_total_valid: number
          p_valid: number
        }
        Returns: number
      }
      event_sync_statuses: { Args: never; Returns: undefined }
      evolve_pet: {
        Args: {
          p_idempotency_key: string
          p_player_pet_id: string
          p_telegram_id: number
        }
        Returns: Json
      }
      expire_stale_pet_egg_orders: {
        Args: { p_user_id?: string }
        Returns: number
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
      forge_random_seed: { Args: { p_salt?: string }; Returns: string }
      fuse_heroes: {
        Args: {
          p_main_hero_id: string
          p_material_ids: string[]
          p_telegram_id: number
        }
        Returns: Json
      }
      fuse_heroes_by_rarity: {
        Args: {
          p_hero_ids: string[]
          p_idempotency_key?: string
          p_telegram_id: number
        }
        Returns: Json
      }
      game_day_key: { Args: { p_at?: string }; Returns: string }
      game_day_number: { Args: { p_at?: string }; Returns: number }
      game_day_reset_hour: { Args: never; Returns: number }
      game_day_start: { Args: { p_day?: string }; Returns: string }
      game_day_state: { Args: never; Returns: Json }
      game_launch_day: { Args: never; Returns: string }
      game_next_reset_at: { Args: { p_at?: string }; Returns: string }
      game_timezone: { Args: never; Returns: string }
      generate_missing_hero_stats: { Args: never; Returns: number }
      get_boss_combat: { Args: { p_telegram_id: number }; Returns: Json }
      get_calendar_dashboard: { Args: { p_telegram_id: number }; Returns: Json }
      get_channel_rewards: { Args: { p_telegram_id: number }; Returns: Json }
      get_clan_dashboard: { Args: { p_telegram_id: number }; Returns: Json }
      get_community_pool_dashboard: {
        Args: { p_telegram_id: number }
        Returns: Json
      }
      get_daily_quests: { Args: { p_telegram_id: number }; Returns: Json }
      get_global_boss_history: {
        Args: { p_limit?: number; p_telegram_id: number }
        Returns: Json
      }
      get_global_boss_ranking: {
        Args: { p_limit?: number; p_telegram_id: number }
        Returns: Json
      }
      get_hero_fusion_dashboard: {
        Args: { p_telegram_id: number }
        Returns: Json
      }
      get_hero_shop_config: { Args: never; Returns: Json }
      get_pet_admin_stats: { Args: never; Returns: Json }
      get_pet_bonuses: { Args: { p_user: string }; Returns: Json }
      get_pet_dashboard: { Args: { p_telegram_id: number }; Returns: Json }
      get_pet_egg_opening: {
        Args: { p_opening_id: string; p_telegram_id: number }
        Returns: Json
      }
      get_pet_egg_store: { Args: { p_telegram_id: number }; Returns: Json }
      get_pet_pvp_snapshot: { Args: { p_user: string }; Returns: Json }
      get_player_inventory: { Args: { p_telegram_id: number }; Returns: Json }
      get_pvp_dashboard: { Args: { p_telegram_id: number }; Returns: Json }
      get_pvp_history: { Args: { p_telegram_id: number }; Returns: Json }
      get_pvp_ranking: { Args: never; Returns: Json }
      get_rarity_fusion_dashboard: {
        Args: { p_telegram_id: number }
        Returns: Json
      }
      get_recent_pass_xp: {
        Args: { p_since?: string; p_telegram_id: number }
        Returns: Json
      }
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
      get_reward_history: {
        Args: { p_limit?: number; p_offset?: number; p_telegram_id: number }
        Returns: Json
      }
      get_runtime_config: { Args: { p_telegram_id?: number }; Returns: Json }
      get_season_pass_dashboard: {
        Args: { p_telegram_id: number }
        Returns: Json
      }
      get_special_events_dashboard: {
        Args: { p_telegram_id: number }
        Returns: Json
      }
      get_wallet_summary: { Args: { p_telegram_id: number }; Returns: Json }
      global_boss_overlay: { Args: { p_user: string }; Returns: Json }
      grant_clan_xp: {
        Args: { p_amount?: number; p_source: string; p_user_id: string }
        Returns: undefined
      }
      grant_referral_milestones: {
        Args: { p_user_id: string }
        Returns: undefined
      }
      grant_season_pass_xp: {
        Args: {
          p_amount?: number
          p_reference_id?: string
          p_source: string
          p_user_id: string
        }
        Returns: Json
      }
      has_active_season_pass: { Args: { p_user_id: string }; Returns: string }
      hatch_pet_egg: {
        Args: {
          p_egg_id: string
          p_idempotency_key: string
          p_telegram_id: number
        }
        Returns: Json
      }
      hero_fusion_config: { Args: never; Returns: Json }
      hero_fusion_multiplier: { Args: { p_stars: number }; Returns: number }
      hero_max_level: { Args: { p_stars: number }; Returns: number }
      hero_rarity_fusion_config: { Args: never; Returns: Json }
      hero_recruit_price: { Args: { p_count: number }; Returns: number }
      hero_summon_rates: { Args: never; Returns: Json }
      is_valid_ton_address: { Args: { p_address: string }; Returns: boolean }
      join_clan: {
        Args: { p_clan_id: string; p_telegram_id: number }
        Returns: Json
      }
      leave_clan: { Args: { p_telegram_id: number }; Returns: Json }
      log_pet_transaction: {
        Args: {
          p_after: number
          p_before: number
          p_event: string
          p_fc: number
          p_item_name: string
          p_item_ref: string
          p_item_type: string
          p_meta?: Json
          p_quantity: number
          p_user_id: string
        }
        Returns: undefined
      }
      mark_notifications_read: {
        Args: { p_ids?: string[]; p_telegram_id: number }
        Returns: Json
      }
      normalize_hero_rarity: { Args: { value: string }; Returns: string }
      normalize_language_code: { Args: { p_code: string }; Returns: string }
      normalize_pet_rarity: { Args: { v: string }; Returns: string }
      open_calendar_hero_chest: {
        Args: { p_inventory_item_id: string; p_telegram_id: number }
        Returns: Json
      }
      open_hero_chest: {
        Args: {
          p_inventory_item_id: string
          p_source?: string
          p_telegram_id: number
        }
        Returns: Json
      }
      open_season_mythic_egg: {
        Args: { p_item_id: string; p_telegram_id: number }
        Returns: Json
      }
      payment_recovery_deliver: {
        Args: {
          p_admin_id: number
          p_force?: boolean
          p_order_id: string
          p_reason: string
        }
        Returns: Json
      }
      payment_recovery_order_json: {
        Args: { p_order_id: string }
        Returns: Json
      }
      payment_recovery_tx_conflict: {
        Args: { p_order_id: string; p_tx_hash: string }
        Returns: string
      }
      pending_pet_egg_orders: { Args: { p_telegram_id: number }; Returns: Json }
      pending_season_pass_orders: {
        Args: { p_telegram_id: number }
        Returns: Json
      }
      pending_wallet_deposits: {
        Args: { p_telegram_id: number }
        Returns: Json
      }
      pet_evolution_cost: { Args: { r: string; v: number }; Returns: number }
      pet_evolution_stage: { Args: { v: number }; Returns: string }
      pet_hatch_result_json: {
        Args: {
          p_history: Database["public"]["Tables"]["pet_hatch_history"]["Row"]
        }
        Returns: Json
      }
      pet_level_xp_required: { Args: { p_level: number }; Returns: number }
      pet_max_level: { Args: never; Returns: number }
      pet_rarity_multiplier: { Args: { v: string }; Returns: number }
      pet_tier_multiplier: { Args: { p_tier: number }; Returns: number }
      pet_xp_required: { Args: { v: number }; Returns: number }
      player_pet_buffs: { Args: { p_player_pet_id: string }; Returns: Json }
      player_pet_json: { Args: { p_player_pet_id: string }; Returns: Json }
      pool_eligibility: { Args: { p_user_id: string }; Returns: Json }
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
      pvp_ticket_packs: { Args: never; Returns: Json }
      pvp_ticket_shop_state: { Args: { p_user_id: string }; Returns: Json }
      quest_timezone: { Args: never; Returns: string }
      quest_today: { Args: never; Returns: string }
      rarity_base_atk: { Args: { r: string }; Returns: number }
      rarity_base_hp: { Args: { r: string }; Returns: number }
      rarity_resistance: { Args: { r: string }; Returns: number }
      rates_allowed_rarities: { Args: { p_rates: Json }; Returns: string[] }
      reconcile_pet_egg_orders: {
        Args: { p_telegram_id: number }
        Returns: Json
      }
      record_clan_mission_progress: {
        Args: { p_amount?: number; p_metric: string; p_user_id: string }
        Returns: undefined
      }
      record_daily_quest_progress: {
        Args: { p_amount?: number; p_event: string; p_user_id: string }
        Returns: undefined
      }
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
      record_global_boss_damage: {
        Args: { p_cycle_id: string; p_damage: number; p_user: string }
        Returns: undefined
      }
      record_quest_event: {
        Args: { p_amount?: number; p_event: string; p_user_id: string }
        Returns: undefined
      }
      record_quest_event_for_telegram: {
        Args: { p_amount?: number; p_event: string; p_telegram_id: number }
        Returns: undefined
      }
      record_ton_revenue: {
        Args: {
          p_amount_ton: number
          p_reference_id: string
          p_source: string
          p_tx_hash?: string
          p_user_id: string
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
      roll_chest_rarity: {
        Args: {
          p_ancestral?: number
          p_common?: number
          p_epic?: number
          p_legendary?: number
          p_rare?: number
          p_uncommon?: number
        }
        Returns: {
          allowed: string[]
          rarity: string
        }[]
      }
      roll_hero_for_rarity: {
        Args: { p_allowed: string[]; p_rarity: string }
        Returns: Record<string, unknown>
      }
      roll_rarity_from_rates: {
        Args: { p_luck?: number; p_rates: Json }
        Returns: string
      }
      roll_universal_fragment_rarity: { Args: never; Returns: string }
      save_pvp_team_slot: {
        Args: {
          p_hero_id: string
          p_slot: number
          p_team_type: string
          p_telegram_id: number
        }
        Returns: Json
      }
      search_clans: {
        Args: { p_query?: string; p_telegram_id: number }
        Returns: Json
      }
      search_pvp_opponents: { Args: { p_telegram_id: number }; Returns: Json }
      season_pass_level_purchase_config: { Args: never; Returns: Json }
      season_pass_tier_multiplier: { Args: { p_tier: string }; Returns: number }
      season_pass_xp_caps: { Args: never; Returns: Json }
      season_pass_xp_config: { Args: never; Returns: Json }
      season_pass_xp_multipliers: { Args: never; Returns: Json }
      set_boss_team: {
        Args: { p_hero_ids: string[]; p_telegram_id: number }
        Returns: Json
      }
      set_hero_lock: {
        Args: { p_hero_id: string; p_locked: boolean; p_telegram_id: number }
        Returns: Json
      }
      set_player_language: {
        Args: { p_language: string; p_telegram_id: number }
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
      sync_boss_team_state: { Args: { p_user: string }; Returns: undefined }
      ton_pending_purchase_orders: {
        Args: { p_max_age_days?: number }
        Returns: {
          amount_nano: string
          created_at: string
          order_id: string
          order_kind: string
          payment_address: string
          payment_comment: string
          product_id: string
          telegram_id: number
          user_id: string
        }[]
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
      unequip_combat_hero: {
        Args: { p_slot: number; p_telegram_id: number }
        Returns: Json
      }
      universal_fragment_balance: {
        Args: { p_user_id: string }
        Returns: number
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
      upsert_telegram_player_profile:
        | {
            Args: {
              p_first_name: string
              p_last_name?: string
              p_photo_url?: string
              p_telegram_id: number
              p_username?: string
            }
            Returns: Json
          }
        | {
            Args: {
              p_first_name: string
              p_language_code?: string
              p_last_name?: string
              p_photo_url?: string
              p_telegram_id: number
              p_username?: string
            }
            Returns: Json
          }
      wallet_hot_address: { Args: never; Returns: string }
      withdraw_fee_percent: { Args: never; Returns: number }
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
