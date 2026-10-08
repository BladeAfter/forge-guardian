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
    PostgrestVersion: "14.5"
  }
  public: {
    Tables: {
      _market_probe: {
        Row: {
          k: string
          v: string | null
        }
        Insert: {
          k: string
          v?: string | null
        }
        Update: {
          k?: string
          v?: string | null
        }
        Relationships: []
      }
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
      ad_reward_claims: {
        Row: {
          ad_event_id: string
          amount_ton: number
          block_id: string | null
          created_at: string
          id: string
          reward_period: string
          rewarded_at: string | null
          source: string
          status: string
          updated_at: string
          user_id: string
        }
        Insert: {
          ad_event_id: string
          amount_ton?: number
          block_id?: string | null
          created_at?: string
          id?: string
          reward_period: string
          rewarded_at?: string | null
          source?: string
          status?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          ad_event_id?: string
          amount_ton?: number
          block_id?: string | null
          created_at?: string
          id?: string
          reward_period?: string
          rewarded_at?: string | null
          source?: string
          status?: string
          updated_at?: string
          user_id?: string
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
      adventurer_pack_config: {
        Row: {
          account_ton_bonus_percent: number
          enabled: boolean
          ends_at: string | null
          fc_reward: number
          grant_pass_tier: string
          hero_rarity: string
          id: boolean
          legendary_armors: number
          legendary_chests: number
          lock_mining_after_reveal: boolean
          max_reward_rarity: string
          nft_weapons: number
          package_version: string
          popup_enabled: boolean
          popup_frequency: string
          popup_priority: number
          price_ton: number
          purchase_limit: number
          random_items: number
          random_items_pool: Json
          reward_configuration_version: number
          sales_paused: boolean
          sold_out_visible: boolean
          start_at: string | null
          stock_total: number | null
          universal_fragments: number
          updated_at: string
        }
        Insert: {
          account_ton_bonus_percent?: number
          enabled?: boolean
          ends_at?: string | null
          fc_reward?: number
          grant_pass_tier?: string
          hero_rarity?: string
          id?: boolean
          legendary_armors?: number
          legendary_chests?: number
          lock_mining_after_reveal?: boolean
          max_reward_rarity?: string
          nft_weapons?: number
          package_version?: string
          popup_enabled?: boolean
          popup_frequency?: string
          popup_priority?: number
          price_ton?: number
          purchase_limit?: number
          random_items?: number
          random_items_pool?: Json
          reward_configuration_version?: number
          sales_paused?: boolean
          sold_out_visible?: boolean
          start_at?: string | null
          stock_total?: number | null
          universal_fragments?: number
          updated_at?: string
        }
        Update: {
          account_ton_bonus_percent?: number
          enabled?: boolean
          ends_at?: string | null
          fc_reward?: number
          grant_pass_tier?: string
          hero_rarity?: string
          id?: boolean
          legendary_armors?: number
          legendary_chests?: number
          lock_mining_after_reveal?: boolean
          max_reward_rarity?: string
          nft_weapons?: number
          package_version?: string
          popup_enabled?: boolean
          popup_frequency?: string
          popup_priority?: number
          price_ton?: number
          purchase_limit?: number
          random_items?: number
          random_items_pool?: Json
          reward_configuration_version?: number
          sales_paused?: boolean
          sold_out_visible?: boolean
          start_at?: string | null
          stock_total?: number | null
          universal_fragments?: number
          updated_at?: string
        }
        Relationships: []
      }
      adventurer_pack_items: {
        Row: {
          created_at: string
          id: string
          instance_id: string | null
          item_type: string
          mining_locked: boolean
          mining_pending_reveal: boolean
          purchase_id: string
          quantity: number
          rarity: string | null
          revealed_at: string | null
          revealed_myth: number | null
          revealed_ton: number | null
          template_id: string | null
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          instance_id?: string | null
          item_type: string
          mining_locked?: boolean
          mining_pending_reveal?: boolean
          purchase_id: string
          quantity?: number
          rarity?: string | null
          revealed_at?: string | null
          revealed_myth?: number | null
          revealed_ton?: number | null
          template_id?: string | null
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          instance_id?: string | null
          item_type?: string
          mining_locked?: boolean
          mining_pending_reveal?: boolean
          purchase_id?: string
          quantity?: number
          rarity?: string | null
          revealed_at?: string | null
          revealed_myth?: number | null
          revealed_ton?: number | null
          template_id?: string | null
          user_id?: string
        }
        Relationships: []
      }
      adventurer_pack_ledger: {
        Row: {
          created_at: string
          fc_amount: number | null
          id: string
          kind: string
          note: string | null
          purchase_id: string | null
          ton_amount: number | null
          user_id: string | null
        }
        Insert: {
          created_at?: string
          fc_amount?: number | null
          id?: string
          kind: string
          note?: string | null
          purchase_id?: string | null
          ton_amount?: number | null
          user_id?: string | null
        }
        Update: {
          created_at?: string
          fc_amount?: number | null
          id?: string
          kind?: string
          note?: string | null
          purchase_id?: string | null
          ton_amount?: number | null
          user_id?: string | null
        }
        Relationships: []
      }
      adventurer_pack_purchases: {
        Row: {
          bonus_percent_snapshot: number
          confirmed_at: string | null
          created_at: string
          delivered_at: string | null
          delivery: Json | null
          expected_nanoton: string
          expires_at: string
          fc_snapshot: number
          fragments_snapshot: number
          fulfillment_error: string | null
          id: string
          idempotency_key: string | null
          package_version: string
          pass_tier_snapshot: string
          payment_address: string | null
          payment_comment: string | null
          payment_method: string
          price_ton: number
          reward_configuration_version: number
          status: string
          telegram_id: number | null
          tx_hash: string | null
          user_id: string
        }
        Insert: {
          bonus_percent_snapshot?: number
          confirmed_at?: string | null
          created_at?: string
          delivered_at?: string | null
          delivery?: Json | null
          expected_nanoton: string
          expires_at?: string
          fc_snapshot?: number
          fragments_snapshot?: number
          fulfillment_error?: string | null
          id?: string
          idempotency_key?: string | null
          package_version: string
          pass_tier_snapshot?: string
          payment_address?: string | null
          payment_comment?: string | null
          payment_method?: string
          price_ton: number
          reward_configuration_version?: number
          status?: string
          telegram_id?: number | null
          tx_hash?: string | null
          user_id: string
        }
        Update: {
          bonus_percent_snapshot?: number
          confirmed_at?: string | null
          created_at?: string
          delivered_at?: string | null
          delivery?: Json | null
          expected_nanoton?: string
          expires_at?: string
          fc_snapshot?: number
          fragments_snapshot?: number
          fulfillment_error?: string | null
          id?: string
          idempotency_key?: string | null
          package_version?: string
          pass_tier_snapshot?: string
          payment_address?: string | null
          payment_comment?: string | null
          payment_method?: string
          price_ton?: number
          reward_configuration_version?: number
          status?: string
          telegram_id?: number | null
          tx_hash?: string | null
          user_id?: string
        }
        Relationships: []
      }
      adventurer_pack_reveal_audit: {
        Row: {
          admin_id: number
          id: string
          item_id: string
          item_instance_id: string | null
          item_type: string
          new_myth: number | null
          new_ton: number | null
          old_myth: number | null
          old_ton: number | null
          override: boolean
          purchase_id: string | null
          reason: string | null
          revealed_at: string
          user_id: string
        }
        Insert: {
          admin_id: number
          id?: string
          item_id: string
          item_instance_id?: string | null
          item_type: string
          new_myth?: number | null
          new_ton?: number | null
          old_myth?: number | null
          old_ton?: number | null
          override?: boolean
          purchase_id?: string | null
          reason?: string | null
          revealed_at?: string
          user_id: string
        }
        Update: {
          admin_id?: number
          id?: string
          item_id?: string
          item_instance_id?: string | null
          item_type?: string
          new_myth?: number | null
          new_ton?: number | null
          old_myth?: number | null
          old_ton?: number | null
          override?: boolean
          purchase_id?: string | null
          reason?: string | null
          revealed_at?: string
          user_id?: string
        }
        Relationships: []
      }
      ancient_ruin_rooms: {
        Row: {
          branch: number
          config: Json
          id: string
          resolved_at: string | null
          room_index: number
          room_type: string
          run_id: string
          status: string
        }
        Insert: {
          branch?: number
          config?: Json
          id?: string
          resolved_at?: string | null
          room_index: number
          room_type: string
          run_id: string
          status?: string
        }
        Update: {
          branch?: number
          config?: Json
          id?: string
          resolved_at?: string | null
          room_index?: number
          room_type?: string
          run_id?: string
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "ancient_ruin_rooms_run_id_fkey"
            columns: ["run_id"]
            isOneToOne: false
            referencedRelation: "ancient_ruin_runs"
            referencedColumns: ["id"]
          },
        ]
      }
      ancient_ruin_runs: {
        Row: {
          buffs: Json
          completed_at: string | null
          current_room: number
          entry_cost_fc: number
          entry_cost_ton: number
          entry_tier: string
          hp: number
          id: string
          loot: Json
          region_id: string
          ruin_coins: number
          seed: number
          started_at: string
          status: string
          user_id: string
        }
        Insert: {
          buffs?: Json
          completed_at?: string | null
          current_room?: number
          entry_cost_fc?: number
          entry_cost_ton?: number
          entry_tier?: string
          hp?: number
          id?: string
          loot?: Json
          region_id: string
          ruin_coins?: number
          seed: number
          started_at?: string
          status?: string
          user_id: string
        }
        Update: {
          buffs?: Json
          completed_at?: string | null
          current_room?: number
          entry_cost_fc?: number
          entry_cost_ton?: number
          entry_tier?: string
          hp?: number
          id?: string
          loot?: Json
          region_id?: string
          ruin_coins?: number
          seed?: number
          started_at?: string
          status?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "ancient_ruin_runs_region_id_fkey"
            columns: ["region_id"]
            isOneToOne: false
            referencedRelation: "realm_regions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ancient_ruin_runs_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      anti_fake_logs: {
        Row: {
          created_at: string
          device_hash: string | null
          event: string
          id: string
          metadata: Json
          telegram_id: number | null
        }
        Insert: {
          created_at?: string
          device_hash?: string | null
          event: string
          id?: string
          metadata?: Json
          telegram_id?: number | null
        }
        Update: {
          created_at?: string
          device_hash?: string | null
          event?: string
          id?: string
          metadata?: Json
          telegram_id?: number | null
        }
        Relationships: []
      }
      auction_bids: {
        Row: {
          amount_ton: number
          auction_id: string
          bidder_user_id: string
          created_at: string
          id: string
          idempotency_key: string | null
          status: string
        }
        Insert: {
          amount_ton: number
          auction_id: string
          bidder_user_id: string
          created_at?: string
          id?: string
          idempotency_key?: string | null
          status?: string
        }
        Update: {
          amount_ton?: number
          auction_id?: string
          bidder_user_id?: string
          created_at?: string
          id?: string
          idempotency_key?: string | null
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "auction_bids_auction_id_fkey"
            columns: ["auction_id"]
            isOneToOne: false
            referencedRelation: "auctions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "auction_bids_bidder_user_id_fkey"
            columns: ["bidder_user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      auction_ledger: {
        Row: {
          auction_id: string | null
          balance_after: number | null
          balance_before: number | null
          bid_id: string | null
          counterparty_user_id: string | null
          created_at: string
          details: Json
          event: string
          fee_ton: number | null
          gross_ton: number | null
          id: string
          net_ton: number | null
          user_id: string | null
        }
        Insert: {
          auction_id?: string | null
          balance_after?: number | null
          balance_before?: number | null
          bid_id?: string | null
          counterparty_user_id?: string | null
          created_at?: string
          details?: Json
          event: string
          fee_ton?: number | null
          gross_ton?: number | null
          id?: string
          net_ton?: number | null
          user_id?: string | null
        }
        Update: {
          auction_id?: string | null
          balance_after?: number | null
          balance_before?: number | null
          bid_id?: string | null
          counterparty_user_id?: string | null
          created_at?: string
          details?: Json
          event?: string
          fee_ton?: number | null
          gross_ton?: number | null
          id?: string
          net_ton?: number | null
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "auction_ledger_auction_id_fkey"
            columns: ["auction_id"]
            isOneToOne: false
            referencedRelation: "auctions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "auction_ledger_bid_id_fkey"
            columns: ["bid_id"]
            isOneToOne: false
            referencedRelation: "auction_bids"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "auction_ledger_counterparty_user_id_fkey"
            columns: ["counterparty_user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "auction_ledger_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      auctions: {
        Row: {
          bid_count: number
          created_at: string
          current_bid_ton: number | null
          ends_at: string
          fee_percent: number
          fee_ton: number | null
          final_price_ton: number | null
          finished_at: string | null
          highest_bidder_id: string | null
          id: string
          item_instance_id: string
          item_type: string
          min_increment_ton: number
          seller_net_ton: number | null
          seller_user_id: string
          snapshot: Json
          starting_bid_ton: number
          status: string
          updated_at: string
          winner_user_id: string | null
        }
        Insert: {
          bid_count?: number
          created_at?: string
          current_bid_ton?: number | null
          ends_at: string
          fee_percent?: number
          fee_ton?: number | null
          final_price_ton?: number | null
          finished_at?: string | null
          highest_bidder_id?: string | null
          id?: string
          item_instance_id: string
          item_type: string
          min_increment_ton?: number
          seller_net_ton?: number | null
          seller_user_id: string
          snapshot?: Json
          starting_bid_ton: number
          status?: string
          updated_at?: string
          winner_user_id?: string | null
        }
        Update: {
          bid_count?: number
          created_at?: string
          current_bid_ton?: number | null
          ends_at?: string
          fee_percent?: number
          fee_ton?: number | null
          final_price_ton?: number | null
          finished_at?: string | null
          highest_bidder_id?: string | null
          id?: string
          item_instance_id?: string
          item_type?: string
          min_increment_ton?: number
          seller_net_ton?: number | null
          seller_user_id?: string
          snapshot?: Json
          starting_bid_ton?: number
          status?: string
          updated_at?: string
          winner_user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "auctions_highest_bidder_id_fkey"
            columns: ["highest_bidder_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "auctions_seller_user_id_fkey"
            columns: ["seller_user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "auctions_winner_user_id_fkey"
            columns: ["winner_user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
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
      celestial_pack_config: {
        Row: {
          account_ton_bonus_percent: number
          armors: number
          enabled: boolean
          ends_at: string | null
          fc_reward: number
          id: boolean
          legendary_chests: number
          nft_weapons: number
          package_version: string
          popup_enabled: boolean
          popup_frequency: string
          popup_priority: number
          price_ton: number
          purchase_limit: number
          random_items: number
          random_items_pool: Json
          reward_configuration_version: number
          sales_paused: boolean
          sold_out_visible: boolean
          start_at: string | null
          stock_total: number | null
          updated_at: string
        }
        Insert: {
          account_ton_bonus_percent?: number
          armors?: number
          enabled?: boolean
          ends_at?: string | null
          fc_reward?: number
          id?: boolean
          legendary_chests?: number
          nft_weapons?: number
          package_version?: string
          popup_enabled?: boolean
          popup_frequency?: string
          popup_priority?: number
          price_ton?: number
          purchase_limit?: number
          random_items?: number
          random_items_pool?: Json
          reward_configuration_version?: number
          sales_paused?: boolean
          sold_out_visible?: boolean
          start_at?: string | null
          stock_total?: number | null
          updated_at?: string
        }
        Update: {
          account_ton_bonus_percent?: number
          armors?: number
          enabled?: boolean
          ends_at?: string | null
          fc_reward?: number
          id?: boolean
          legendary_chests?: number
          nft_weapons?: number
          package_version?: string
          popup_enabled?: boolean
          popup_frequency?: string
          popup_priority?: number
          price_ton?: number
          purchase_limit?: number
          random_items?: number
          random_items_pool?: Json
          reward_configuration_version?: number
          sales_paused?: boolean
          sold_out_visible?: boolean
          start_at?: string | null
          stock_total?: number | null
          updated_at?: string
        }
        Relationships: []
      }
      celestial_pack_items: {
        Row: {
          created_at: string
          id: string
          instance_id: string | null
          item_type: string
          mining_pending_reveal: boolean
          purchase_id: string
          revealed_at: string | null
          revealed_myth: number | null
          revealed_ton: number | null
          template_id: string | null
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          instance_id?: string | null
          item_type: string
          mining_pending_reveal?: boolean
          purchase_id: string
          revealed_at?: string | null
          revealed_myth?: number | null
          revealed_ton?: number | null
          template_id?: string | null
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          instance_id?: string | null
          item_type?: string
          mining_pending_reveal?: boolean
          purchase_id?: string
          revealed_at?: string | null
          revealed_myth?: number | null
          revealed_ton?: number | null
          template_id?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "celestial_pack_items_purchase_id_fkey"
            columns: ["purchase_id"]
            isOneToOne: false
            referencedRelation: "celestial_pack_purchases"
            referencedColumns: ["id"]
          },
        ]
      }
      celestial_pack_ledger: {
        Row: {
          created_at: string
          fc_amount: number | null
          id: string
          kind: string
          note: string | null
          purchase_id: string | null
          ton_amount: number | null
          user_id: string | null
        }
        Insert: {
          created_at?: string
          fc_amount?: number | null
          id?: string
          kind: string
          note?: string | null
          purchase_id?: string | null
          ton_amount?: number | null
          user_id?: string | null
        }
        Update: {
          created_at?: string
          fc_amount?: number | null
          id?: string
          kind?: string
          note?: string | null
          purchase_id?: string | null
          ton_amount?: number | null
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "celestial_pack_ledger_purchase_id_fkey"
            columns: ["purchase_id"]
            isOneToOne: false
            referencedRelation: "celestial_pack_purchases"
            referencedColumns: ["id"]
          },
        ]
      }
      celestial_pack_purchases: {
        Row: {
          bonus_percent_snapshot: number
          confirmed_at: string | null
          created_at: string
          delivered_at: string | null
          delivery: Json | null
          expected_nanoton: string
          expires_at: string
          fc_snapshot: number
          id: string
          idempotency_key: string | null
          package_version: string
          payment_address: string | null
          payment_comment: string | null
          payment_method: string
          price_ton: number
          reward_configuration_version: number
          status: string
          telegram_id: number | null
          tx_hash: string | null
          user_id: string
        }
        Insert: {
          bonus_percent_snapshot?: number
          confirmed_at?: string | null
          created_at?: string
          delivered_at?: string | null
          delivery?: Json | null
          expected_nanoton: string
          expires_at?: string
          fc_snapshot?: number
          id?: string
          idempotency_key?: string | null
          package_version: string
          payment_address?: string | null
          payment_comment?: string | null
          payment_method?: string
          price_ton: number
          reward_configuration_version?: number
          status?: string
          telegram_id?: number | null
          tx_hash?: string | null
          user_id: string
        }
        Update: {
          bonus_percent_snapshot?: number
          confirmed_at?: string | null
          created_at?: string
          delivered_at?: string | null
          delivery?: Json | null
          expected_nanoton?: string
          expires_at?: string
          fc_snapshot?: number
          id?: string
          idempotency_key?: string | null
          package_version?: string
          payment_address?: string | null
          payment_comment?: string | null
          payment_method?: string
          price_ton?: number
          reward_configuration_version?: number
          status?: string
          telegram_id?: number | null
          tx_hash?: string | null
          user_id?: string
        }
        Relationships: []
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
      clan_abuse_flags: {
        Row: {
          created_at: string
          details: Json
          flag: string
          id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          details?: Json
          flag: string
          id?: string
          user_id: string
        }
        Update: {
          created_at?: string
          details?: Json
          flag?: string
          id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "clan_abuse_flags_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      clan_anti_abuse_settings: {
        Row: {
          boss_lock_enabled: boolean
          boss_lock_min_hours: number
          enabled: boolean
          hopping_threshold_24h: number
          id: number
          kick_cooldown_hours: number
          leave_cooldown_hours: number
          updated_at: string
        }
        Insert: {
          boss_lock_enabled?: boolean
          boss_lock_min_hours?: number
          enabled?: boolean
          hopping_threshold_24h?: number
          id?: number
          kick_cooldown_hours?: number
          leave_cooldown_hours?: number
          updated_at?: string
        }
        Update: {
          boss_lock_enabled?: boolean
          boss_lock_min_hours?: number
          enabled?: boolean
          hopping_threshold_24h?: number
          id?: number
          kick_cooldown_hours?: number
          leave_cooldown_hours?: number
          updated_at?: string
        }
        Relationships: []
      }
      clan_boss_attack_log: {
        Row: {
          attack_type: string
          clan_boss_id: string | null
          clan_id: string | null
          created_at: string
          damage: number
          id: string
          pass_type: string | null
          team_power: number
          telegram_id: number | null
          user_id: string
        }
        Insert: {
          attack_type: string
          clan_boss_id?: string | null
          clan_id?: string | null
          created_at?: string
          damage?: number
          id?: string
          pass_type?: string | null
          team_power?: number
          telegram_id?: number | null
          user_id: string
        }
        Update: {
          attack_type?: string
          clan_boss_id?: string | null
          clan_id?: string | null
          created_at?: string
          damage?: number
          id?: string
          pass_type?: string | null
          team_power?: number
          telegram_id?: number | null
          user_id?: string
        }
        Relationships: []
      }
      clan_boss_auto_attack: {
        Row: {
          attacks_total: number
          created_at: string
          enabled: boolean
          last_auto_attack_at: string | null
          next_auto_attack_at: string
          paused_reason: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          attacks_total?: number
          created_at?: string
          enabled?: boolean
          last_auto_attack_at?: string | null
          next_auto_attack_at?: string
          paused_reason?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          attacks_total?: number
          created_at?: string
          enabled?: boolean
          last_auto_attack_at?: string | null
          next_auto_attack_at?: string
          paused_reason?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "clan_boss_auto_attack_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      clan_boss_claims: {
        Row: {
          clan_id: string
          created_at: string
          damage: number
          id: string
          instance_id: string
          payload: Json
          reversal_status: string | null
          reversed_at: string | null
          user_id: string
        }
        Insert: {
          clan_id: string
          created_at?: string
          damage?: number
          id?: string
          instance_id: string
          payload?: Json
          reversal_status?: string | null
          reversed_at?: string | null
          user_id: string
        }
        Update: {
          clan_id?: string
          created_at?: string
          damage?: number
          id?: string
          instance_id?: string
          payload?: Json
          reversal_status?: string | null
          reversed_at?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "clan_boss_claims_clan_id_fkey"
            columns: ["clan_id"]
            isOneToOne: false
            referencedRelation: "clans"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "clan_boss_claims_instance_id_fkey"
            columns: ["instance_id"]
            isOneToOne: false
            referencedRelation: "clan_boss_instances"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "clan_boss_claims_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      clan_boss_clan_settings: {
        Row: {
          bosses_per_day: number | null
          clan_id: string
          created_at: string
          duration_hours: number | null
          fixed_hp: number
          notes: string | null
          reward_fc_pool: number | null
          rewards: Json | null
          updated_at: string
        }
        Insert: {
          bosses_per_day?: number | null
          clan_id: string
          created_at?: string
          duration_hours?: number | null
          fixed_hp?: number
          notes?: string | null
          reward_fc_pool?: number | null
          rewards?: Json | null
          updated_at?: string
        }
        Update: {
          bosses_per_day?: number | null
          clan_id?: string
          created_at?: string
          duration_hours?: number | null
          fixed_hp?: number
          notes?: string | null
          reward_fc_pool?: number | null
          rewards?: Json | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "clan_boss_clan_settings_clan_id_fkey"
            columns: ["clan_id"]
            isOneToOne: true
            referencedRelation: "clans"
            referencedColumns: ["id"]
          },
        ]
      }
      clan_boss_config: {
        Row: {
          base_hp: number
          boss_key: string
          boss_name: string
          clan_xp_reward: number
          cooldown_seconds: number
          duration_hours: number
          hp_per_clan_level_pct: number
          hp_per_cycle_pct: number
          hp_per_member_pct: number
          id: number
          min_damage_pct: number
          rewards: Json
          updated_at: string
        }
        Insert: {
          base_hp?: number
          boss_key?: string
          boss_name?: string
          clan_xp_reward?: number
          cooldown_seconds?: number
          duration_hours?: number
          hp_per_clan_level_pct?: number
          hp_per_cycle_pct?: number
          hp_per_member_pct?: number
          id?: number
          min_damage_pct?: number
          rewards?: Json
          updated_at?: string
        }
        Update: {
          base_hp?: number
          boss_key?: string
          boss_name?: string
          clan_xp_reward?: number
          cooldown_seconds?: number
          duration_hours?: number
          hp_per_clan_level_pct?: number
          hp_per_cycle_pct?: number
          hp_per_member_pct?: number
          id?: number
          min_damage_pct?: number
          rewards?: Json
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
      clan_boss_daily_counters: {
        Row: {
          created_at: string
          defeated_count: number
          last_defeat_at: string | null
          reset_day: string
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          defeated_count?: number
          last_defeat_at?: string | null
          reset_day: string
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          defeated_count?: number
          last_defeat_at?: string | null
          reset_day?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      clan_boss_damage: {
        Row: {
          attacks: number
          clan_id: string
          created_at: string
          damage: number
          eligibility_status: string
          id: string
          instance_id: string
          last_attack_at: string | null
          user_id: string
        }
        Insert: {
          attacks?: number
          clan_id: string
          created_at?: string
          damage?: number
          eligibility_status?: string
          id?: string
          instance_id: string
          last_attack_at?: string | null
          user_id: string
        }
        Update: {
          attacks?: number
          clan_id?: string
          created_at?: string
          damage?: number
          eligibility_status?: string
          id?: string
          instance_id?: string
          last_attack_at?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "clan_boss_damage_clan_id_fkey"
            columns: ["clan_id"]
            isOneToOne: false
            referencedRelation: "clans"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "clan_boss_damage_instance_id_fkey"
            columns: ["instance_id"]
            isOneToOne: false
            referencedRelation: "clan_boss_instances"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "clan_boss_damage_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      clan_boss_instances: {
        Row: {
          active_members_snapshot: number | null
          actual_duration_seconds: number | null
          atk_multiplier: number
          attacks: number
          base_hp: number | null
          boss_atk: number
          boss_def: number
          boss_key: string
          boss_name: string
          boss_number_today: number
          boss_power: number
          clan_id: string
          clan_power_snapshot: number | null
          clan_xp_awarded: number
          created_at: string
          current_hp: number
          cycle: number
          cycle_ends_at: string | null
          cycle_started_at: string | null
          def_multiplier: number
          difficulty: string | null
          duration_quality: string | null
          ends_at: string
          finished_at: string | null
          historical_dps_snapshot: number | null
          hp_multiplier: number
          id: string
          is_personal: boolean
          level: number
          max_hp: number
          min_damage_required: number
          participants: number
          performance_snapshot: Json
          player_power_snapshot: number | null
          reset_day: string | null
          rewards_snapshot: Json
          scaling_snapshot: Json
          scaling_version: number
          starts_at: string
          status: string
          target_duration_seconds: number | null
          top_user_id: string | null
          total_damage: number
          user_id: string | null
        }
        Insert: {
          active_members_snapshot?: number | null
          actual_duration_seconds?: number | null
          atk_multiplier?: number
          attacks?: number
          base_hp?: number | null
          boss_atk?: number
          boss_def?: number
          boss_key?: string
          boss_name?: string
          boss_number_today?: number
          boss_power?: number
          clan_id: string
          clan_power_snapshot?: number | null
          clan_xp_awarded?: number
          created_at?: string
          current_hp: number
          cycle?: number
          cycle_ends_at?: string | null
          cycle_started_at?: string | null
          def_multiplier?: number
          difficulty?: string | null
          duration_quality?: string | null
          ends_at: string
          finished_at?: string | null
          historical_dps_snapshot?: number | null
          hp_multiplier?: number
          id?: string
          is_personal?: boolean
          level?: number
          max_hp: number
          min_damage_required?: number
          participants?: number
          performance_snapshot?: Json
          player_power_snapshot?: number | null
          reset_day?: string | null
          rewards_snapshot?: Json
          scaling_snapshot?: Json
          scaling_version?: number
          starts_at?: string
          status?: string
          target_duration_seconds?: number | null
          top_user_id?: string | null
          total_damage?: number
          user_id?: string | null
        }
        Update: {
          active_members_snapshot?: number | null
          actual_duration_seconds?: number | null
          atk_multiplier?: number
          attacks?: number
          base_hp?: number | null
          boss_atk?: number
          boss_def?: number
          boss_key?: string
          boss_name?: string
          boss_number_today?: number
          boss_power?: number
          clan_id?: string
          clan_power_snapshot?: number | null
          clan_xp_awarded?: number
          created_at?: string
          current_hp?: number
          cycle?: number
          cycle_ends_at?: string | null
          cycle_started_at?: string | null
          def_multiplier?: number
          difficulty?: string | null
          duration_quality?: string | null
          ends_at?: string
          finished_at?: string | null
          historical_dps_snapshot?: number | null
          hp_multiplier?: number
          id?: string
          is_personal?: boolean
          level?: number
          max_hp?: number
          min_damage_required?: number
          participants?: number
          performance_snapshot?: Json
          player_power_snapshot?: number | null
          reset_day?: string | null
          rewards_snapshot?: Json
          scaling_snapshot?: Json
          scaling_version?: number
          starts_at?: string
          status?: string
          target_duration_seconds?: number | null
          top_user_id?: string | null
          total_damage?: number
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "clan_boss_instances_clan_id_fkey"
            columns: ["clan_id"]
            isOneToOne: false
            referencedRelation: "clans"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "clan_boss_instances_top_user_id_fkey"
            columns: ["top_user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
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
      clan_boss_performance_history: {
        Row: {
          active_members_snapshot: number | null
          actual_duration_seconds: number | null
          atk_multiplier: number | null
          attack_count: number | null
          avg_damage_per_attack: number | null
          base_atk: number | null
          base_def: number | null
          base_hp: number | null
          boss_number_today: number | null
          boss_power: number | null
          clan_id: string
          clan_power_snapshot: number | null
          created_at: string
          cycle: number | null
          def_multiplier: number | null
          difficulty: string | null
          effective_atk: number | null
          effective_def: number | null
          effective_hp: number | null
          final_status: string | null
          historical_damage_rate: number | null
          hp_multiplier: number | null
          id: string
          instance_id: string
          max_hit: number | null
          participants: number | null
          player_power: number | null
          quality: string | null
          scaling_version: number | null
          target_duration_seconds: number | null
          total_damage: number | null
          user_id: string | null
        }
        Insert: {
          active_members_snapshot?: number | null
          actual_duration_seconds?: number | null
          atk_multiplier?: number | null
          attack_count?: number | null
          avg_damage_per_attack?: number | null
          base_atk?: number | null
          base_def?: number | null
          base_hp?: number | null
          boss_number_today?: number | null
          boss_power?: number | null
          clan_id: string
          clan_power_snapshot?: number | null
          created_at?: string
          cycle?: number | null
          def_multiplier?: number | null
          difficulty?: string | null
          effective_atk?: number | null
          effective_def?: number | null
          effective_hp?: number | null
          final_status?: string | null
          historical_damage_rate?: number | null
          hp_multiplier?: number | null
          id?: string
          instance_id: string
          max_hit?: number | null
          participants?: number | null
          player_power?: number | null
          quality?: string | null
          scaling_version?: number | null
          target_duration_seconds?: number | null
          total_damage?: number | null
          user_id?: string | null
        }
        Update: {
          active_members_snapshot?: number | null
          actual_duration_seconds?: number | null
          atk_multiplier?: number | null
          attack_count?: number | null
          avg_damage_per_attack?: number | null
          base_atk?: number | null
          base_def?: number | null
          base_hp?: number | null
          boss_number_today?: number | null
          boss_power?: number | null
          clan_id?: string
          clan_power_snapshot?: number | null
          created_at?: string
          cycle?: number | null
          def_multiplier?: number | null
          difficulty?: string | null
          effective_atk?: number | null
          effective_def?: number | null
          effective_hp?: number | null
          final_status?: string | null
          historical_damage_rate?: number | null
          hp_multiplier?: number | null
          id?: string
          instance_id?: string
          max_hit?: number | null
          participants?: number | null
          player_power?: number | null
          quality?: string | null
          scaling_version?: number | null
          target_duration_seconds?: number | null
          total_damage?: number | null
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "clan_boss_performance_history_clan_id_fkey"
            columns: ["clan_id"]
            isOneToOne: false
            referencedRelation: "clans"
            referencedColumns: ["id"]
          },
        ]
      }
      clan_boss_personal_config: {
        Row: {
          atk_ratio: number
          balanced_pct: number
          boss_duration_hours: number
          capacity_ceiling: number
          capacity_floor: number
          daily_limit: number
          def_mitigation_target: number
          difficulty_bonus_enabled: boolean
          easy_pct: number
          enabled: boolean
          fc_pool_pct: number
          fixed_fc_pool: number
          hard_pct: number
          history_samples: number
          id: number
          max_hp: number
          max_scale_down: number
          max_scale_up: number
          min_hp: number
          outlier_median_factor: number
          reset_hour_utc: number
          scaling_version: number
          target_attacks_per_boss: number
          updated_at: string
          very_easy_pct: number
          very_hard_pct: number
        }
        Insert: {
          atk_ratio?: number
          balanced_pct?: number
          boss_duration_hours?: number
          capacity_ceiling?: number
          capacity_floor?: number
          daily_limit?: number
          def_mitigation_target?: number
          difficulty_bonus_enabled?: boolean
          easy_pct?: number
          enabled?: boolean
          fc_pool_pct?: number
          fixed_fc_pool?: number
          hard_pct?: number
          history_samples?: number
          id?: number
          max_hp?: number
          max_scale_down?: number
          max_scale_up?: number
          min_hp?: number
          outlier_median_factor?: number
          reset_hour_utc?: number
          scaling_version?: number
          target_attacks_per_boss?: number
          updated_at?: string
          very_easy_pct?: number
          very_hard_pct?: number
        }
        Update: {
          atk_ratio?: number
          balanced_pct?: number
          boss_duration_hours?: number
          capacity_ceiling?: number
          capacity_floor?: number
          daily_limit?: number
          def_mitigation_target?: number
          difficulty_bonus_enabled?: boolean
          easy_pct?: number
          enabled?: boolean
          fc_pool_pct?: number
          fixed_fc_pool?: number
          hard_pct?: number
          history_samples?: number
          id?: number
          max_hp?: number
          max_scale_down?: number
          max_scale_up?: number
          min_hp?: number
          outlier_median_factor?: number
          reset_hour_utc?: number
          scaling_version?: number
          target_attacks_per_boss?: number
          updated_at?: string
          very_easy_pct?: number
          very_hard_pct?: number
        }
        Relationships: []
      }
      clan_boss_player_locks: {
        Row: {
          clan_id: string
          cycle: number | null
          instance_id: string | null
          locked_at: string
          locked_until: string
          updated_at: string
          user_id: string
        }
        Insert: {
          clan_id: string
          cycle?: number | null
          instance_id?: string | null
          locked_at?: string
          locked_until: string
          updated_at?: string
          user_id: string
        }
        Update: {
          clan_id?: string
          cycle?: number | null
          instance_id?: string | null
          locked_at?: string
          locked_until?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "clan_boss_player_locks_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      clan_boss_player_profile: {
        Row: {
          created_at: string
          daily_limit_override: number | null
          difficulty_rating: string | null
          effective_power: number
          fixed_fc_pool_override: number | null
          last_quality: string | null
          metrics: Json
          official_power: number
          recent_avg_attacks: number | null
          recent_avg_clear_time: number | null
          recent_avg_damage: number
          recent_max_hit: number
          recommended_atk: number
          recommended_def: number
          recommended_hp: number
          samples: number
          scaling_version: number
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          daily_limit_override?: number | null
          difficulty_rating?: string | null
          effective_power?: number
          fixed_fc_pool_override?: number | null
          last_quality?: string | null
          metrics?: Json
          official_power?: number
          recent_avg_attacks?: number | null
          recent_avg_clear_time?: number | null
          recent_avg_damage?: number
          recent_max_hit?: number
          recommended_atk?: number
          recommended_def?: number
          recommended_hp?: number
          samples?: number
          scaling_version?: number
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          daily_limit_override?: number | null
          difficulty_rating?: string | null
          effective_power?: number
          fixed_fc_pool_override?: number | null
          last_quality?: string | null
          metrics?: Json
          official_power?: number
          recent_avg_attacks?: number | null
          recent_avg_clear_time?: number | null
          recent_avg_damage?: number
          recent_max_hit?: number
          recommended_atk?: number
          recommended_def?: number
          recommended_hp?: number
          samples?: number
          scaling_version?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      clan_boss_reward_rollback_log: {
        Row: {
          clan_boss_id: string | null
          created_at: string
          details: Json
          id: string
          original_quantity: number
          preserved_quantity: number
          reason: string
          removed_quantity: number
          reward_at: string | null
          reward_id: string | null
          reward_type: string
          rollback_id: string
          telegram_id: number | null
          user_id: string
        }
        Insert: {
          clan_boss_id?: string | null
          created_at?: string
          details?: Json
          id?: string
          original_quantity?: number
          preserved_quantity?: number
          reason?: string
          removed_quantity?: number
          reward_at?: string | null
          reward_id?: string | null
          reward_type: string
          rollback_id: string
          telegram_id?: number | null
          user_id: string
        }
        Update: {
          clan_boss_id?: string | null
          created_at?: string
          details?: Json
          id?: string
          original_quantity?: number
          preserved_quantity?: number
          reason?: string
          removed_quantity?: number
          reward_at?: string | null
          reward_id?: string | null
          reward_type?: string
          rollback_id?: string
          telegram_id?: number | null
          user_id?: string
        }
        Relationships: []
      }
      clan_boss_scaling_config: {
        Row: {
          atk_ratio: number
          atk_scaling: number
          bosses_per_day: number
          cycle_hours: number
          cycle_lock_enabled: boolean
          cycle_lock_hours: number
          def_mitigation_cap: number
          def_scaling: number
          def_share: number
          enabled: boolean
          engagement_factor: number
          fixed_hp: number
          hp_scaling: number
          hp_share: number
          id: number
          max_hp_cap: number
          max_scale_down_per_cycle: number
          max_scale_up_per_cycle: number
          min_effective_damage_pct: number
          outlier_median_factor: number
          rebase_kills_threshold: number
          rebase_max_scale: number
          scaling_version: number
          survival_factor: number
          target_duration_seconds: number
          too_easy_seconds: number
          too_hard_seconds: number
          updated_at: string
          w_24h: number
          w_3d: number
          w_7d: number
        }
        Insert: {
          atk_ratio?: number
          atk_scaling?: number
          bosses_per_day?: number
          cycle_hours?: number
          cycle_lock_enabled?: boolean
          cycle_lock_hours?: number
          def_mitigation_cap?: number
          def_scaling?: number
          def_share?: number
          enabled?: boolean
          engagement_factor?: number
          fixed_hp?: number
          hp_scaling?: number
          hp_share?: number
          id?: number
          max_hp_cap?: number
          max_scale_down_per_cycle?: number
          max_scale_up_per_cycle?: number
          min_effective_damage_pct?: number
          outlier_median_factor?: number
          rebase_kills_threshold?: number
          rebase_max_scale?: number
          scaling_version?: number
          survival_factor?: number
          target_duration_seconds?: number
          too_easy_seconds?: number
          too_hard_seconds?: number
          updated_at?: string
          w_24h?: number
          w_3d?: number
          w_7d?: number
        }
        Update: {
          atk_ratio?: number
          atk_scaling?: number
          bosses_per_day?: number
          cycle_hours?: number
          cycle_lock_enabled?: boolean
          cycle_lock_hours?: number
          def_mitigation_cap?: number
          def_scaling?: number
          def_share?: number
          enabled?: boolean
          engagement_factor?: number
          fixed_hp?: number
          hp_scaling?: number
          hp_share?: number
          id?: number
          max_hp_cap?: number
          max_scale_down_per_cycle?: number
          max_scale_up_per_cycle?: number
          min_effective_damage_pct?: number
          outlier_median_factor?: number
          rebase_kills_threshold?: number
          rebase_max_scale?: number
          scaling_version?: number
          survival_factor?: number
          target_duration_seconds?: number
          too_easy_seconds?: number
          too_hard_seconds?: number
          updated_at?: string
          w_24h?: number
          w_3d?: number
          w_7d?: number
        }
        Relationships: []
      }
      clan_boss_scaling_profiles: {
        Row: {
          active_members_snapshot: number
          atk_multiplier: number
          boss_participants_snapshot: number
          clan_id: string
          clan_power_snapshot: number
          def_multiplier: number
          effective_dps: number
          historical_damage_rate: number
          hp_multiplier: number
          last_actual_duration_seconds: number | null
          last_mode: string | null
          last_quality: string | null
          metrics: Json
          scaling_tier: string
          scaling_version: number
          updated_at: string
        }
        Insert: {
          active_members_snapshot?: number
          atk_multiplier?: number
          boss_participants_snapshot?: number
          clan_id: string
          clan_power_snapshot?: number
          def_multiplier?: number
          effective_dps?: number
          historical_damage_rate?: number
          hp_multiplier?: number
          last_actual_duration_seconds?: number | null
          last_mode?: string | null
          last_quality?: string | null
          metrics?: Json
          scaling_tier?: string
          scaling_version?: number
          updated_at?: string
        }
        Update: {
          active_members_snapshot?: number
          atk_multiplier?: number
          boss_participants_snapshot?: number
          clan_id?: string
          clan_power_snapshot?: number
          def_multiplier?: number
          effective_dps?: number
          historical_damage_rate?: number
          hp_multiplier?: number
          last_actual_duration_seconds?: number | null
          last_mode?: string | null
          last_quality?: string | null
          metrics?: Json
          scaling_tier?: string
          scaling_version?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "clan_boss_scaling_profiles_clan_id_fkey"
            columns: ["clan_id"]
            isOneToOne: true
            referencedRelation: "clans"
            referencedColumns: ["id"]
          },
        ]
      }
      clan_boss_templates: {
        Row: {
          background_url: string | null
          base_damage: number
          boss_key: string
          created_at: string
          cycle_number: number
          enabled: boolean
          id: string
          image_url: string | null
          max_hp: number
          name: string
          reward_clan_xp: number
          reward_fc: number
          sort_order: number
          subtitle: string
          theme: string
          updated_at: string
        }
        Insert: {
          background_url?: string | null
          base_damage?: number
          boss_key: string
          created_at?: string
          cycle_number: number
          enabled?: boolean
          id?: string
          image_url?: string | null
          max_hp: number
          name: string
          reward_clan_xp?: number
          reward_fc?: number
          sort_order?: number
          subtitle?: string
          theme?: string
          updated_at?: string
        }
        Update: {
          background_url?: string | null
          base_damage?: number
          boss_key?: string
          created_at?: string
          cycle_number?: number
          enabled?: boolean
          id?: string
          image_url?: string | null
          max_hp?: number
          name?: string
          reward_clan_xp?: number
          reward_fc?: number
          sort_order?: number
          subtitle?: string
          theme?: string
          updated_at?: string
        }
        Relationships: []
      }
      clan_buff_config: {
        Row: {
          bonus_pct: number
          code: string
          cost_fc: number
          duration_hours: number
          enabled: boolean
          label: string
          max_pct: number
          required_research_level: number
          updated_at: string
        }
        Insert: {
          bonus_pct?: number
          code: string
          cost_fc?: number
          duration_hours?: number
          enabled?: boolean
          label: string
          max_pct?: number
          required_research_level?: number
          updated_at?: string
        }
        Update: {
          bonus_pct?: number
          code?: string
          cost_fc?: number
          duration_hours?: number
          enabled?: boolean
          label?: string
          max_pct?: number
          required_research_level?: number
          updated_at?: string
        }
        Relationships: []
      }
      clan_buffs: {
        Row: {
          activated_by: string | null
          bonus_pct: number
          clan_id: string
          code: string
          expires_at: string
          updated_at: string
        }
        Insert: {
          activated_by?: string | null
          bonus_pct?: number
          clan_id: string
          code: string
          expires_at: string
          updated_at?: string
        }
        Update: {
          activated_by?: string | null
          bonus_pct?: number
          clan_id?: string
          code?: string
          expires_at?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "clan_buffs_activated_by_fkey"
            columns: ["activated_by"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "clan_buffs_clan_id_fkey"
            columns: ["clan_id"]
            isOneToOne: false
            referencedRelation: "clans"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "clan_buffs_code_fkey"
            columns: ["code"]
            isOneToOne: false
            referencedRelation: "clan_buff_config"
            referencedColumns: ["code"]
          },
        ]
      }
      clan_coin_ledger: {
        Row: {
          amount: number
          balance_after: number
          balance_before: number
          capped: number
          clan_id: string | null
          created_at: string
          cycle_key: string
          day_key: string
          id: string
          requested: number
          source_id: string | null
          source_type: string
          user_id: string
        }
        Insert: {
          amount?: number
          balance_after?: number
          balance_before?: number
          capped?: number
          clan_id?: string | null
          created_at?: string
          cycle_key?: string
          day_key?: string
          id?: string
          requested?: number
          source_id?: string | null
          source_type: string
          user_id: string
        }
        Update: {
          amount?: number
          balance_after?: number
          balance_before?: number
          capped?: number
          clan_id?: string | null
          created_at?: string
          cycle_key?: string
          day_key?: string
          id?: string
          requested?: number
          source_id?: string | null
          source_type?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "clan_coin_ledger_clan_id_fkey"
            columns: ["clan_id"]
            isOneToOne: false
            referencedRelation: "clans"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "clan_coin_ledger_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      clan_coin_settings: {
        Row: {
          boss_coins: number[]
          enabled: boolean
          id: boolean
          milestone_coins: Json
          personal_weekly_cap: number
          price_multiplier_max: number
          price_multiplier_min: number
          raid_defeat: number
          raid_participation: number
          raid_top_bonus: number[]
          target_coins_per_active: number
          updated_at: string
          war_participation: number
          war_victory: number
        }
        Insert: {
          boss_coins?: number[]
          enabled?: boolean
          id?: boolean
          milestone_coins?: Json
          personal_weekly_cap?: number
          price_multiplier_max?: number
          price_multiplier_min?: number
          raid_defeat?: number
          raid_participation?: number
          raid_top_bonus?: number[]
          target_coins_per_active?: number
          updated_at?: string
          war_participation?: number
          war_victory?: number
        }
        Update: {
          boss_coins?: number[]
          enabled?: boolean
          id?: boolean
          milestone_coins?: Json
          personal_weekly_cap?: number
          price_multiplier_max?: number
          price_multiplier_min?: number
          raid_defeat?: number
          raid_participation?: number
          raid_top_bonus?: number[]
          target_coins_per_active?: number
          updated_at?: string
          war_participation?: number
          war_victory?: number
        }
        Relationships: []
      }
      clan_coin_source_caps: {
        Row: {
          daily_cap: number
          enabled: boolean
          label: string
          source_type: string
          updated_at: string
          weekly_cap: number
        }
        Insert: {
          daily_cap?: number
          enabled?: boolean
          label: string
          source_type: string
          updated_at?: string
          weekly_cap?: number
        }
        Update: {
          daily_cap?: number
          enabled?: boolean
          label?: string
          source_type?: string
          updated_at?: string
          weekly_cap?: number
        }
        Relationships: []
      }
      clan_collective_settings: {
        Row: {
          active_member_days: number
          boss_points: number[]
          clan_xp_per_contribution: number
          coins_per_contribution: number
          donation_default_max_fc: number
          donation_default_max_myth: number
          donation_default_min_fc: number
          donation_default_min_myth: number
          donation_hard_max_fc: number
          donation_hard_max_myth: number
          enabled: boolean
          id: boolean
          milestones: Json
          min_weekly_contribution: number
          myth_milestone_rewards: boolean
          raid_attacks_per_day: number
          raid_boss_name: string
          raid_catchup_enabled: boolean
          raid_catchup_max_pct: number
          raid_deadline_days: number
          raid_dps_weight_24h: number
          raid_dps_weight_3d: number
          raid_dps_weight_7d: number
          raid_duration_days: number
          raid_enabled: boolean
          raid_full_kill_required: boolean
          raid_health_gates_enabled: boolean
          raid_hp_max: number
          raid_hp_min: number
          raid_hp_per_power: number
          raid_max_hp_decrease_pct: number
          raid_max_hp_increase_pct: number
          raid_min_kill_days: number
          raid_rewards: Json
          raid_safety_factor: number
          raid_target_kill_days: number
          treasury_assets: string[]
          treasury_ton_enabled: boolean
          updated_at: string
          weekly_target_max: number
          weekly_target_min: number
          weekly_target_per_active: number
        }
        Insert: {
          active_member_days?: number
          boss_points?: number[]
          clan_xp_per_contribution?: number
          coins_per_contribution?: number
          donation_default_max_fc?: number
          donation_default_max_myth?: number
          donation_default_min_fc?: number
          donation_default_min_myth?: number
          donation_hard_max_fc?: number
          donation_hard_max_myth?: number
          enabled?: boolean
          id?: boolean
          milestones?: Json
          min_weekly_contribution?: number
          myth_milestone_rewards?: boolean
          raid_attacks_per_day?: number
          raid_boss_name?: string
          raid_catchup_enabled?: boolean
          raid_catchup_max_pct?: number
          raid_deadline_days?: number
          raid_dps_weight_24h?: number
          raid_dps_weight_3d?: number
          raid_dps_weight_7d?: number
          raid_duration_days?: number
          raid_enabled?: boolean
          raid_full_kill_required?: boolean
          raid_health_gates_enabled?: boolean
          raid_hp_max?: number
          raid_hp_min?: number
          raid_hp_per_power?: number
          raid_max_hp_decrease_pct?: number
          raid_max_hp_increase_pct?: number
          raid_min_kill_days?: number
          raid_rewards?: Json
          raid_safety_factor?: number
          raid_target_kill_days?: number
          treasury_assets?: string[]
          treasury_ton_enabled?: boolean
          updated_at?: string
          weekly_target_max?: number
          weekly_target_min?: number
          weekly_target_per_active?: number
        }
        Update: {
          active_member_days?: number
          boss_points?: number[]
          clan_xp_per_contribution?: number
          coins_per_contribution?: number
          donation_default_max_fc?: number
          donation_default_max_myth?: number
          donation_default_min_fc?: number
          donation_default_min_myth?: number
          donation_hard_max_fc?: number
          donation_hard_max_myth?: number
          enabled?: boolean
          id?: boolean
          milestones?: Json
          min_weekly_contribution?: number
          myth_milestone_rewards?: boolean
          raid_attacks_per_day?: number
          raid_boss_name?: string
          raid_catchup_enabled?: boolean
          raid_catchup_max_pct?: number
          raid_deadline_days?: number
          raid_dps_weight_24h?: number
          raid_dps_weight_3d?: number
          raid_dps_weight_7d?: number
          raid_duration_days?: number
          raid_enabled?: boolean
          raid_full_kill_required?: boolean
          raid_health_gates_enabled?: boolean
          raid_hp_max?: number
          raid_hp_min?: number
          raid_hp_per_power?: number
          raid_max_hp_decrease_pct?: number
          raid_max_hp_increase_pct?: number
          raid_min_kill_days?: number
          raid_rewards?: Json
          raid_safety_factor?: number
          raid_target_kill_days?: number
          treasury_assets?: string[]
          treasury_ton_enabled?: boolean
          updated_at?: string
          weekly_target_max?: number
          weekly_target_min?: number
          weekly_target_per_active?: number
        }
        Relationships: []
      }
      clan_contribution_ledger: {
        Row: {
          amount: number
          clan_id: string
          created_at: string
          cycle_id: string | null
          game_day: string
          id: string
          source_id: string | null
          source_type: string
          user_id: string | null
        }
        Insert: {
          amount: number
          clan_id: string
          created_at?: string
          cycle_id?: string | null
          game_day?: string
          id?: string
          source_id?: string | null
          source_type: string
          user_id?: string | null
        }
        Update: {
          amount?: number
          clan_id?: string
          created_at?: string
          cycle_id?: string | null
          game_day?: string
          id?: string
          source_id?: string | null
          source_type?: string
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "clan_contribution_ledger_clan_id_fkey"
            columns: ["clan_id"]
            isOneToOne: false
            referencedRelation: "clans"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "clan_contribution_ledger_cycle_id_fkey"
            columns: ["cycle_id"]
            isOneToOne: false
            referencedRelation: "clan_weekly_cycles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "clan_contribution_ledger_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      clan_daily_contributions: {
        Row: {
          asset: string
          clan_id: string
          created_at: string
          donations: number
          game_day: string
          id: string
          total: number
          updated_at: string
          user_id: string
        }
        Insert: {
          asset: string
          clan_id: string
          created_at?: string
          donations?: number
          game_day: string
          id?: string
          total?: number
          updated_at?: string
          user_id: string
        }
        Update: {
          asset?: string
          clan_id?: string
          created_at?: string
          donations?: number
          game_day?: string
          id?: string
          total?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "clan_daily_contributions_clan_id_fkey"
            columns: ["clan_id"]
            isOneToOne: false
            referencedRelation: "clans"
            referencedColumns: ["id"]
          },
        ]
      }
      clan_exploit_audit_runs: {
        Row: {
          admin_telegram_id: number | null
          created_at: string
          id: string
          mode: string
          scope: string
          stats: Json
        }
        Insert: {
          admin_telegram_id?: number | null
          created_at?: string
          id?: string
          mode?: string
          scope?: string
          stats?: Json
        }
        Update: {
          admin_telegram_id?: number | null
          created_at?: string
          id?: string
          mode?: string
          scope?: string
          stats?: Json
        }
        Relationships: []
      }
      clan_exploit_participations: {
        Row: {
          boss_name: string | null
          claim_id: string
          clan_id: string | null
          classification: string
          created_at: string
          cycle: number | null
          first_attack_at: string | null
          instance_id: string | null
          legit_claim_id: string | null
          reward_payload: Json
          run_id: string | null
          updated_at: string
          user_id: string
          window_end: string | null
          window_start: string | null
        }
        Insert: {
          boss_name?: string | null
          claim_id: string
          clan_id?: string | null
          classification: string
          created_at?: string
          cycle?: number | null
          first_attack_at?: string | null
          instance_id?: string | null
          legit_claim_id?: string | null
          reward_payload?: Json
          run_id?: string | null
          updated_at?: string
          user_id: string
          window_end?: string | null
          window_start?: string | null
        }
        Update: {
          boss_name?: string | null
          claim_id?: string
          clan_id?: string | null
          classification?: string
          created_at?: string
          cycle?: number | null
          first_attack_at?: string | null
          instance_id?: string | null
          legit_claim_id?: string | null
          reward_payload?: Json
          run_id?: string | null
          updated_at?: string
          user_id?: string
          window_end?: string | null
          window_start?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "clan_exploit_participations_claim_id_fkey"
            columns: ["claim_id"]
            isOneToOne: true
            referencedRelation: "clan_boss_claims"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "clan_exploit_participations_run_id_fkey"
            columns: ["run_id"]
            isOneToOne: false
            referencedRelation: "clan_exploit_audit_runs"
            referencedColumns: ["id"]
          },
        ]
      }
      clan_exploit_reversals: {
        Row: {
          admin_telegram_id: number | null
          claim_id: string
          clan_id: string | null
          created_at: string
          debt: Json
          executed_at: string | null
          id: string
          illicit: Json
          instance_id: string | null
          notes: Json
          recovered: Json
          status: string
          user_id: string
        }
        Insert: {
          admin_telegram_id?: number | null
          claim_id: string
          clan_id?: string | null
          created_at?: string
          debt?: Json
          executed_at?: string | null
          id?: string
          illicit?: Json
          instance_id?: string | null
          notes?: Json
          recovered?: Json
          status?: string
          user_id: string
        }
        Update: {
          admin_telegram_id?: number | null
          claim_id?: string
          clan_id?: string | null
          created_at?: string
          debt?: Json
          executed_at?: string | null
          id?: string
          illicit?: Json
          instance_id?: string | null
          notes?: Json
          recovered?: Json
          status?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "clan_exploit_reversals_claim_id_fkey"
            columns: ["claim_id"]
            isOneToOne: true
            referencedRelation: "clan_boss_claims"
            referencedColumns: ["id"]
          },
        ]
      }
      clan_join_cooldowns: {
        Row: {
          changes_24h: number
          changes_7d: number
          cooldown_until: string
          reason: string
          source_clan_id: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          changes_24h?: number
          changes_7d?: number
          cooldown_until: string
          reason?: string
          source_clan_id?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          changes_24h?: number
          changes_7d?: number
          cooldown_until?: string
          reason?: string
          source_clan_id?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "clan_join_cooldowns_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
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
          permissions: string[]
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
          permissions?: string[]
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
          permissions?: string[]
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
      clan_membership_history: {
        Row: {
          clan_id: string
          clan_name: string | null
          created_at: string
          id: string
          joined_at: string
          leave_reason: string | null
          left_at: string | null
          removed_by: string | null
          user_id: string
        }
        Insert: {
          clan_id: string
          clan_name?: string | null
          created_at?: string
          id?: string
          joined_at?: string
          leave_reason?: string | null
          left_at?: string | null
          removed_by?: string | null
          user_id: string
        }
        Update: {
          clan_id?: string
          clan_name?: string | null
          created_at?: string
          id?: string
          joined_at?: string
          leave_reason?: string | null
          left_at?: string | null
          removed_by?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "clan_membership_history_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
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
      clan_milestone_claims: {
        Row: {
          clan_id: string
          created_at: string
          cycle_id: string
          id: string
          milestone_pct: number
          payload: Json
          user_id: string
        }
        Insert: {
          clan_id: string
          created_at?: string
          cycle_id: string
          id?: string
          milestone_pct: number
          payload?: Json
          user_id: string
        }
        Update: {
          clan_id?: string
          created_at?: string
          cycle_id?: string
          id?: string
          milestone_pct?: number
          payload?: Json
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "clan_milestone_claims_clan_id_fkey"
            columns: ["clan_id"]
            isOneToOne: false
            referencedRelation: "clans"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "clan_milestone_claims_cycle_id_fkey"
            columns: ["cycle_id"]
            isOneToOne: false
            referencedRelation: "clan_weekly_cycles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "clan_milestone_claims_user_id_fkey"
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
      clan_raid_attacks: {
        Row: {
          attack_day: string
          attack_number: number | null
          boss_hp_after: number | null
          boss_hp_before: number | null
          clan_id: string
          combat_damage: number
          created_at: string
          daily_hp_remaining_after: number | null
          daily_hp_remaining_before: number | null
          damage: number
          hp_damage_applied: number
          id: string
          idempotency_key: string | null
          payload: Json
          phase: number
          raid_id: string
          user_id: string
        }
        Insert: {
          attack_day?: string
          attack_number?: number | null
          boss_hp_after?: number | null
          boss_hp_before?: number | null
          clan_id: string
          combat_damage?: number
          created_at?: string
          daily_hp_remaining_after?: number | null
          daily_hp_remaining_before?: number | null
          damage?: number
          hp_damage_applied?: number
          id?: string
          idempotency_key?: string | null
          payload?: Json
          phase?: number
          raid_id: string
          user_id: string
        }
        Update: {
          attack_day?: string
          attack_number?: number | null
          boss_hp_after?: number | null
          boss_hp_before?: number | null
          clan_id?: string
          combat_damage?: number
          created_at?: string
          daily_hp_remaining_after?: number | null
          daily_hp_remaining_before?: number | null
          damage?: number
          hp_damage_applied?: number
          id?: string
          idempotency_key?: string | null
          payload?: Json
          phase?: number
          raid_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "clan_raid_attacks_clan_id_fkey"
            columns: ["clan_id"]
            isOneToOne: false
            referencedRelation: "clans"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "clan_raid_attacks_raid_id_fkey"
            columns: ["raid_id"]
            isOneToOne: false
            referencedRelation: "clan_raid_cycles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "clan_raid_attacks_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      clan_raid_cycles: {
        Row: {
          active_members_snapshot: number
          boss_atk: number
          boss_def: number
          boss_name: string
          boss_theme: string
          boss_tier: string
          catchup_pct: number
          clan_id: string
          clan_power_snapshot: number
          cleared_in_hours: number | null
          combat_damage: number
          created_at: string
          current_hp: number
          deadline_days: number
          effective_dps_snapshot: number
          ends_at: string
          gates_enabled: boolean
          id: string
          kill_unlock_at: string | null
          max_hp: number
          min_kill_days: number
          participants: number
          performance_class: string | null
          raid_key: string
          rewards_snapshot: Json
          settled_at: string | null
          started_at: string
          status: string
          target_days: number
          total_damage: number
          updated_at: string
        }
        Insert: {
          active_members_snapshot?: number
          boss_atk?: number
          boss_def?: number
          boss_name?: string
          boss_theme?: string
          boss_tier?: string
          catchup_pct?: number
          clan_id: string
          clan_power_snapshot?: number
          cleared_in_hours?: number | null
          combat_damage?: number
          created_at?: string
          current_hp: number
          deadline_days?: number
          effective_dps_snapshot?: number
          ends_at: string
          gates_enabled?: boolean
          id?: string
          kill_unlock_at?: string | null
          max_hp: number
          min_kill_days?: number
          participants?: number
          performance_class?: string | null
          raid_key: string
          rewards_snapshot?: Json
          settled_at?: string | null
          started_at?: string
          status?: string
          target_days?: number
          total_damage?: number
          updated_at?: string
        }
        Update: {
          active_members_snapshot?: number
          boss_atk?: number
          boss_def?: number
          boss_name?: string
          boss_theme?: string
          boss_tier?: string
          catchup_pct?: number
          clan_id?: string
          clan_power_snapshot?: number
          cleared_in_hours?: number | null
          combat_damage?: number
          created_at?: string
          current_hp?: number
          deadline_days?: number
          effective_dps_snapshot?: number
          ends_at?: string
          gates_enabled?: boolean
          id?: string
          kill_unlock_at?: string | null
          max_hp?: number
          min_kill_days?: number
          participants?: number
          performance_class?: string | null
          raid_key?: string
          rewards_snapshot?: Json
          settled_at?: string | null
          started_at?: string
          status?: string
          target_days?: number
          total_damage?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "clan_raid_cycles_clan_id_fkey"
            columns: ["clan_id"]
            isOneToOne: false
            referencedRelation: "clans"
            referencedColumns: ["id"]
          },
        ]
      }
      clan_raid_participation: {
        Row: {
          attacks: number
          clan_id: string
          combat_damage: number
          created_at: string
          effective_damage: number
          first_attack_at: string
          id: string
          last_attack_at: string
          raid_id: string
          updated_at: string
          user_id: string
        }
        Insert: {
          attacks?: number
          clan_id: string
          combat_damage?: number
          created_at?: string
          effective_damage?: number
          first_attack_at?: string
          id?: string
          last_attack_at?: string
          raid_id: string
          updated_at?: string
          user_id: string
        }
        Update: {
          attacks?: number
          clan_id?: string
          combat_damage?: number
          created_at?: string
          effective_damage?: number
          first_attack_at?: string
          id?: string
          last_attack_at?: string
          raid_id?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "clan_raid_participation_clan_id_fkey"
            columns: ["clan_id"]
            isOneToOne: false
            referencedRelation: "clans"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "clan_raid_participation_raid_id_fkey"
            columns: ["raid_id"]
            isOneToOne: false
            referencedRelation: "clan_raid_cycles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "clan_raid_participation_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      clan_raid_performance: {
        Row: {
          clan_id: string
          cleared_in_hours: number | null
          created_at: string
          damage_done: number
          effective_dps: number
          id: string
          max_hp: number
          performance_class: string
          raid_id: string
          status: string
          suggested_next_hp: number
          target_days: number
        }
        Insert: {
          clan_id: string
          cleared_in_hours?: number | null
          created_at?: string
          damage_done: number
          effective_dps: number
          id?: string
          max_hp: number
          performance_class: string
          raid_id: string
          status: string
          suggested_next_hp: number
          target_days: number
        }
        Update: {
          clan_id?: string
          cleared_in_hours?: number | null
          created_at?: string
          damage_done?: number
          effective_dps?: number
          id?: string
          max_hp?: number
          performance_class?: string
          raid_id?: string
          status?: string
          suggested_next_hp?: number
          target_days?: number
        }
        Relationships: []
      }
      clan_raid_rebase_audit: {
        Row: {
          clan_id: string
          created_at: string
          daily_capacity: number
          damage_preserved: number
          day_index: number
          id: string
          new_current_hp: number
          new_max_hp: number
          old_current_hp: number
          old_max_hp: number
          raid_id: string
          reason: string
          safety_factor: number
          target_days: number
          unlocked_pct: number
        }
        Insert: {
          clan_id: string
          created_at?: string
          daily_capacity: number
          damage_preserved: number
          day_index: number
          id?: string
          new_current_hp: number
          new_max_hp: number
          old_current_hp: number
          old_max_hp: number
          raid_id: string
          reason?: string
          safety_factor: number
          target_days: number
          unlocked_pct: number
        }
        Update: {
          clan_id?: string
          created_at?: string
          daily_capacity?: number
          damage_preserved?: number
          day_index?: number
          id?: string
          new_current_hp?: number
          new_max_hp?: number
          old_current_hp?: number
          old_max_hp?: number
          raid_id?: string
          reason?: string
          safety_factor?: number
          target_days?: number
          unlocked_pct?: number
        }
        Relationships: [
          {
            foreignKeyName: "clan_raid_rebase_audit_raid_id_fkey"
            columns: ["raid_id"]
            isOneToOne: false
            referencedRelation: "clan_raid_cycles"
            referencedColumns: ["id"]
          },
        ]
      }
      clan_raid_rewards: {
        Row: {
          clan_id: string
          created_at: string
          damage: number
          id: string
          payload: Json
          raid_id: string
          user_id: string
        }
        Insert: {
          clan_id: string
          created_at?: string
          damage?: number
          id?: string
          payload?: Json
          raid_id: string
          user_id: string
        }
        Update: {
          clan_id?: string
          created_at?: string
          damage?: number
          id?: string
          payload?: Json
          raid_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "clan_raid_rewards_clan_id_fkey"
            columns: ["clan_id"]
            isOneToOne: false
            referencedRelation: "clans"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "clan_raid_rewards_raid_id_fkey"
            columns: ["raid_id"]
            isOneToOne: false
            referencedRelation: "clan_raid_cycles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "clan_raid_rewards_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      clan_shop_config: {
        Row: {
          clan_weekly_stock: number
          code: string
          cost_coins: number
          daily_limit: number
          enabled: boolean
          item_code: string
          item_type: string
          label: string
          quantity: number
          required_clan_level: number
          scale_stock: boolean
          season_limit: number
          sort_order: number
          updated_at: string
          weekly_limit: number
        }
        Insert: {
          clan_weekly_stock?: number
          code: string
          cost_coins?: number
          daily_limit?: number
          enabled?: boolean
          item_code: string
          item_type: string
          label: string
          quantity?: number
          required_clan_level?: number
          scale_stock?: boolean
          season_limit?: number
          sort_order?: number
          updated_at?: string
          weekly_limit?: number
        }
        Update: {
          clan_weekly_stock?: number
          code?: string
          cost_coins?: number
          daily_limit?: number
          enabled?: boolean
          item_code?: string
          item_type?: string
          label?: string
          quantity?: number
          required_clan_level?: number
          scale_stock?: boolean
          season_limit?: number
          sort_order?: number
          updated_at?: string
          weekly_limit?: number
        }
        Relationships: []
      }
      clan_shop_cycles: {
        Row: {
          clan_id: string
          created_at: string
          effective_active_members: number
          forecast_emission: number
          id: string
          price_multiplier: number
          reference_emission: number
          total_members: number
          week_key: string
        }
        Insert: {
          clan_id: string
          created_at?: string
          effective_active_members?: number
          forecast_emission?: number
          id?: string
          price_multiplier?: number
          reference_emission?: number
          total_members?: number
          week_key?: string
        }
        Update: {
          clan_id?: string
          created_at?: string
          effective_active_members?: number
          forecast_emission?: number
          id?: string
          price_multiplier?: number
          reference_emission?: number
          total_members?: number
          week_key?: string
        }
        Relationships: [
          {
            foreignKeyName: "clan_shop_cycles_clan_id_fkey"
            columns: ["clan_id"]
            isOneToOne: false
            referencedRelation: "clans"
            referencedColumns: ["id"]
          },
        ]
      }
      clan_shop_purchases: {
        Row: {
          clan_id: string
          clan_stock_after: number | null
          clan_stock_before: number | null
          code: string
          cost_coins: number
          created_at: string
          cycle_key: string
          id: string
          idempotency_key: string | null
          personal_after: number | null
          personal_before: number | null
          price_multiplier: number
          purchase_day: string
          quantity: number
          unit_price: number
          user_id: string
          week_key: string
        }
        Insert: {
          clan_id: string
          clan_stock_after?: number | null
          clan_stock_before?: number | null
          code: string
          cost_coins?: number
          created_at?: string
          cycle_key?: string
          id?: string
          idempotency_key?: string | null
          personal_after?: number | null
          personal_before?: number | null
          price_multiplier?: number
          purchase_day?: string
          quantity?: number
          unit_price?: number
          user_id: string
          week_key?: string
        }
        Update: {
          clan_id?: string
          clan_stock_after?: number | null
          clan_stock_before?: number | null
          code?: string
          cost_coins?: number
          created_at?: string
          cycle_key?: string
          id?: string
          idempotency_key?: string | null
          personal_after?: number | null
          personal_before?: number | null
          price_multiplier?: number
          purchase_day?: string
          quantity?: number
          unit_price?: number
          user_id?: string
          week_key?: string
        }
        Relationships: [
          {
            foreignKeyName: "clan_shop_purchases_clan_id_fkey"
            columns: ["clan_id"]
            isOneToOne: false
            referencedRelation: "clans"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "clan_shop_purchases_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      clan_shop_stock: {
        Row: {
          clan_id: string
          code: string
          stock_total: number
          stock_used: number
          updated_at: string
          week_key: string
        }
        Insert: {
          clan_id: string
          code: string
          stock_total?: number
          stock_used?: number
          updated_at?: string
          week_key?: string
        }
        Update: {
          clan_id?: string
          code?: string
          stock_total?: number
          stock_used?: number
          updated_at?: string
          week_key?: string
        }
        Relationships: [
          {
            foreignKeyName: "clan_shop_stock_clan_id_fkey"
            columns: ["clan_id"]
            isOneToOne: false
            referencedRelation: "clans"
            referencedColumns: ["id"]
          },
        ]
      }
      clan_treasury: {
        Row: {
          clan_id: string
          fc: number
          materials: number
          myth: number
          updated_at: string
        }
        Insert: {
          clan_id: string
          fc?: number
          materials?: number
          myth?: number
          updated_at?: string
        }
        Update: {
          clan_id?: string
          fc?: number
          materials?: number
          myth?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "clan_treasury_clan_id_fkey"
            columns: ["clan_id"]
            isOneToOne: true
            referencedRelation: "clans"
            referencedColumns: ["id"]
          },
        ]
      }
      clan_treasury_ledger: {
        Row: {
          amount: number
          asset: string
          balance_after: number
          balance_before: number
          clan_id: string
          created_at: string
          id: string
          reason: string
          user_id: string | null
        }
        Insert: {
          amount: number
          asset: string
          balance_after?: number
          balance_before?: number
          clan_id: string
          created_at?: string
          id?: string
          reason: string
          user_id?: string | null
        }
        Update: {
          amount?: number
          asset?: string
          balance_after?: number
          balance_before?: number
          clan_id?: string
          created_at?: string
          id?: string
          reason?: string
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "clan_treasury_ledger_clan_id_fkey"
            columns: ["clan_id"]
            isOneToOne: false
            referencedRelation: "clans"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "clan_treasury_ledger_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      clan_upgrade_audit: {
        Row: {
          clan_id: string
          cost: number
          created_at: string
          id: string
          idempotency_key: string | null
          new_level: number
          old_level: number
          performed_by: string | null
          performed_by_role: string | null
          resource_type: string
          treasury_after: number
          treasury_before: number
          upgrade_code: string
        }
        Insert: {
          clan_id: string
          cost?: number
          created_at?: string
          id?: string
          idempotency_key?: string | null
          new_level: number
          old_level: number
          performed_by?: string | null
          performed_by_role?: string | null
          resource_type?: string
          treasury_after?: number
          treasury_before?: number
          upgrade_code: string
        }
        Update: {
          clan_id?: string
          cost?: number
          created_at?: string
          id?: string
          idempotency_key?: string | null
          new_level?: number
          old_level?: number
          performed_by?: string | null
          performed_by_role?: string | null
          resource_type?: string
          treasury_after?: number
          treasury_before?: number
          upgrade_code?: string
        }
        Relationships: [
          {
            foreignKeyName: "clan_upgrade_audit_clan_id_fkey"
            columns: ["clan_id"]
            isOneToOne: false
            referencedRelation: "clans"
            referencedColumns: ["id"]
          },
        ]
      }
      clan_upgrade_config: {
        Row: {
          base_cost_fc: number
          bonus_cap: number
          bonus_kind: string
          bonus_per_level: number
          code: string
          cost_growth: number
          description: string
          enabled: boolean
          label: string
          max_level: number
          required_clan_level: number
          updated_at: string
        }
        Insert: {
          base_cost_fc?: number
          bonus_cap?: number
          bonus_kind?: string
          bonus_per_level?: number
          code: string
          cost_growth?: number
          description?: string
          enabled?: boolean
          label: string
          max_level?: number
          required_clan_level?: number
          updated_at?: string
        }
        Update: {
          base_cost_fc?: number
          bonus_cap?: number
          bonus_kind?: string
          bonus_per_level?: number
          code?: string
          cost_growth?: number
          description?: string
          enabled?: boolean
          label?: string
          max_level?: number
          required_clan_level?: number
          updated_at?: string
        }
        Relationships: []
      }
      clan_upgrades: {
        Row: {
          clan_id: string
          code: string
          level: number
          updated_at: string
        }
        Insert: {
          clan_id: string
          code: string
          level?: number
          updated_at?: string
        }
        Update: {
          clan_id?: string
          code?: string
          level?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "clan_upgrades_clan_id_fkey"
            columns: ["clan_id"]
            isOneToOne: false
            referencedRelation: "clans"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "clan_upgrades_code_fkey"
            columns: ["code"]
            isOneToOne: false
            referencedRelation: "clan_upgrade_config"
            referencedColumns: ["code"]
          },
        ]
      }
      clan_war_attacks: {
        Row: {
          attacker_clan: string
          attacker_power: number
          attacker_user: string
          battle: Json
          client_key: string | null
          created_at: string
          defender_clan: string
          defender_power: number
          defender_user: string
          id: string
          perfect: boolean
          points: number
          result: string
          sector: string
          upset_bonus: number
          war_id: string
        }
        Insert: {
          attacker_clan: string
          attacker_power?: number
          attacker_user: string
          battle?: Json
          client_key?: string | null
          created_at?: string
          defender_clan: string
          defender_power?: number
          defender_user: string
          id?: string
          perfect?: boolean
          points?: number
          result: string
          sector: string
          upset_bonus?: number
          war_id: string
        }
        Update: {
          attacker_clan?: string
          attacker_power?: number
          attacker_user?: string
          battle?: Json
          client_key?: string | null
          created_at?: string
          defender_clan?: string
          defender_power?: number
          defender_user?: string
          id?: string
          perfect?: boolean
          points?: number
          result?: string
          sector?: string
          upset_bonus?: number
          war_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "clan_war_attacks_war_id_fkey"
            columns: ["war_id"]
            isOneToOne: false
            referencedRelation: "clan_wars"
            referencedColumns: ["id"]
          },
        ]
      }
      clan_war_defenses: {
        Row: {
          clan_id: string
          hero_ids: string[]
          id: string
          locked_at: string | null
          pet_buffs: Json
          pet_id: string | null
          power: number
          team_json: Json
          updated_at: string
          user_id: string
          war_id: string
        }
        Insert: {
          clan_id: string
          hero_ids?: string[]
          id?: string
          locked_at?: string | null
          pet_buffs?: Json
          pet_id?: string | null
          power?: number
          team_json?: Json
          updated_at?: string
          user_id: string
          war_id: string
        }
        Update: {
          clan_id?: string
          hero_ids?: string[]
          id?: string
          locked_at?: string | null
          pet_buffs?: Json
          pet_id?: string | null
          power?: number
          team_json?: Json
          updated_at?: string
          user_id?: string
          war_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "clan_war_defenses_war_id_fkey"
            columns: ["war_id"]
            isOneToOne: false
            referencedRelation: "clan_wars"
            referencedColumns: ["id"]
          },
        ]
      }
      clan_war_rating_history: {
        Row: {
          clan_id: string
          created_at: string
          delta: number
          id: string
          rating_after: number
          rating_before: number
          result: string
          season_id: string | null
          war_id: string | null
        }
        Insert: {
          clan_id: string
          created_at?: string
          delta: number
          id?: string
          rating_after: number
          rating_before: number
          result: string
          season_id?: string | null
          war_id?: string | null
        }
        Update: {
          clan_id?: string
          created_at?: string
          delta?: number
          id?: string
          rating_after?: number
          rating_before?: number
          result?: string
          season_id?: string | null
          war_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "clan_war_rating_history_war_id_fkey"
            columns: ["war_id"]
            isOneToOne: false
            referencedRelation: "clan_wars"
            referencedColumns: ["id"]
          },
        ]
      }
      clan_war_rewards: {
        Row: {
          clan_id: string
          created_at: string
          id: string
          payload: Json
          result: string
          user_id: string
          war_id: string
        }
        Insert: {
          clan_id: string
          created_at?: string
          id?: string
          payload?: Json
          result: string
          user_id: string
          war_id: string
        }
        Update: {
          clan_id?: string
          created_at?: string
          id?: string
          payload?: Json
          result?: string
          user_id?: string
          war_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "clan_war_rewards_war_id_fkey"
            columns: ["war_id"]
            isOneToOne: false
            referencedRelation: "clan_wars"
            referencedColumns: ["id"]
          },
        ]
      }
      clan_war_rosters: {
        Row: {
          attacks_total: number
          attacks_used: number
          clan_id: string
          created_at: string
          defeats_taken: number
          id: string
          losses: number
          points_earned: number
          sector: string
          team_power_snapshot: number
          user_id: string
          war_id: string
          wins: number
        }
        Insert: {
          attacks_total?: number
          attacks_used?: number
          clan_id: string
          created_at?: string
          defeats_taken?: number
          id?: string
          losses?: number
          points_earned?: number
          sector?: string
          team_power_snapshot?: number
          user_id: string
          war_id: string
          wins?: number
        }
        Update: {
          attacks_total?: number
          attacks_used?: number
          clan_id?: string
          created_at?: string
          defeats_taken?: number
          id?: string
          losses?: number
          points_earned?: number
          sector?: string
          team_power_snapshot?: number
          user_id?: string
          war_id?: string
          wins?: number
        }
        Relationships: [
          {
            foreignKeyName: "clan_war_rosters_war_id_fkey"
            columns: ["war_id"]
            isOneToOne: false
            referencedRelation: "clan_wars"
            referencedColumns: ["id"]
          },
        ]
      }
      clan_war_seasons: {
        Row: {
          code: string
          created_at: string
          ends_at: string
          id: string
          name: string
          starts_at: string
          status: string
          ton_prize_enabled: boolean
          ton_prize_ton: number
        }
        Insert: {
          code: string
          created_at?: string
          ends_at?: string
          id?: string
          name?: string
          starts_at?: string
          status?: string
          ton_prize_enabled?: boolean
          ton_prize_ton?: number
        }
        Update: {
          code?: string
          created_at?: string
          ends_at?: string
          id?: string
          name?: string
          starts_at?: string
          status?: string
          ton_prize_enabled?: boolean
          ton_prize_ton?: number
        }
        Relationships: []
      }
      clan_war_sector_state: {
        Row: {
          clan_id: string
          conquered_at: string | null
          defeats: number
          id: string
          sector: string
          war_id: string
        }
        Insert: {
          clan_id: string
          conquered_at?: string | null
          defeats?: number
          id?: string
          sector: string
          war_id: string
        }
        Update: {
          clan_id?: string
          conquered_at?: string | null
          defeats?: number
          id?: string
          sector?: string
          war_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "clan_war_sector_state_war_id_fkey"
            columns: ["war_id"]
            isOneToOne: false
            referencedRelation: "clan_wars"
            referencedColumns: ["id"]
          },
        ]
      }
      clan_wars: {
        Row: {
          attacks_per_player: number
          battle_ends_at: string | null
          battle_starts_at: string | null
          clan_a: string | null
          clan_b: string | null
          created_at: string
          ends_at: string | null
          finished_at: string | null
          id: string
          preparation_starts_at: string | null
          registered_by: string | null
          roster_size: number
          score_a: number
          score_b: number
          season_id: string | null
          settled_at: string | null
          starts_at: string | null
          status: string
          test_war: boolean
          winner_clan_id: string | null
        }
        Insert: {
          attacks_per_player?: number
          battle_ends_at?: string | null
          battle_starts_at?: string | null
          clan_a?: string | null
          clan_b?: string | null
          created_at?: string
          ends_at?: string | null
          finished_at?: string | null
          id?: string
          preparation_starts_at?: string | null
          registered_by?: string | null
          roster_size?: number
          score_a?: number
          score_b?: number
          season_id?: string | null
          settled_at?: string | null
          starts_at?: string | null
          status?: string
          test_war?: boolean
          winner_clan_id?: string | null
        }
        Update: {
          attacks_per_player?: number
          battle_ends_at?: string | null
          battle_starts_at?: string | null
          clan_a?: string | null
          clan_b?: string | null
          created_at?: string
          ends_at?: string | null
          finished_at?: string | null
          id?: string
          preparation_starts_at?: string | null
          registered_by?: string | null
          roster_size?: number
          score_a?: number
          score_b?: number
          season_id?: string | null
          settled_at?: string | null
          starts_at?: string | null
          status?: string
          test_war?: boolean
          winner_clan_id?: string | null
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
          {
            foreignKeyName: "clan_wars_season_id_fkey"
            columns: ["season_id"]
            isOneToOne: false
            referencedRelation: "clan_war_seasons"
            referencedColumns: ["id"]
          },
        ]
      }
      clan_weekly_cycles: {
        Row: {
          active_members: number
          clan_id: string
          created_at: string
          ends_at: string | null
          id: string
          started_at: string
          status: string
          target: number
          total_contribution: number
          updated_at: string
          week_key: string
        }
        Insert: {
          active_members?: number
          clan_id: string
          created_at?: string
          ends_at?: string | null
          id?: string
          started_at?: string
          status?: string
          target?: number
          total_contribution?: number
          updated_at?: string
          week_key: string
        }
        Update: {
          active_members?: number
          clan_id?: string
          created_at?: string
          ends_at?: string | null
          id?: string
          started_at?: string
          status?: string
          target?: number
          total_contribution?: number
          updated_at?: string
          week_key?: string
        }
        Relationships: [
          {
            foreignKeyName: "clan_weekly_cycles_clan_id_fkey"
            columns: ["clan_id"]
            isOneToOne: false
            referencedRelation: "clans"
            referencedColumns: ["id"]
          },
        ]
      }
      clan_weekly_member_progress: {
        Row: {
          clan_id: string
          contribution: number
          cycle_id: string
          joined_at: string
          raid_damage: number
          updated_at: string
          user_id: string
        }
        Insert: {
          clan_id: string
          contribution?: number
          cycle_id: string
          joined_at?: string
          raid_damage?: number
          updated_at?: string
          user_id: string
        }
        Update: {
          clan_id?: string
          contribution?: number
          cycle_id?: string
          joined_at?: string
          raid_damage?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "clan_weekly_member_progress_clan_id_fkey"
            columns: ["clan_id"]
            isOneToOne: false
            referencedRelation: "clans"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "clan_weekly_member_progress_cycle_id_fkey"
            columns: ["cycle_id"]
            isOneToOne: false
            referencedRelation: "clan_weekly_cycles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "clan_weekly_member_progress_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
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
          daily_contribution_max_fc: number | null
          daily_contribution_max_myth: number | null
          daily_contribution_min_fc: number | null
          daily_contribution_min_myth: number | null
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
          war_draws: number
          war_losses: number
          war_points_total: number
          war_rating: number
          war_wins: number
          xp: number
        }
        Insert: {
          clan_points?: number
          created_at?: string
          daily_contribution_max_fc?: number | null
          daily_contribution_max_myth?: number | null
          daily_contribution_min_fc?: number | null
          daily_contribution_min_myth?: number | null
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
          war_draws?: number
          war_losses?: number
          war_points_total?: number
          war_rating?: number
          war_wins?: number
          xp?: number
        }
        Update: {
          clan_points?: number
          created_at?: string
          daily_contribution_max_fc?: number | null
          daily_contribution_max_myth?: number | null
          daily_contribution_min_fc?: number | null
          daily_contribution_min_myth?: number | null
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
          war_draws?: number
          war_losses?: number
          war_points_total?: number
          war_rating?: number
          war_wins?: number
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
      device_accounts: {
        Row: {
          admin_bypass: boolean
          created_at: string
          device_hash: string
          first_seen_at: string
          id: string
          last_seen_at: string
          player_id: string | null
          sessions: number
          slot: number
          status: string
          telegram_id: number
          updated_at: string
        }
        Insert: {
          admin_bypass?: boolean
          created_at?: string
          device_hash: string
          first_seen_at?: string
          id?: string
          last_seen_at?: string
          player_id?: string | null
          sessions?: number
          slot?: number
          status?: string
          telegram_id: number
          updated_at?: string
        }
        Update: {
          admin_bypass?: boolean
          created_at?: string
          device_hash?: string
          first_seen_at?: string
          id?: string
          last_seen_at?: string
          player_id?: string | null
          sessions?: number
          slot?: number
          status?: string
          telegram_id?: number
          updated_at?: string
        }
        Relationships: []
      }
      device_allowlist: {
        Row: {
          created_at: string
          created_by: number | null
          device_hash: string | null
          id: string
          reason: string | null
          telegram_id: number | null
        }
        Insert: {
          created_at?: string
          created_by?: number | null
          device_hash?: string | null
          id?: string
          reason?: string | null
          telegram_id?: number | null
        }
        Update: {
          created_at?: string
          created_by?: number | null
          device_hash?: string | null
          id?: string
          reason?: string | null
          telegram_id?: number | null
        }
        Relationships: []
      }
      device_registry: {
        Row: {
          created_at: string
          device_hash: string
          first_seen_at: string
          id: string
          last_ip_hash: string | null
          last_seen_at: string
          notes: string | null
          platform: string | null
          risk_score: number
          risk_status: string
          seen_count: number
          updated_at: string
          user_agent_hash: string | null
        }
        Insert: {
          created_at?: string
          device_hash: string
          first_seen_at?: string
          id?: string
          last_ip_hash?: string | null
          last_seen_at?: string
          notes?: string | null
          platform?: string | null
          risk_score?: number
          risk_status?: string
          seen_count?: number
          updated_at?: string
          user_agent_hash?: string | null
        }
        Update: {
          created_at?: string
          device_hash?: string
          first_seen_at?: string
          id?: string
          last_ip_hash?: string | null
          last_seen_at?: string
          notes?: string | null
          platform?: string | null
          risk_score?: number
          risk_status?: string
          seen_count?: number
          updated_at?: string
          user_agent_hash?: string | null
        }
        Relationships: []
      }
      device_review_requests: {
        Row: {
          created_at: string
          device_hash: string
          id: string
          message: string | null
          reviewed_at: string | null
          reviewed_by: number | null
          status: string
          telegram_id: number
        }
        Insert: {
          created_at?: string
          device_hash: string
          id?: string
          message?: string | null
          reviewed_at?: string | null
          reviewed_by?: number | null
          status?: string
          telegram_id: number
        }
        Update: {
          created_at?: string
          device_hash?: string
          id?: string
          message?: string | null
          reviewed_at?: string | null
          reviewed_by?: number | null
          status?: string
          telegram_id?: number
        }
        Relationships: []
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
      equipment_templates: {
        Row: {
          bonus_attack: number
          bonus_defense: number
          bonus_hp: number
          code: string
          created_at: string
          description: string
          founder_line: boolean
          hero_class: string | null
          id: string
          image_url: string
          is_active: boolean
          is_nft: boolean
          kind: string
          name: string
          power: number
          rarity: string
          slot: string
          tier: number
          updated_at: string
          veteran_line: boolean
        }
        Insert: {
          bonus_attack?: number
          bonus_defense?: number
          bonus_hp?: number
          code: string
          created_at?: string
          description?: string
          founder_line?: boolean
          hero_class?: string | null
          id?: string
          image_url: string
          is_active?: boolean
          is_nft?: boolean
          kind: string
          name: string
          power?: number
          rarity: string
          slot: string
          tier?: number
          updated_at?: string
          veteran_line?: boolean
        }
        Update: {
          bonus_attack?: number
          bonus_defense?: number
          bonus_hp?: number
          code?: string
          created_at?: string
          description?: string
          founder_line?: boolean
          hero_class?: string | null
          id?: string
          image_url?: string
          is_active?: boolean
          is_nft?: boolean
          kind?: string
          name?: string
          power?: number
          rarity?: string
          slot?: string
          tier?: number
          updated_at?: string
          veteran_line?: boolean
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
      expedition_attempts: {
        Row: {
          created_at: string
          extra_available: number
          fc_extra_purchases_used: number
          free_used: number
          mission_id: string
          period: string
          rewarded_ads_used: number
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          extra_available?: number
          fc_extra_purchases_used?: number
          free_used?: number
          mission_id: string
          period: string
          rewarded_ads_used?: number
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          extra_available?: number
          fc_extra_purchases_used?: number
          free_used?: number
          mission_id?: string
          period?: string
          rewarded_ads_used?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "expedition_attempts_mission_id_fkey"
            columns: ["mission_id"]
            isOneToOne: false
            referencedRelation: "expedition_missions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "expedition_attempts_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      expedition_boost_ad_views: {
        Row: {
          created_at: string
          expedition_id: string
          granted_at: string | null
          id: string
          seconds_saved: number | null
          status: string
          user_id: string
        }
        Insert: {
          created_at?: string
          expedition_id: string
          granted_at?: string | null
          id?: string
          seconds_saved?: number | null
          status?: string
          user_id: string
        }
        Update: {
          created_at?: string
          expedition_id?: string
          granted_at?: string | null
          id?: string
          seconds_saved?: number | null
          status?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "expedition_boost_ad_views_expedition_id_fkey"
            columns: ["expedition_id"]
            isOneToOne: false
            referencedRelation: "pet_expeditions"
            referencedColumns: ["id"]
          },
        ]
      }
      expedition_extra_grants: {
        Row: {
          cost_fc: number
          created_at: string
          granted_at: string | null
          id: string
          idempotency_key: string | null
          mission_id: string
          period: string
          source: string
          status: string
          user_id: string
        }
        Insert: {
          cost_fc?: number
          created_at?: string
          granted_at?: string | null
          id?: string
          idempotency_key?: string | null
          mission_id: string
          period: string
          source: string
          status?: string
          user_id: string
        }
        Update: {
          cost_fc?: number
          created_at?: string
          granted_at?: string | null
          id?: string
          idempotency_key?: string | null
          mission_id?: string
          period?: string
          source?: string
          status?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "expedition_extra_grants_mission_id_fkey"
            columns: ["mission_id"]
            isOneToOne: false
            referencedRelation: "expedition_missions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "expedition_extra_grants_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      expedition_missions: {
        Row: {
          base_success: number
          code: string
          duration_hours: number
          enabled: boolean
          id: string
          name: string
          rarity: string
          recommended_element: string | null
          required_power: number
          reward_pool: Json
          sort_order: number
          updated_at: string
        }
        Insert: {
          base_success?: number
          code: string
          duration_hours: number
          enabled?: boolean
          id?: string
          name: string
          rarity?: string
          recommended_element?: string | null
          required_power: number
          reward_pool?: Json
          sort_order?: number
          updated_at?: string
        }
        Update: {
          base_success?: number
          code?: string
          duration_hours?: number
          enabled?: boolean
          id?: string
          name?: string
          rarity?: string
          recommended_element?: string | null
          required_power?: number
          reward_pool?: Json
          sort_order?: number
          updated_at?: string
        }
        Relationships: []
      }
      exploit_manual_reviews: {
        Row: {
          claim_id: string | null
          created_at: string
          details: Json
          id: string
          kind: string
          status: string
          user_id: string
        }
        Insert: {
          claim_id?: string | null
          created_at?: string
          details?: Json
          id?: string
          kind: string
          status?: string
          user_id: string
        }
        Update: {
          claim_id?: string | null
          created_at?: string
          details?: Json
          id?: string
          kind?: string
          status?: string
          user_id?: string
        }
        Relationships: []
      }
      exploit_recovery_debts: {
        Row: {
          amount: number
          asset_id: string | null
          asset_type: string
          created_at: string
          id: string
          reason: string
          source_reward_id: string | null
          status: string
          updated_at: string
          user_id: string
        }
        Insert: {
          amount?: number
          asset_id?: string | null
          asset_type: string
          created_at?: string
          id?: string
          reason?: string
          source_reward_id?: string | null
          status?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          amount?: number
          asset_id?: string | null
          asset_type?: string
          created_at?: string
          id?: string
          reason?: string
          source_reward_id?: string | null
          status?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      exploit_reversal_ledger: {
        Row: {
          amount: number
          asset_id: string | null
          asset_type: string
          balance_after: number | null
          created_at: string
          id: string
          kind: string
          reversal_id: string | null
          user_id: string
        }
        Insert: {
          amount: number
          asset_id?: string | null
          asset_type: string
          balance_after?: number | null
          created_at?: string
          id?: string
          kind?: string
          reversal_id?: string | null
          user_id: string
        }
        Update: {
          amount?: number
          asset_id?: string | null
          asset_type?: string
          balance_after?: number | null
          created_at?: string
          id?: string
          kind?: string
          reversal_id?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "exploit_reversal_ledger_reversal_id_fkey"
            columns: ["reversal_id"]
            isOneToOne: false
            referencedRelation: "clan_exploit_reversals"
            referencedColumns: ["id"]
          },
        ]
      }
      familiar_hunt_instances: {
        Row: {
          created_at: string
          id: string
          idempotency_key: string | null
          is_boss: boolean
          loot_pool: string
          loot_table_version: number
          payment_address: string | null
          payment_amount: number
          payment_amount_nano: number
          payment_comment: string | null
          payment_currency: string
          received_amount_nano: number | null
          recommended_power: number
          result_json: Json | null
          rewards: Json
          rounds: number | null
          settled_at: string | null
          stage: number
          stage_name: string | null
          status: string
          team_power: number
          team_snapshot: Json
          total_damage: number | null
          tx_hash: string | null
          updated_at: string
          user_id: string
          victory: boolean | null
        }
        Insert: {
          created_at?: string
          id?: string
          idempotency_key?: string | null
          is_boss?: boolean
          loot_pool?: string
          loot_table_version?: number
          payment_address?: string | null
          payment_amount?: number
          payment_amount_nano?: number
          payment_comment?: string | null
          payment_currency: string
          received_amount_nano?: number | null
          recommended_power?: number
          result_json?: Json | null
          rewards?: Json
          rounds?: number | null
          settled_at?: string | null
          stage: number
          stage_name?: string | null
          status?: string
          team_power?: number
          team_snapshot?: Json
          total_damage?: number | null
          tx_hash?: string | null
          updated_at?: string
          user_id: string
          victory?: boolean | null
        }
        Update: {
          created_at?: string
          id?: string
          idempotency_key?: string | null
          is_boss?: boolean
          loot_pool?: string
          loot_table_version?: number
          payment_address?: string | null
          payment_amount?: number
          payment_amount_nano?: number
          payment_comment?: string | null
          payment_currency?: string
          received_amount_nano?: number | null
          recommended_power?: number
          result_json?: Json | null
          rewards?: Json
          rounds?: number | null
          settled_at?: string | null
          stage?: number
          stage_name?: string | null
          status?: string
          team_power?: number
          team_snapshot?: Json
          total_damage?: number | null
          tx_hash?: string | null
          updated_at?: string
          user_id?: string
          victory?: boolean | null
        }
        Relationships: [
          {
            foreignKeyName: "familiar_hunt_instances_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      familiar_hunt_missions: {
        Row: {
          background: string | null
          code: string
          created_at: string
          description: string | null
          enabled: boolean
          enemies: Json
          entry_cost_fc: number
          entry_cost_ton: number
          id: string
          max_runs_per_day: number
          name: string
          rarity: string
          recommended_power: number
          reward_pool: Json
          sort_order: number
          theme: string
          updated_at: string
        }
        Insert: {
          background?: string | null
          code: string
          created_at?: string
          description?: string | null
          enabled?: boolean
          enemies?: Json
          entry_cost_fc?: number
          entry_cost_ton?: number
          id?: string
          max_runs_per_day?: number
          name: string
          rarity?: string
          recommended_power?: number
          reward_pool?: Json
          sort_order?: number
          theme: string
          updated_at?: string
        }
        Update: {
          background?: string | null
          code?: string
          created_at?: string
          description?: string | null
          enabled?: boolean
          enemies?: Json
          entry_cost_fc?: number
          entry_cost_ton?: number
          id?: string
          max_runs_per_day?: number
          name?: string
          rarity?: string
          recommended_power?: number
          reward_pool?: Json
          sort_order?: number
          theme?: string
          updated_at?: string
        }
        Relationships: []
      }
      familiar_hunt_progress: {
        Row: {
          created_at: string
          current_familiar_hunt_stage: number
          highest_stage_completed: number
          total_runs: number
          total_wins: number
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          current_familiar_hunt_stage?: number
          highest_stage_completed?: number
          total_runs?: number
          total_wins?: number
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          current_familiar_hunt_stage?: number
          highest_stage_completed?: number
          total_runs?: number
          total_wins?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "familiar_hunt_progress_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      familiar_hunt_runs: {
        Row: {
          battle_log: Json
          created_at: string
          game_day: string
          id: string
          idempotency_key: string | null
          mission_id: string
          pet_ids: string[]
          rewards: Json
          rounds: number
          team_power: number
          total_damage: number
          updated_at: string
          user_id: string
          victory: boolean
        }
        Insert: {
          battle_log?: Json
          created_at?: string
          game_day?: string
          id?: string
          idempotency_key?: string | null
          mission_id: string
          pet_ids: string[]
          rewards?: Json
          rounds?: number
          team_power?: number
          total_damage?: number
          updated_at?: string
          user_id: string
          victory?: boolean
        }
        Update: {
          battle_log?: Json
          created_at?: string
          game_day?: string
          id?: string
          idempotency_key?: string | null
          mission_id?: string
          pet_ids?: string[]
          rewards?: Json
          rounds?: number
          team_power?: number
          total_damage?: number
          updated_at?: string
          user_id?: string
          victory?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "familiar_hunt_runs_mission_id_fkey"
            columns: ["mission_id"]
            isOneToOne: false
            referencedRelation: "familiar_hunt_missions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "familiar_hunt_runs_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      familiar_hunt_settings: {
        Row: {
          created_at: string
          difficulty: Json
          enabled: boolean
          entry_fc: number
          entry_ton: number
          fc_loot: Json
          id: boolean
          loot_table_version: number
          stage_pool: Json
          ton_loot: Json
          updated_at: string
        }
        Insert: {
          created_at?: string
          difficulty?: Json
          enabled?: boolean
          entry_fc?: number
          entry_ton?: number
          fc_loot?: Json
          id?: boolean
          loot_table_version?: number
          stage_pool?: Json
          ton_loot?: Json
          updated_at?: string
        }
        Update: {
          created_at?: string
          difficulty?: Json
          enabled?: boolean
          entry_fc?: number
          entry_ton?: number
          fc_loot?: Json
          id?: boolean
          loot_table_version?: number
          stage_pool?: Json
          ton_loot?: Json
          updated_at?: string
        }
        Relationships: []
      }
      founder_pack_config: {
        Row: {
          badge_enabled: boolean
          eligibility_days: number
          enabled: boolean
          ends_at: string | null
          equipment_chest_code: string
          fragments: number
          frame_enabled: boolean
          hero_daily_myth: number
          hero_key: string
          id: boolean
          legendary_chests: number
          myth_amount: number
          pack_version: number
          pass_tier: string
          pet_daily_myth: number
          pet_slug: string
          popup_enabled: boolean
          popup_frequency: string
          popup_priority: number
          price_ton: number
          require_new_account: boolean
          resource_chest: Json
          resource_chest_code: string
          signup_from: string
          start_at: string
          updated_at: string
          weapon_code: string | null
        }
        Insert: {
          badge_enabled?: boolean
          eligibility_days?: number
          enabled?: boolean
          ends_at?: string | null
          equipment_chest_code?: string
          fragments?: number
          frame_enabled?: boolean
          hero_daily_myth?: number
          hero_key?: string
          id?: boolean
          legendary_chests?: number
          myth_amount?: number
          pack_version?: number
          pass_tier?: string
          pet_daily_myth?: number
          pet_slug?: string
          popup_enabled?: boolean
          popup_frequency?: string
          popup_priority?: number
          price_ton?: number
          require_new_account?: boolean
          resource_chest?: Json
          resource_chest_code?: string
          signup_from?: string
          start_at?: string
          updated_at?: string
          weapon_code?: string | null
        }
        Update: {
          badge_enabled?: boolean
          eligibility_days?: number
          enabled?: boolean
          ends_at?: string | null
          equipment_chest_code?: string
          fragments?: number
          frame_enabled?: boolean
          hero_daily_myth?: number
          hero_key?: string
          id?: boolean
          legendary_chests?: number
          myth_amount?: number
          pack_version?: number
          pass_tier?: string
          pet_daily_myth?: number
          pet_slug?: string
          popup_enabled?: boolean
          popup_frequency?: string
          popup_priority?: number
          price_ton?: number
          require_new_account?: boolean
          resource_chest?: Json
          resource_chest_code?: string
          signup_from?: string
          start_at?: string
          updated_at?: string
          weapon_code?: string | null
        }
        Relationships: []
      }
      founder_pack_purchases: {
        Row: {
          amount_nano: string
          confirmed_at: string | null
          created_at: string
          delivery: Json
          expires_at: string
          id: string
          idempotency_key: string | null
          pack_version: number
          payment_address: string | null
          payment_comment: string | null
          payment_method: string
          price_ton: number
          reward_snapshot: Json
          settled_at: string | null
          status: string
          telegram_id: number | null
          tx_hash: string | null
          user_id: string
        }
        Insert: {
          amount_nano: string
          confirmed_at?: string | null
          created_at?: string
          delivery?: Json
          expires_at?: string
          id?: string
          idempotency_key?: string | null
          pack_version?: number
          payment_address?: string | null
          payment_comment?: string | null
          payment_method?: string
          price_ton: number
          reward_snapshot?: Json
          settled_at?: string | null
          status?: string
          telegram_id?: number | null
          tx_hash?: string | null
          user_id: string
        }
        Update: {
          amount_nano?: string
          confirmed_at?: string | null
          created_at?: string
          delivery?: Json
          expires_at?: string
          id?: string
          idempotency_key?: string | null
          pack_version?: number
          payment_address?: string | null
          payment_comment?: string | null
          payment_method?: string
          price_ton?: number
          reward_snapshot?: Json
          settled_at?: string | null
          status?: string
          telegram_id?: number | null
          tx_hash?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "founder_pack_purchases_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      fragment_summon_history: {
        Row: {
          created_at: string
          fragments_spent: number
          hero_id: string | null
          hero_key: string | null
          hero_name: string | null
          id: string
          idempotency_key: string | null
          result: Json
          rolled_rarity: string
          user_id: string
        }
        Insert: {
          created_at?: string
          fragments_spent: number
          hero_id?: string | null
          hero_key?: string | null
          hero_name?: string | null
          id?: string
          idempotency_key?: string | null
          result?: Json
          rolled_rarity: string
          user_id: string
        }
        Update: {
          created_at?: string
          fragments_spent?: number
          hero_id?: string | null
          hero_key?: string | null
          hero_name?: string | null
          id?: string
          idempotency_key?: string | null
          result?: Json
          rolled_rarity?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "fragment_summon_history_user_id_fkey"
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
          account_ton_mining_bonus: number
          avatar_border: string | null
          avatar_url: string | null
          ban_reason: string | null
          banned: boolean
          banned_at: string | null
          boss_defeats: number
          created_at: string
          display_name: string | null
          first_name: string | null
          forge_coins: number
          hero_mining_claimed_at: string | null
          hero_mining_invested_ton: number
          hero_mining_lifetime_myth: number
          hero_mining_lifetime_ton: number
          hero_mining_returned_ton: number
          hero_mining_unclaimed_myth: number
          hero_mining_unclaimed_ton: number
          id: string
          language: string
          language_locked: boolean
          last_name: string | null
          last_seen_at: string
          market_cooldown_until: string | null
          market_pending_fc: number
          market_pending_ton: number
          market_restricted_until: string | null
          market_trust: string
          name: string | null
          premium_title: string | null
          premium_until: string | null
          pvp_banned: boolean
          pvp_losses: number
          pvp_tickets: number
          pvp_tickets_reset_at: string | null
          pvp_tickets_reset_day: string | null
          pvp_trophies: number
          pvp_wins: number
          starter_pack_claimed: boolean
          starter_pack_claimed_at: string | null
          telegram_id: number
          ton_balance: number
          ton_reserved: number
          updated_at: string
          username: string | null
          vip_until: string | null
        }
        Insert: {
          account_ton_mining_bonus?: number
          avatar_border?: string | null
          avatar_url?: string | null
          ban_reason?: string | null
          banned?: boolean
          banned_at?: string | null
          boss_defeats?: number
          created_at?: string
          display_name?: string | null
          first_name?: string | null
          forge_coins?: number
          hero_mining_claimed_at?: string | null
          hero_mining_invested_ton?: number
          hero_mining_lifetime_myth?: number
          hero_mining_lifetime_ton?: number
          hero_mining_returned_ton?: number
          hero_mining_unclaimed_myth?: number
          hero_mining_unclaimed_ton?: number
          id?: string
          language?: string
          language_locked?: boolean
          last_name?: string | null
          last_seen_at?: string
          market_cooldown_until?: string | null
          market_pending_fc?: number
          market_pending_ton?: number
          market_restricted_until?: string | null
          market_trust?: string
          name?: string | null
          premium_title?: string | null
          premium_until?: string | null
          pvp_banned?: boolean
          pvp_losses?: number
          pvp_tickets?: number
          pvp_tickets_reset_at?: string | null
          pvp_tickets_reset_day?: string | null
          pvp_trophies?: number
          pvp_wins?: number
          starter_pack_claimed?: boolean
          starter_pack_claimed_at?: string | null
          telegram_id: number
          ton_balance?: number
          ton_reserved?: number
          updated_at?: string
          username?: string | null
          vip_until?: string | null
        }
        Update: {
          account_ton_mining_bonus?: number
          avatar_border?: string | null
          avatar_url?: string | null
          ban_reason?: string | null
          banned?: boolean
          banned_at?: string | null
          boss_defeats?: number
          created_at?: string
          display_name?: string | null
          first_name?: string | null
          forge_coins?: number
          hero_mining_claimed_at?: string | null
          hero_mining_invested_ton?: number
          hero_mining_lifetime_myth?: number
          hero_mining_lifetime_ton?: number
          hero_mining_returned_ton?: number
          hero_mining_unclaimed_myth?: number
          hero_mining_unclaimed_ton?: number
          id?: string
          language?: string
          language_locked?: boolean
          last_name?: string | null
          last_seen_at?: string
          market_cooldown_until?: string | null
          market_pending_fc?: number
          market_pending_ton?: number
          market_restricted_until?: string | null
          market_trust?: string
          name?: string | null
          premium_title?: string | null
          premium_until?: string | null
          pvp_banned?: boolean
          pvp_losses?: number
          pvp_tickets?: number
          pvp_tickets_reset_at?: string | null
          pvp_tickets_reset_day?: string | null
          pvp_trophies?: number
          pvp_wins?: number
          starter_pack_claimed?: boolean
          starter_pack_claimed_at?: string | null
          telegram_id?: number
          ton_balance?: number
          ton_reserved?: number
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
      global_boss_attack_log: {
        Row: {
          attack_type: string
          boss_id: string | null
          created_at: string
          cycle_id: string | null
          damage: number
          id: string
          pass_type: string | null
          team_power: number
          telegram_id: number | null
          user_id: string
        }
        Insert: {
          attack_type: string
          boss_id?: string | null
          created_at?: string
          cycle_id?: string | null
          damage?: number
          id?: string
          pass_type?: string | null
          team_power?: number
          telegram_id?: number | null
          user_id: string
        }
        Update: {
          attack_type?: string
          boss_id?: string | null
          created_at?: string
          cycle_id?: string | null
          damage?: number
          id?: string
          pass_type?: string | null
          team_power?: number
          telegram_id?: number | null
          user_id?: string
        }
        Relationships: []
      }
      global_boss_auto_attack: {
        Row: {
          attacks_total: number
          created_at: string
          enabled: boolean
          last_auto_attack_at: string | null
          next_auto_attack_at: string
          paused_reason: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          attacks_total?: number
          created_at?: string
          enabled?: boolean
          last_auto_attack_at?: string | null
          next_auto_attack_at?: string
          paused_reason?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          attacks_total?: number
          created_at?: string
          enabled?: boolean
          last_auto_attack_at?: string | null
          next_auto_attack_at?: string
          paused_reason?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "global_boss_auto_attack_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      global_boss_cycles: {
        Row: {
          atk_multiplier: number
          boss_attack: number
          boss_background: string | null
          boss_defense: number
          boss_image: string | null
          boss_key: string
          boss_level: number
          boss_name: string
          boss_number: number | null
          boss_subtitle: string | null
          boss_theme: string | null
          created_at: string
          current_hp: number
          cycle_number: number
          defeated_at: string | null
          defense_multiplier: number
          distributed_at: string | null
          ended_reason: string | null
          ends_at: string | null
          hp_multiplier: number
          id: string
          max_hp: number
          minimum_damage_fixed: number
          minimum_damage_percent: number
          minimum_reward_fc: number
          participants: number
          rank_bonus: Json
          rank_bonus_enabled: boolean
          reward_pool_fc: number
          rotation_number: number
          starts_at: string
          status: string
          template_id: string | null
          total_damage: number
          updated_at: string
        }
        Insert: {
          atk_multiplier?: number
          boss_attack?: number
          boss_background?: string | null
          boss_defense?: number
          boss_image?: string | null
          boss_key: string
          boss_level?: number
          boss_name: string
          boss_number?: number | null
          boss_subtitle?: string | null
          boss_theme?: string | null
          created_at?: string
          current_hp: number
          cycle_number: number
          defeated_at?: string | null
          defense_multiplier?: number
          distributed_at?: string | null
          ended_reason?: string | null
          ends_at?: string | null
          hp_multiplier?: number
          id?: string
          max_hp: number
          minimum_damage_fixed?: number
          minimum_damage_percent?: number
          minimum_reward_fc?: number
          participants?: number
          rank_bonus?: Json
          rank_bonus_enabled?: boolean
          reward_pool_fc?: number
          rotation_number?: number
          starts_at?: string
          status?: string
          template_id?: string | null
          total_damage?: number
          updated_at?: string
        }
        Update: {
          atk_multiplier?: number
          boss_attack?: number
          boss_background?: string | null
          boss_defense?: number
          boss_image?: string | null
          boss_key?: string
          boss_level?: number
          boss_name?: string
          boss_number?: number | null
          boss_subtitle?: string | null
          boss_theme?: string | null
          created_at?: string
          current_hp?: number
          cycle_number?: number
          defeated_at?: string | null
          defense_multiplier?: number
          distributed_at?: string | null
          ended_reason?: string | null
          ends_at?: string | null
          hp_multiplier?: number
          id?: string
          max_hp?: number
          minimum_damage_fixed?: number
          minimum_damage_percent?: number
          minimum_reward_fc?: number
          participants?: number
          rank_bonus?: Json
          rank_bonus_enabled?: boolean
          reward_pool_fc?: number
          rotation_number?: number
          starts_at?: string
          status?: string
          template_id?: string | null
          total_damage?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "global_boss_cycles_template_id_fkey"
            columns: ["template_id"]
            isOneToOne: false
            referencedRelation: "global_boss_templates"
            referencedColumns: ["id"]
          },
        ]
      }
      global_boss_damage_outliers: {
        Row: {
          boss_defense: number
          combat_id: string | null
          created_at: string
          cycle_id: string | null
          damage_credited: number
          damage_factor: number
          details: Json
          expected_max: number
          gap_seconds: number
          id: string
          kind: string
          pass_tier: string | null
          team_damage_per_tick: number
          telegram_id: number | null
          ticks_allowed: number
          user_id: string | null
          window_seconds: number
        }
        Insert: {
          boss_defense?: number
          combat_id?: string | null
          created_at?: string
          cycle_id?: string | null
          damage_credited?: number
          damage_factor?: number
          details?: Json
          expected_max?: number
          gap_seconds?: number
          id?: string
          kind?: string
          pass_tier?: string | null
          team_damage_per_tick?: number
          telegram_id?: number | null
          ticks_allowed?: number
          user_id?: string | null
          window_seconds?: number
        }
        Update: {
          boss_defense?: number
          combat_id?: string | null
          created_at?: string
          cycle_id?: string | null
          damage_credited?: number
          damage_factor?: number
          details?: Json
          expected_max?: number
          gap_seconds?: number
          id?: string
          kind?: string
          pass_tier?: string | null
          team_damage_per_tick?: number
          telegram_id?: number | null
          ticks_allowed?: number
          user_id?: string | null
          window_seconds?: number
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
      global_boss_templates: {
        Row: {
          background_url: string | null
          base_attack: number
          base_defense: number
          boss_level: number
          boss_number: number
          code: string
          created_at: string
          duration_seconds: number
          enabled: boolean
          id: string
          image_url: string | null
          max_hp: number
          name: string
          reward_fc: number
          sort_order: number
          subtitle: string | null
          theme: string
          updated_at: string
        }
        Insert: {
          background_url?: string | null
          base_attack?: number
          base_defense?: number
          boss_level?: number
          boss_number: number
          code: string
          created_at?: string
          duration_seconds?: number
          enabled?: boolean
          id?: string
          image_url?: string | null
          max_hp: number
          name: string
          reward_fc: number
          sort_order?: number
          subtitle?: string | null
          theme?: string
          updated_at?: string
        }
        Update: {
          background_url?: string | null
          base_attack?: number
          base_defense?: number
          boss_level?: number
          boss_number?: number
          code?: string
          created_at?: string
          duration_seconds?: number
          enabled?: boolean
          id?: string
          image_url?: string | null
          max_hp?: number
          name?: string
          reward_fc?: number
          sort_order?: number
          subtitle?: string | null
          theme?: string
          updated_at?: string
        }
        Relationships: []
      }
      global_roulette_awards: {
        Row: {
          amount: number | null
          created_at: string
          cycle_id: string | null
          id: string
          payload: Json
          reward_class: string
          reward_key: string | null
          source_type: string
          spin_id: string | null
          user_id: string | null
        }
        Insert: {
          amount?: number | null
          created_at?: string
          cycle_id?: string | null
          id?: string
          payload?: Json
          reward_class: string
          reward_key?: string | null
          source_type: string
          spin_id?: string | null
          user_id?: string | null
        }
        Update: {
          amount?: number | null
          created_at?: string
          cycle_id?: string | null
          id?: string
          payload?: Json
          reward_class?: string
          reward_key?: string | null
          source_type?: string
          spin_id?: string | null
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "global_roulette_awards_cycle_id_fkey"
            columns: ["cycle_id"]
            isOneToOne: false
            referencedRelation: "global_roulette_cycles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "global_roulette_awards_spin_id_fkey"
            columns: ["spin_id"]
            isOneToOne: false
            referencedRelation: "global_roulette_spins"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "global_roulette_awards_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      global_roulette_cycles: {
        Row: {
          completed_at: string | null
          config_snapshot: Json
          created_at: string
          cycle_number: number
          global_spend_nanoton: number
          id: string
          reward_attempts: number
          reward_delivered_at: string | null
          reward_delivery_key: string | null
          reward_last_error: string | null
          reward_status: string
          started_at: string
          status: string
          target_reference_cost_nanoton: number
          target_reward_id: string
          target_reward_type: string
          threshold_reached_at: string | null
          updated_at: string
          winner_user_id: string | null
          winning_spin_id: string | null
        }
        Insert: {
          completed_at?: string | null
          config_snapshot?: Json
          created_at?: string
          cycle_number?: number
          global_spend_nanoton?: number
          id?: string
          reward_attempts?: number
          reward_delivered_at?: string | null
          reward_delivery_key?: string | null
          reward_last_error?: string | null
          reward_status?: string
          started_at?: string
          status?: string
          target_reference_cost_nanoton: number
          target_reward_id: string
          target_reward_type: string
          threshold_reached_at?: string | null
          updated_at?: string
          winner_user_id?: string | null
          winning_spin_id?: string | null
        }
        Update: {
          completed_at?: string | null
          config_snapshot?: Json
          created_at?: string
          cycle_number?: number
          global_spend_nanoton?: number
          id?: string
          reward_attempts?: number
          reward_delivered_at?: string | null
          reward_delivery_key?: string | null
          reward_last_error?: string | null
          reward_status?: string
          started_at?: string
          status?: string
          target_reference_cost_nanoton?: number
          target_reward_id?: string
          target_reward_type?: string
          threshold_reached_at?: string | null
          updated_at?: string
          winner_user_id?: string | null
          winning_spin_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "global_roulette_cycles_winner_user_id_fkey"
            columns: ["winner_user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "global_roulette_cycles_winning_spin_fkey"
            columns: ["winning_spin_id"]
            isOneToOne: false
            referencedRelation: "global_roulette_spins"
            referencedColumns: ["id"]
          },
        ]
      }
      global_roulette_reward_deliveries: {
        Row: {
          cycle_id: string
          delivered_at: string
          delivery_key: string
          id: string
          payload: Json
          reward_key: string | null
          reward_slot: string
          reward_type: string
          source: string
          spin_id: string | null
          user_id: string
        }
        Insert: {
          cycle_id: string
          delivered_at?: string
          delivery_key: string
          id?: string
          payload?: Json
          reward_key?: string | null
          reward_slot?: string
          reward_type: string
          source?: string
          spin_id?: string | null
          user_id: string
        }
        Update: {
          cycle_id?: string
          delivered_at?: string
          delivery_key?: string
          id?: string
          payload?: Json
          reward_key?: string | null
          reward_slot?: string
          reward_type?: string
          source?: string
          spin_id?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "global_roulette_reward_deliveries_cycle_id_fkey"
            columns: ["cycle_id"]
            isOneToOne: false
            referencedRelation: "global_roulette_cycles"
            referencedColumns: ["id"]
          },
        ]
      }
      global_roulette_settings: {
        Row: {
          celestial_threshold_nanoton: number
          created_at: string
          enabled: boolean
          id: boolean
          myth_shortage_behavior: string
          normal_weight_equipment: number
          normal_weight_myth: number
          paused: boolean
          payment_ttl_minutes: number
          spin_cost_nanoton: number
          updated_at: string
          weight_celestial: number
          weight_mythic: number
          weight_nft_hero: number
        }
        Insert: {
          celestial_threshold_nanoton?: number
          created_at?: string
          enabled?: boolean
          id?: boolean
          myth_shortage_behavior?: string
          normal_weight_equipment?: number
          normal_weight_myth?: number
          paused?: boolean
          payment_ttl_minutes?: number
          spin_cost_nanoton?: number
          updated_at?: string
          weight_celestial?: number
          weight_mythic?: number
          weight_nft_hero?: number
        }
        Update: {
          celestial_threshold_nanoton?: number
          created_at?: string
          enabled?: boolean
          id?: boolean
          myth_shortage_behavior?: string
          normal_weight_equipment?: number
          normal_weight_myth?: number
          paused?: boolean
          payment_ttl_minutes?: number
          spin_cost_nanoton?: number
          updated_at?: string
          weight_celestial?: number
          weight_mythic?: number
          weight_nft_hero?: number
        }
        Relationships: []
      }
      global_roulette_spins: {
        Row: {
          amount_nanoton: number
          created_at: string
          cycle_id: string | null
          expires_at: string | null
          id: string
          idempotency_key: string | null
          normal_reward_amount: number | null
          normal_reward_json: Json | null
          normal_reward_type: string | null
          paid_at: string | null
          payment_address: string | null
          payment_comment: string | null
          payment_source: string
          premium_reward_awarded: boolean
          premium_reward_id: string | null
          premium_reward_type: string | null
          received_nanoton: number | null
          result_json: Json | null
          settled_at: string | null
          status: string
          tx_hash: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          amount_nanoton: number
          created_at?: string
          cycle_id?: string | null
          expires_at?: string | null
          id?: string
          idempotency_key?: string | null
          normal_reward_amount?: number | null
          normal_reward_json?: Json | null
          normal_reward_type?: string | null
          paid_at?: string | null
          payment_address?: string | null
          payment_comment?: string | null
          payment_source: string
          premium_reward_awarded?: boolean
          premium_reward_id?: string | null
          premium_reward_type?: string | null
          received_nanoton?: number | null
          result_json?: Json | null
          settled_at?: string | null
          status?: string
          tx_hash?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          amount_nanoton?: number
          created_at?: string
          cycle_id?: string | null
          expires_at?: string | null
          id?: string
          idempotency_key?: string | null
          normal_reward_amount?: number | null
          normal_reward_json?: Json | null
          normal_reward_type?: string | null
          paid_at?: string | null
          payment_address?: string | null
          payment_comment?: string | null
          payment_source?: string
          premium_reward_awarded?: boolean
          premium_reward_id?: string | null
          premium_reward_type?: string | null
          received_nanoton?: number | null
          result_json?: Json | null
          settled_at?: string | null
          status?: string
          tx_hash?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "global_roulette_spins_cycle_id_fkey"
            columns: ["cycle_id"]
            isOneToOne: false
            referencedRelation: "global_roulette_cycles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "global_roulette_spins_user_id_fkey"
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
          base_def: number | null
          base_hp: number | null
          base_speed: number | null
          battle_image: string | null
          buffs: Json
          crit_rate: number | null
          description: string | null
          discount_percent: number
          drop_weight: number
          enabled: boolean
          featured: boolean
          fixed_base_stats: boolean
          fusion_pool_enabled: boolean
          growth_multiplier: number
          hero_class: string
          hero_key: string
          image: string
          in_shop: boolean
          is_nft_exclusive: boolean
          is_pass_exclusive: boolean
          max_level: number
          name: string
          nft_class_label: string | null
          nft_passive: Json
          per_player_limit: number | null
          power: number | null
          price_fc: number | null
          price_ton: number | null
          random_drop_eligible: boolean
          rarity: string
          recruit_eligible: boolean
          recruit_enabled: boolean
          reward_pool_eligible: boolean
          roulette_exclusive: boolean
          shop_eligible: boolean
          skill_power: number | null
          skills: Json
          sort_order: number
          start_level: number
          stock: number | null
          updated_at: string
          veteran_line: boolean
        }
        Insert: {
          available_from?: string | null
          available_until?: string | null
          base_atk?: number | null
          base_def?: number | null
          base_hp?: number | null
          base_speed?: number | null
          battle_image?: string | null
          buffs?: Json
          crit_rate?: number | null
          description?: string | null
          discount_percent?: number
          drop_weight?: number
          enabled?: boolean
          featured?: boolean
          fixed_base_stats?: boolean
          fusion_pool_enabled?: boolean
          growth_multiplier?: number
          hero_class?: string
          hero_key: string
          image: string
          in_shop?: boolean
          is_nft_exclusive?: boolean
          is_pass_exclusive?: boolean
          max_level?: number
          name: string
          nft_class_label?: string | null
          nft_passive?: Json
          per_player_limit?: number | null
          power?: number | null
          price_fc?: number | null
          price_ton?: number | null
          random_drop_eligible?: boolean
          rarity: string
          recruit_eligible?: boolean
          recruit_enabled?: boolean
          reward_pool_eligible?: boolean
          roulette_exclusive?: boolean
          shop_eligible?: boolean
          skill_power?: number | null
          skills?: Json
          sort_order?: number
          start_level?: number
          stock?: number | null
          updated_at?: string
          veteran_line?: boolean
        }
        Update: {
          available_from?: string | null
          available_until?: string | null
          base_atk?: number | null
          base_def?: number | null
          base_hp?: number | null
          base_speed?: number | null
          battle_image?: string | null
          buffs?: Json
          crit_rate?: number | null
          description?: string | null
          discount_percent?: number
          drop_weight?: number
          enabled?: boolean
          featured?: boolean
          fixed_base_stats?: boolean
          fusion_pool_enabled?: boolean
          growth_multiplier?: number
          hero_class?: string
          hero_key?: string
          image?: string
          in_shop?: boolean
          is_nft_exclusive?: boolean
          is_pass_exclusive?: boolean
          max_level?: number
          name?: string
          nft_class_label?: string | null
          nft_passive?: Json
          per_player_limit?: number | null
          power?: number | null
          price_fc?: number | null
          price_ton?: number | null
          random_drop_eligible?: boolean
          rarity?: string
          recruit_eligible?: boolean
          recruit_enabled?: boolean
          reward_pool_eligible?: boolean
          roulette_exclusive?: boolean
          shop_eligible?: boolean
          skill_power?: number | null
          skills?: Json
          sort_order?: number
          start_level?: number
          stock?: number | null
          updated_at?: string
          veteran_line?: boolean
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
          revive_attack_at: string | null
          revive_attack_used: boolean
          revive_protected: boolean
          revive_protected_until: string | null
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
          revive_attack_at?: string | null
          revive_attack_used?: boolean
          revive_protected?: boolean
          revive_protected_until?: string | null
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
          revive_attack_at?: string | null
          revive_attack_used?: boolean
          revive_protected?: boolean
          revive_protected_until?: string | null
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
          idempotency_key: string | null
          material_ids: string[]
          materials_consumed: number
          to_stars: number
          universal_fragments_spent: number
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
          idempotency_key?: string | null
          material_ids?: string[]
          materials_consumed: number
          to_stars: number
          universal_fragments_spent?: number
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
          idempotency_key?: string | null
          material_ids?: string[]
          materials_consumed?: number
          to_stars?: number
          universal_fragments_spent?: number
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
      hero_mining_claims: {
        Row: {
          amount_myth: number
          amount_ton: number
          created_at: string
          currency: string
          hero_count: number
          id: string
          rate_per_day: number
          source: string
          user_id: string
        }
        Insert: {
          amount_myth?: number
          amount_ton: number
          created_at?: string
          currency?: string
          hero_count?: number
          id?: string
          rate_per_day?: number
          source?: string
          user_id: string
        }
        Update: {
          amount_myth?: number
          amount_ton?: number
          created_at?: string
          currency?: string
          hero_count?: number
          id?: string
          rate_per_day?: number
          source?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "hero_mining_claims_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      hero_mining_investments: {
        Row: {
          amount_ton: number
          created_at: string
          id: string
          reference: string
          source_type: string
          user_id: string
        }
        Insert: {
          amount_ton: number
          created_at?: string
          id?: string
          reference: string
          source_type: string
          user_id: string
        }
        Update: {
          amount_ton?: number
          created_at?: string
          id?: string
          reference?: string
          source_type?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "hero_mining_investments_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      hero_mining_rates: {
        Row: {
          created_at: string
          rarity: string
          ton_per_day: number
          updated_at: string
        }
        Insert: {
          created_at?: string
          rarity: string
          ton_per_day?: number
          updated_at?: string
        }
        Update: {
          created_at?: string
          rarity?: string
          ton_per_day?: number
          updated_at?: string
        }
        Relationships: []
      }
      hero_mining_settings: {
        Row: {
          currency_changed_at: string
          enabled: boolean
          id: boolean
          legacy_pass20_access: boolean
          legacy_pass5_access: boolean
          min_claim_myth: number
          min_claim_ton: number
          mining_currency: string
          myth_per_day: number
          pass_exclusive_myth_per_day: number
          pass_gate_cutoff_at: string
          pass_gate_enabled: boolean
          pass_gate_price_ton: number
          premium_gate_enabled: boolean
          premium_rule_start_at: string
          required_deposit_ton: number
          required_pass_ton: number
          unlock_by_deposit_ton: boolean
          unlock_by_nft_hero: boolean
          unlock_by_nft_pet: boolean
          updated_at: string
        }
        Insert: {
          currency_changed_at?: string
          enabled?: boolean
          id?: boolean
          legacy_pass20_access?: boolean
          legacy_pass5_access?: boolean
          min_claim_myth?: number
          min_claim_ton?: number
          mining_currency?: string
          myth_per_day?: number
          pass_exclusive_myth_per_day?: number
          pass_gate_cutoff_at?: string
          pass_gate_enabled?: boolean
          pass_gate_price_ton?: number
          premium_gate_enabled?: boolean
          premium_rule_start_at?: string
          required_deposit_ton?: number
          required_pass_ton?: number
          unlock_by_deposit_ton?: boolean
          unlock_by_nft_hero?: boolean
          unlock_by_nft_pet?: boolean
          updated_at?: string
        }
        Update: {
          currency_changed_at?: string
          enabled?: boolean
          id?: boolean
          legacy_pass20_access?: boolean
          legacy_pass5_access?: boolean
          min_claim_myth?: number
          min_claim_ton?: number
          mining_currency?: string
          myth_per_day?: number
          pass_exclusive_myth_per_day?: number
          pass_gate_cutoff_at?: string
          pass_gate_enabled?: boolean
          pass_gate_price_ton?: number
          premium_gate_enabled?: boolean
          premium_rule_start_at?: string
          required_deposit_ton?: number
          required_pass_ton?: number
          unlock_by_deposit_ton?: boolean
          unlock_by_nft_hero?: boolean
          unlock_by_nft_pet?: boolean
          updated_at?: string
        }
        Relationships: []
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
      hero_rarity_mismatch_audit: {
        Row: {
          created_at: string
          flag: string
          hero_key: string
          id: string
          owned_rarity: string
          player_hero_id: string
          resolved_at: string | null
          template_rarity: string
          user_id: string | null
        }
        Insert: {
          created_at?: string
          flag?: string
          hero_key: string
          id?: string
          owned_rarity: string
          player_hero_id: string
          resolved_at?: string | null
          template_rarity: string
          user_id?: string | null
        }
        Update: {
          created_at?: string
          flag?: string
          hero_key?: string
          id?: string
          owned_rarity?: string
          player_hero_id?: string
          resolved_at?: string | null
          template_rarity?: string
          user_id?: string | null
        }
        Relationships: []
      }
      hero_stat_repair_audit: {
        Row: {
          created_at: string
          hero_id: string
          hero_key: string | null
          id: string
          new_base_atk: number | null
          new_base_hp: number | null
          old_base_atk: number | null
          old_base_hp: number | null
          rarity: string
          user_id: string
        }
        Insert: {
          created_at?: string
          hero_id: string
          hero_key?: string | null
          id?: string
          new_base_atk?: number | null
          new_base_hp?: number | null
          old_base_atk?: number | null
          old_base_hp?: number | null
          rarity: string
          user_id: string
        }
        Update: {
          created_at?: string
          hero_id?: string
          hero_key?: string | null
          id?: string
          new_base_atk?: number | null
          new_base_hp?: number | null
          old_base_atk?: number | null
          old_base_hp?: number | null
          rarity?: string
          user_id?: string
        }
        Relationships: []
      }
      hero_xp_events: {
        Row: {
          activity_type: string
          created_at: string
          daily_period: string
          id: string
          level_after: number
          level_before: number
          player_hero_id: string
          reference_id: string
          user_id: string
          xp_awarded: number
        }
        Insert: {
          activity_type: string
          created_at?: string
          daily_period?: string
          id?: string
          level_after?: number
          level_before?: number
          player_hero_id: string
          reference_id: string
          user_id: string
          xp_awarded?: number
        }
        Update: {
          activity_type?: string
          created_at?: string
          daily_period?: string
          id?: string
          level_after?: number
          level_before?: number
          player_hero_id?: string
          reference_id?: string
          user_id?: string
          xp_awarded?: number
        }
        Relationships: [
          {
            foreignKeyName: "hero_xp_events_player_hero_id_fkey"
            columns: ["player_hero_id"]
            isOneToOne: false
            referencedRelation: "player_heroes"
            referencedColumns: ["id"]
          },
        ]
      }
      key_chest_catalog: {
        Row: {
          chest_code: string
          created_at: string
          draws_max: number
          draws_min: number
          enabled: boolean
          guaranteed_premium: number
          image_url: string | null
          key_code: string
          name: string
          rarity: string
          sort_order: number
          subtitle: string
          updated_at: string
        }
        Insert: {
          chest_code: string
          created_at?: string
          draws_max?: number
          draws_min?: number
          enabled?: boolean
          guaranteed_premium?: number
          image_url?: string | null
          key_code: string
          name: string
          rarity?: string
          sort_order?: number
          subtitle?: string
          updated_at?: string
        }
        Update: {
          chest_code?: string
          created_at?: string
          draws_max?: number
          draws_min?: number
          enabled?: boolean
          guaranteed_premium?: number
          image_url?: string | null
          key_code?: string
          name?: string
          rarity?: string
          sort_order?: number
          subtitle?: string
          updated_at?: string
        }
        Relationships: []
      }
      key_chest_open_log: {
        Row: {
          chest_code: string
          created_at: string
          id: string
          key_code: string
          rewards: Json
          telegram_id: number | null
          user_id: string
        }
        Insert: {
          chest_code: string
          created_at?: string
          id?: string
          key_code: string
          rewards?: Json
          telegram_id?: number | null
          user_id: string
        }
        Update: {
          chest_code?: string
          created_at?: string
          id?: string
          key_code?: string
          rewards?: Json
          telegram_id?: number | null
          user_id?: string
        }
        Relationships: []
      }
      key_chest_reward_pool: {
        Row: {
          chest_code: string
          created_at: string
          enabled: boolean
          id: string
          is_premium: boolean
          label: string
          max_amount: number
          min_amount: number
          reward_code: string | null
          reward_type: string
          weight: number
        }
        Insert: {
          chest_code: string
          created_at?: string
          enabled?: boolean
          id?: string
          is_premium?: boolean
          label?: string
          max_amount?: number
          min_amount?: number
          reward_code?: string | null
          reward_type: string
          weight?: number
        }
        Update: {
          chest_code?: string
          created_at?: string
          enabled?: boolean
          id?: string
          is_premium?: boolean
          label?: string
          max_amount?: number
          min_amount?: number
          reward_code?: string | null
          reward_type?: string
          weight?: number
        }
        Relationships: [
          {
            foreignKeyName: "key_chest_reward_pool_chest_code_fkey"
            columns: ["chest_code"]
            isOneToOne: false
            referencedRelation: "key_chest_catalog"
            referencedColumns: ["chest_code"]
          },
        ]
      }
      market_item_ownership_history: {
        Row: {
          created_at: string
          currency: string | null
          from_user_id: string | null
          id: string
          item_code: string | null
          item_instance_id: string | null
          item_type: string
          listing_id: string | null
          price_fc: number | null
          price_ton: number | null
          to_user_id: string | null
          transaction_id: string | null
        }
        Insert: {
          created_at?: string
          currency?: string | null
          from_user_id?: string | null
          id?: string
          item_code?: string | null
          item_instance_id?: string | null
          item_type: string
          listing_id?: string | null
          price_fc?: number | null
          price_ton?: number | null
          to_user_id?: string | null
          transaction_id?: string | null
        }
        Update: {
          created_at?: string
          currency?: string | null
          from_user_id?: string | null
          id?: string
          item_code?: string | null
          item_instance_id?: string | null
          item_type?: string
          listing_id?: string | null
          price_fc?: number | null
          price_ton?: number | null
          to_user_id?: string | null
          transaction_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "market_item_ownership_history_from_user_id_fkey"
            columns: ["from_user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "market_item_ownership_history_to_user_id_fkey"
            columns: ["to_user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      market_listings: {
        Row: {
          buyer_user_id: string | null
          cancelled_at: string | null
          created_at: string
          currency: string
          fee_percent: number
          id: string
          item_code: string | null
          item_instance_id: string | null
          item_type: string
          price_fc: number | null
          price_ton: number | null
          quantity: number
          reserved_for: string | null
          reserved_until: string | null
          risk_level: string
          seller_user_id: string
          snapshot: Json
          sold_at: string | null
          status: string
          updated_at: string
        }
        Insert: {
          buyer_user_id?: string | null
          cancelled_at?: string | null
          created_at?: string
          currency?: string
          fee_percent?: number
          id?: string
          item_code?: string | null
          item_instance_id?: string | null
          item_type: string
          price_fc?: number | null
          price_ton?: number | null
          quantity?: number
          reserved_for?: string | null
          reserved_until?: string | null
          risk_level?: string
          seller_user_id: string
          snapshot?: Json
          sold_at?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          buyer_user_id?: string | null
          cancelled_at?: string | null
          created_at?: string
          currency?: string
          fee_percent?: number
          id?: string
          item_code?: string | null
          item_instance_id?: string | null
          item_type?: string
          price_fc?: number | null
          price_ton?: number | null
          quantity?: number
          reserved_for?: string | null
          reserved_until?: string | null
          risk_level?: string
          seller_user_id?: string
          snapshot?: Json
          sold_at?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "market_listings_buyer_user_id_fkey"
            columns: ["buyer_user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "market_listings_seller_user_id_fkey"
            columns: ["seller_user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      market_pair_stats: {
        Row: {
          buyer_user_id: string
          first_trade_at: string
          last_trade_at: string
          seller_user_id: string
          total_fc: number
          trades: number
        }
        Insert: {
          buyer_user_id: string
          first_trade_at?: string
          last_trade_at?: string
          seller_user_id: string
          total_fc?: number
          trades?: number
        }
        Update: {
          buyer_user_id?: string
          first_trade_at?: string
          last_trade_at?: string
          seller_user_id?: string
          total_fc?: number
          trades?: number
        }
        Relationships: [
          {
            foreignKeyName: "market_pair_stats_buyer_user_id_fkey"
            columns: ["buyer_user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "market_pair_stats_seller_user_id_fkey"
            columns: ["seller_user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      market_payment_intents: {
        Row: {
          amount_nano: number
          amount_ton: number
          buyer_user_id: string
          created_at: string
          expires_at: string
          id: string
          listing_id: string
          payment_address: string
          payment_comment: string
          seller_user_id: string
          status: string
          transaction_id: string | null
          tx_hash: string | null
          updated_at: string
          wallet_address: string | null
        }
        Insert: {
          amount_nano: number
          amount_ton: number
          buyer_user_id: string
          created_at?: string
          expires_at: string
          id?: string
          listing_id: string
          payment_address: string
          payment_comment: string
          seller_user_id: string
          status?: string
          transaction_id?: string | null
          tx_hash?: string | null
          updated_at?: string
          wallet_address?: string | null
        }
        Update: {
          amount_nano?: number
          amount_ton?: number
          buyer_user_id?: string
          created_at?: string
          expires_at?: string
          id?: string
          listing_id?: string
          payment_address?: string
          payment_comment?: string
          seller_user_id?: string
          status?: string
          transaction_id?: string | null
          tx_hash?: string | null
          updated_at?: string
          wallet_address?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "market_payment_intents_buyer_user_id_fkey"
            columns: ["buyer_user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "market_payment_intents_listing_id_fkey"
            columns: ["listing_id"]
            isOneToOne: false
            referencedRelation: "market_listings"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "market_payment_intents_seller_user_id_fkey"
            columns: ["seller_user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      market_price_ranges: {
        Row: {
          created_at: string
          id: string
          item_type: string
          max_fc: number
          max_ton: number | null
          min_fc: number
          min_ton: number | null
          rarity: string
          recommended_fc: number | null
          recommended_ton: number | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: string
          item_type: string
          max_fc: number
          max_ton?: number | null
          min_fc: number
          min_ton?: number | null
          rarity: string
          recommended_fc?: number | null
          recommended_ton?: number | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          item_type?: string
          max_fc?: number
          max_ton?: number | null
          min_fc?: number
          min_ton?: number | null
          rarity?: string
          recommended_fc?: number | null
          recommended_ton?: number | null
          updated_at?: string
        }
        Relationships: []
      }
      market_revenue_ledger: {
        Row: {
          buyer_user_id: string | null
          created_at: string
          currency: string
          entry_type: string
          fee_percent: number | null
          gross_amount_fc: number | null
          gross_amount_ton: number | null
          id: string
          item_code: string | null
          item_instance_id: string | null
          item_type: string | null
          listing_id: string | null
          market_fee_fc: number | null
          market_fee_ton: number | null
          payment_method: string
          seller_net_fc: number | null
          seller_net_ton: number | null
          seller_user_id: string | null
          transaction_id: string
          tx_hash: string | null
        }
        Insert: {
          buyer_user_id?: string | null
          created_at?: string
          currency: string
          entry_type: string
          fee_percent?: number | null
          gross_amount_fc?: number | null
          gross_amount_ton?: number | null
          id?: string
          item_code?: string | null
          item_instance_id?: string | null
          item_type?: string | null
          listing_id?: string | null
          market_fee_fc?: number | null
          market_fee_ton?: number | null
          payment_method: string
          seller_net_fc?: number | null
          seller_net_ton?: number | null
          seller_user_id?: string | null
          transaction_id: string
          tx_hash?: string | null
        }
        Update: {
          buyer_user_id?: string | null
          created_at?: string
          currency?: string
          entry_type?: string
          fee_percent?: number | null
          gross_amount_fc?: number | null
          gross_amount_ton?: number | null
          id?: string
          item_code?: string | null
          item_instance_id?: string | null
          item_type?: string | null
          listing_id?: string | null
          market_fee_fc?: number | null
          market_fee_ton?: number | null
          payment_method?: string
          seller_net_fc?: number | null
          seller_net_ton?: number | null
          seller_user_id?: string | null
          transaction_id?: string
          tx_hash?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "market_revenue_ledger_transaction_id_fkey"
            columns: ["transaction_id"]
            isOneToOne: false
            referencedRelation: "market_transactions"
            referencedColumns: ["id"]
          },
        ]
      }
      market_security_audit: {
        Row: {
          admin_id: number | null
          buyer_user_id: string | null
          created_at: string
          currency: string | null
          details: Json
          event: string
          fee_fc: number | null
          fee_ton: number | null
          id: string
          listing_id: string | null
          price_fc: number | null
          price_ton: number | null
          risk_flags: string[]
          risk_score: number
          seller_user_id: string | null
          transaction_id: string | null
        }
        Insert: {
          admin_id?: number | null
          buyer_user_id?: string | null
          created_at?: string
          currency?: string | null
          details?: Json
          event: string
          fee_fc?: number | null
          fee_ton?: number | null
          id?: string
          listing_id?: string | null
          price_fc?: number | null
          price_ton?: number | null
          risk_flags?: string[]
          risk_score?: number
          seller_user_id?: string | null
          transaction_id?: string | null
        }
        Update: {
          admin_id?: number | null
          buyer_user_id?: string | null
          created_at?: string
          currency?: string | null
          details?: Json
          event?: string
          fee_fc?: number | null
          fee_ton?: number | null
          id?: string
          listing_id?: string | null
          price_fc?: number | null
          price_ton?: number | null
          risk_flags?: string[]
          risk_score?: number
          seller_user_id?: string | null
          transaction_id?: string | null
        }
        Relationships: []
      }
      market_transactions: {
        Row: {
          admin_id: number | null
          admin_notes: string | null
          buyer_user_id: string
          created_at: string
          currency: string
          fee_fc: number | null
          fee_percent: number
          fee_ton: number | null
          id: string
          item_code: string | null
          item_instance_id: string | null
          item_type: string
          listing_id: string
          price_fc: number | null
          price_ton: number | null
          reversed_at: string | null
          risk_flags: string[]
          risk_score: number
          seller_received_fc: number | null
          seller_received_ton: number | null
          seller_user_id: string
          settle_at: string | null
          settled_at: string | null
          snapshot: Json
          spending_recorded: boolean
          status: string
          tx_hash: string | null
        }
        Insert: {
          admin_id?: number | null
          admin_notes?: string | null
          buyer_user_id: string
          created_at?: string
          currency?: string
          fee_fc?: number | null
          fee_percent: number
          fee_ton?: number | null
          id?: string
          item_code?: string | null
          item_instance_id?: string | null
          item_type: string
          listing_id: string
          price_fc?: number | null
          price_ton?: number | null
          reversed_at?: string | null
          risk_flags?: string[]
          risk_score?: number
          seller_received_fc?: number | null
          seller_received_ton?: number | null
          seller_user_id: string
          settle_at?: string | null
          settled_at?: string | null
          snapshot?: Json
          spending_recorded?: boolean
          status?: string
          tx_hash?: string | null
        }
        Update: {
          admin_id?: number | null
          admin_notes?: string | null
          buyer_user_id?: string
          created_at?: string
          currency?: string
          fee_fc?: number | null
          fee_percent?: number
          fee_ton?: number | null
          id?: string
          item_code?: string | null
          item_instance_id?: string | null
          item_type?: string
          listing_id?: string
          price_fc?: number | null
          price_ton?: number | null
          reversed_at?: string | null
          risk_flags?: string[]
          risk_score?: number
          seller_received_fc?: number | null
          seller_received_ton?: number | null
          seller_user_id?: string
          settle_at?: string | null
          settled_at?: string | null
          snapshot?: Json
          spending_recorded?: boolean
          status?: string
          tx_hash?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "market_transactions_buyer_user_id_fkey"
            columns: ["buyer_user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "market_transactions_listing_id_fkey"
            columns: ["listing_id"]
            isOneToOne: false
            referencedRelation: "market_listings"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "market_transactions_seller_user_id_fkey"
            columns: ["seller_user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      market_treasury: {
        Row: {
          gross_volume_fc: number
          gross_volume_ton: number
          id: boolean
          market_fee_revenue_fc: number
          market_fee_revenue_ton: number
          seller_payout_fc: number
          seller_payout_ton: number
          updated_at: string
        }
        Insert: {
          gross_volume_fc?: number
          gross_volume_ton?: number
          id?: boolean
          market_fee_revenue_fc?: number
          market_fee_revenue_ton?: number
          seller_payout_fc?: number
          seller_payout_ton?: number
          updated_at?: string
        }
        Update: {
          gross_volume_fc?: number
          gross_volume_ton?: number
          id?: boolean
          market_fee_revenue_fc?: number
          market_fee_revenue_ton?: number
          seller_payout_fc?: number
          seller_payout_ton?: number
          updated_at?: string
        }
        Relationships: []
      }
      marketing_pool_expenses: {
        Row: {
          amount_ton: number
          category: string
          created_at: string
          created_by: number | null
          description: string
          id: string
          note: string | null
          spent_at: string
          updated_at: string
        }
        Insert: {
          amount_ton: number
          category?: string
          created_at?: string
          created_by?: number | null
          description: string
          id?: string
          note?: string | null
          spent_at?: string
          updated_at?: string
        }
        Update: {
          amount_ton?: number
          category?: string
          created_at?: string
          created_by?: number | null
          description?: string
          id?: string
          note?: string | null
          spent_at?: string
          updated_at?: string
        }
        Relationships: []
      }
      myth_balances: {
        Row: {
          amount: number
          updated_at: string
          user_id: string
        }
        Insert: {
          amount?: number
          updated_at?: string
          user_id: string
        }
        Update: {
          amount?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "myth_balances_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      myth_burn_history: {
        Row: {
          amount: number
          burn_kind: string
          created_at: string
          created_by: number | null
          id: string
          reason: string | null
          source: string | null
          source_id: string | null
          supply_after: number
          supply_before: number
          user_id: string | null
        }
        Insert: {
          amount: number
          burn_kind?: string
          created_at?: string
          created_by?: number | null
          id?: string
          reason?: string | null
          source?: string | null
          source_id?: string | null
          supply_after: number
          supply_before: number
          user_id?: string | null
        }
        Update: {
          amount?: number
          burn_kind?: string
          created_at?: string
          created_by?: number | null
          id?: string
          reason?: string | null
          source?: string | null
          source_id?: string | null
          supply_after?: number
          supply_before?: number
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "myth_burn_history_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      myth_ledger: {
        Row: {
          admin_telegram_id: number | null
          amount: number
          created_at: string
          direction: string
          id: string
          reason: string
          user_id: string | null
        }
        Insert: {
          admin_telegram_id?: number | null
          amount: number
          created_at?: string
          direction: string
          id?: string
          reason?: string
          user_id?: string | null
        }
        Update: {
          admin_telegram_id?: number | null
          amount?: number
          created_at?: string
          direction?: string
          id?: string
          reason?: string
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "myth_ledger_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      myth_mining_pool: {
        Row: {
          allocated_myth: number
          distributed_myth: number
          id: boolean
          updated_at: string
        }
        Insert: {
          allocated_myth?: number
          distributed_myth?: number
          id?: boolean
          updated_at?: string
        }
        Update: {
          allocated_myth?: number
          distributed_myth?: number
          id?: boolean
          updated_at?: string
        }
        Relationships: []
      }
      myth_payment_intents: {
        Row: {
          amount_nano: number
          amount_ton: number
          created_at: string
          expires_at: string
          id: string
          idempotency_key: string | null
          myth_amount: number
          payment_address: string
          payment_comment: string
          price_snapshot: number
          status: string
          transaction_id: string | null
          tx_hash: string | null
          updated_at: string
          user_id: string
          wallet_address: string | null
        }
        Insert: {
          amount_nano: number
          amount_ton: number
          created_at?: string
          expires_at: string
          id?: string
          idempotency_key?: string | null
          myth_amount: number
          payment_address: string
          payment_comment: string
          price_snapshot: number
          status?: string
          transaction_id?: string | null
          tx_hash?: string | null
          updated_at?: string
          user_id: string
          wallet_address?: string | null
        }
        Update: {
          amount_nano?: number
          amount_ton?: number
          created_at?: string
          expires_at?: string
          id?: string
          idempotency_key?: string | null
          myth_amount?: number
          payment_address?: string
          payment_comment?: string
          price_snapshot?: number
          status?: string
          transaction_id?: string | null
          tx_hash?: string | null
          updated_at?: string
          user_id?: string
          wallet_address?: string | null
        }
        Relationships: []
      }
      myth_sale_config: {
        Row: {
          id: boolean
          intent_minutes: number
          min_purchase_myth: number
          myth_per_ton: number
          sale_allocation: number
          sale_status: string
          updated_at: string
        }
        Insert: {
          id?: boolean
          intent_minutes?: number
          min_purchase_myth?: number
          myth_per_ton?: number
          sale_allocation?: number
          sale_status?: string
          updated_at?: string
        }
        Update: {
          id?: boolean
          intent_minutes?: number
          min_purchase_myth?: number
          myth_per_ton?: number
          sale_allocation?: number
          sale_status?: string
          updated_at?: string
        }
        Relationships: []
      }
      myth_sale_milestone_claims: {
        Row: {
          created_at: string
          id: string
          milestone_amount: number
          myth_total: number
          rewards: Json
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          milestone_amount: number
          myth_total?: number
          rewards?: Json
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          milestone_amount?: number
          myth_total?: number
          rewards?: Json
          user_id?: string
        }
        Relationships: []
      }
      myth_sale_public_stats: {
        Row: {
          available: number
          burned: number
          id: boolean
          myth_per_ton: number
          reserved: number
          sale_status: string
          sold: number
          ton_raised: number
          updated_at: string
        }
        Insert: {
          available?: number
          burned?: number
          id?: boolean
          myth_per_ton?: number
          reserved?: number
          sale_status?: string
          sold?: number
          ton_raised?: number
          updated_at?: string
        }
        Update: {
          available?: number
          burned?: number
          id?: boolean
          myth_per_ton?: number
          reserved?: number
          sale_status?: string
          sold?: number
          ton_raised?: number
          updated_at?: string
        }
        Relationships: []
      }
      myth_sale_transactions: {
        Row: {
          amount_nano: number
          amount_ton: number
          created_at: string
          id: string
          idempotency_key: string | null
          intent_id: string | null
          myth_amount: number
          payment_method: string
          price_snapshot: number
          status: string
          tx_hash: string | null
          user_id: string
        }
        Insert: {
          amount_nano: number
          amount_ton: number
          created_at?: string
          id?: string
          idempotency_key?: string | null
          intent_id?: string | null
          myth_amount: number
          payment_method: string
          price_snapshot: number
          status?: string
          tx_hash?: string | null
          user_id: string
        }
        Update: {
          amount_nano?: number
          amount_ton?: number
          created_at?: string
          id?: string
          idempotency_key?: string | null
          intent_id?: string | null
          myth_amount?: number
          payment_method?: string
          price_snapshot?: number
          status?: string
          tx_hash?: string | null
          user_id?: string
        }
        Relationships: []
      }
      myth_staking_idempotency: {
        Row: {
          created_at: string
          key: string
          result: Json | null
          user_id: string | null
        }
        Insert: {
          created_at?: string
          key: string
          result?: Json | null
          user_id?: string | null
        }
        Update: {
          created_at?: string
          key?: string
          result?: Json | null
          user_id?: string | null
        }
        Relationships: []
      }
      myth_staking_ledger: {
        Row: {
          admin_telegram_id: number | null
          amount: number
          created_at: string
          entry_type: string
          id: string
          note: string | null
          position_id: string | null
          user_id: string | null
        }
        Insert: {
          admin_telegram_id?: number | null
          amount: number
          created_at?: string
          entry_type: string
          id?: string
          note?: string | null
          position_id?: string | null
          user_id?: string | null
        }
        Update: {
          admin_telegram_id?: number | null
          amount?: number
          created_at?: string
          entry_type?: string
          id?: string
          note?: string | null
          position_id?: string | null
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "myth_staking_ledger_position_id_fkey"
            columns: ["position_id"]
            isOneToOne: false
            referencedRelation: "myth_staking_positions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "myth_staking_ledger_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      myth_staking_plans: {
        Row: {
          active: boolean
          apr_percent: number
          code: string
          label: string
          lock_days: number
          sort_order: number
          updated_at: string
        }
        Insert: {
          active?: boolean
          apr_percent?: number
          code: string
          label: string
          lock_days?: number
          sort_order?: number
          updated_at?: string
        }
        Update: {
          active?: boolean
          apr_percent?: number
          code?: string
          label?: string
          lock_days?: number
          sort_order?: number
          updated_at?: string
        }
        Relationships: []
      }
      myth_staking_positions: {
        Row: {
          accrued_myth: number
          amount: number
          apr_percent: number
          claimed_myth: number
          closed_at: string | null
          id: string
          last_accrual_at: string
          lock_days: number
          plan_code: string
          staked_at: string
          status: string
          unlock_at: string | null
          user_id: string
        }
        Insert: {
          accrued_myth?: number
          amount: number
          apr_percent: number
          claimed_myth?: number
          closed_at?: string | null
          id?: string
          last_accrual_at?: string
          lock_days?: number
          plan_code: string
          staked_at?: string
          status?: string
          unlock_at?: string | null
          user_id: string
        }
        Update: {
          accrued_myth?: number
          amount?: number
          apr_percent?: number
          claimed_myth?: number
          closed_at?: string | null
          id?: string
          last_accrual_at?: string
          lock_days?: number
          plan_code?: string
          staked_at?: string
          status?: string
          unlock_at?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "myth_staking_positions_plan_code_fkey"
            columns: ["plan_code"]
            isOneToOne: false
            referencedRelation: "myth_staking_plans"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "myth_staking_positions_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      myth_staking_settings: {
        Row: {
          claims_enabled: boolean
          id: boolean
          max_stake: number
          min_stake: number
          new_stakes_paused: boolean
          reward_pool_distributed: number
          reward_pool_total: number
          staking_enabled: boolean
          updated_at: string
        }
        Insert: {
          claims_enabled?: boolean
          id?: boolean
          max_stake?: number
          min_stake?: number
          new_stakes_paused?: boolean
          reward_pool_distributed?: number
          reward_pool_total?: number
          staking_enabled?: boolean
          updated_at?: string
        }
        Update: {
          claims_enabled?: boolean
          id?: boolean
          max_stake?: number
          min_stake?: number
          new_stakes_paused?: boolean
          reward_pool_distributed?: number
          reward_pool_total?: number
          staking_enabled?: boolean
          updated_at?: string
        }
        Relationships: []
      }
      myth_supply_ledger: {
        Row: {
          admin_telegram_id: number | null
          amount: number
          created_at: string
          entry_type: string
          id: string
          note: string | null
          reference_id: string | null
          user_id: string | null
        }
        Insert: {
          admin_telegram_id?: number | null
          amount: number
          created_at?: string
          entry_type: string
          id?: string
          note?: string | null
          reference_id?: string | null
          user_id?: string | null
        }
        Update: {
          admin_telegram_id?: number | null
          amount?: number
          created_at?: string
          entry_type?: string
          id?: string
          note?: string | null
          reference_id?: string | null
          user_id?: string | null
        }
        Relationships: []
      }
      myth_token_settings: {
        Row: {
          id: boolean
          status_label: string
          token_name: string
          token_symbol: string
          total_supply: number
          updated_at: string
          visible_in_game: boolean
        }
        Insert: {
          id?: boolean
          status_label?: string
          token_name?: string
          token_symbol?: string
          total_supply?: number
          updated_at?: string
          visible_in_game?: boolean
        }
        Update: {
          id?: boolean
          status_label?: string
          token_name?: string
          token_symbol?: string
          total_supply?: number
          updated_at?: string
          visible_in_game?: boolean
        }
        Relationships: []
      }
      myth_utility_burns: {
        Row: {
          amount_base_units: number
          amount_myth: number
          balance_after: number
          balance_before: number
          confirmed_at: string | null
          created_at: string
          feature_code: string
          game_burn_status: string
          id: string
          idempotency_key: string | null
          meta: Json
          onchain_burn_status: string
          onchain_tx_hash: string | null
          reference_myth_per_ton: number
          source_id: string | null
          user_id: string
          utility_discount_percent: number
        }
        Insert: {
          amount_base_units?: number
          amount_myth: number
          balance_after: number
          balance_before: number
          confirmed_at?: string | null
          created_at?: string
          feature_code: string
          game_burn_status?: string
          id?: string
          idempotency_key?: string | null
          meta?: Json
          onchain_burn_status?: string
          onchain_tx_hash?: string | null
          reference_myth_per_ton: number
          source_id?: string | null
          user_id: string
          utility_discount_percent: number
        }
        Update: {
          amount_base_units?: number
          amount_myth?: number
          balance_after?: number
          balance_before?: number
          confirmed_at?: string | null
          created_at?: string
          feature_code?: string
          game_burn_status?: string
          id?: string
          idempotency_key?: string | null
          meta?: Json
          onchain_burn_status?: string
          onchain_tx_hash?: string | null
          reference_myth_per_ton?: number
          source_id?: string | null
          user_id?: string
          utility_discount_percent?: number
        }
        Relationships: [
          {
            foreignKeyName: "myth_utility_burns_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      myth_utility_features: {
        Row: {
          custom_myth: number | null
          enabled: boolean
          feature_code: string
          label: string
          pricing_mode: string
          updated_at: string
        }
        Insert: {
          custom_myth?: number | null
          enabled?: boolean
          feature_code: string
          label: string
          pricing_mode?: string
          updated_at?: string
        }
        Update: {
          custom_myth?: number | null
          enabled?: boolean
          feature_code?: string
          label?: string
          pricing_mode?: string
          updated_at?: string
        }
        Relationships: []
      }
      myth_utility_settings: {
        Row: {
          discount_percent: number
          enabled: boolean
          fc_per_ton: number
          id: boolean
          jetton_master_address: string | null
          myth_per_ton: number
          onchain_burn_enabled: boolean
          updated_at: string
        }
        Insert: {
          discount_percent?: number
          enabled?: boolean
          fc_per_ton?: number
          id?: boolean
          jetton_master_address?: string | null
          myth_per_ton?: number
          onchain_burn_enabled?: boolean
          updated_at?: string
        }
        Update: {
          discount_percent?: number
          enabled?: boolean
          fc_per_ton?: number
          id?: boolean
          jetton_master_address?: string | null
          myth_per_ton?: number
          onchain_burn_enabled?: boolean
          updated_at?: string
        }
        Relationships: []
      }
      mythic_power_pack_config: {
        Row: {
          enabled: boolean
          ends_at: string | null
          equipment_chest_code: string
          equipment_chests: number
          eternity_keys: number
          first_bonus_key_code: string
          first_bonus_myth: number
          hero_xp: number
          id: boolean
          myth_reward: number
          mythic_egg_slug: string
          mythic_eggs: number
          package_version: string
          pet_food_code: string
          pet_food_quantity: number
          popup_enabled: boolean
          popup_frequency: string
          popup_priority: number
          price_ton: number
          pvp_tickets: number
          reward_configuration_version: number
          sales_paused: boolean
          start_at: string | null
          universal_fragments: number
          updated_at: string
          void_chests: number
          void_keys: number
        }
        Insert: {
          enabled?: boolean
          ends_at?: string | null
          equipment_chest_code?: string
          equipment_chests?: number
          eternity_keys?: number
          first_bonus_key_code?: string
          first_bonus_myth?: number
          hero_xp?: number
          id?: boolean
          myth_reward?: number
          mythic_egg_slug?: string
          mythic_eggs?: number
          package_version?: string
          pet_food_code?: string
          pet_food_quantity?: number
          popup_enabled?: boolean
          popup_frequency?: string
          popup_priority?: number
          price_ton?: number
          pvp_tickets?: number
          reward_configuration_version?: number
          sales_paused?: boolean
          start_at?: string | null
          universal_fragments?: number
          updated_at?: string
          void_chests?: number
          void_keys?: number
        }
        Update: {
          enabled?: boolean
          ends_at?: string | null
          equipment_chest_code?: string
          equipment_chests?: number
          eternity_keys?: number
          first_bonus_key_code?: string
          first_bonus_myth?: number
          hero_xp?: number
          id?: boolean
          myth_reward?: number
          mythic_egg_slug?: string
          mythic_eggs?: number
          package_version?: string
          pet_food_code?: string
          pet_food_quantity?: number
          popup_enabled?: boolean
          popup_frequency?: string
          popup_priority?: number
          price_ton?: number
          pvp_tickets?: number
          reward_configuration_version?: number
          sales_paused?: boolean
          start_at?: string | null
          universal_fragments?: number
          updated_at?: string
          void_chests?: number
          void_keys?: number
        }
        Relationships: []
      }
      mythic_power_pack_ledger: {
        Row: {
          created_at: string
          id: string
          kind: string
          myth_amount: number | null
          note: string | null
          purchase_id: string | null
          ton_amount: number | null
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          kind: string
          myth_amount?: number | null
          note?: string | null
          purchase_id?: string | null
          ton_amount?: number | null
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          kind?: string
          myth_amount?: number | null
          note?: string | null
          purchase_id?: string | null
          ton_amount?: number | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "mythic_power_pack_ledger_purchase_id_fkey"
            columns: ["purchase_id"]
            isOneToOne: false
            referencedRelation: "mythic_power_pack_purchases"
            referencedColumns: ["id"]
          },
        ]
      }
      mythic_power_pack_purchases: {
        Row: {
          bonus_myth_snapshot: number
          confirmed_at: string | null
          created_at: string
          delivered_at: string | null
          delivery: Json | null
          expected_nanoton: string
          expires_at: string
          first_purchase_bonus: boolean
          fulfillment_error: string | null
          id: string
          idempotency_key: string | null
          myth_snapshot: number
          package_version: string
          payment_address: string | null
          payment_comment: string | null
          payment_method: string
          price_ton: number
          reward_configuration_version: number
          rewards_snapshot: Json
          status: string
          telegram_id: number | null
          tx_hash: string | null
          user_id: string
        }
        Insert: {
          bonus_myth_snapshot?: number
          confirmed_at?: string | null
          created_at?: string
          delivered_at?: string | null
          delivery?: Json | null
          expected_nanoton: string
          expires_at?: string
          first_purchase_bonus?: boolean
          fulfillment_error?: string | null
          id?: string
          idempotency_key?: string | null
          myth_snapshot?: number
          package_version: string
          payment_address?: string | null
          payment_comment?: string | null
          payment_method?: string
          price_ton: number
          reward_configuration_version?: number
          rewards_snapshot?: Json
          status?: string
          telegram_id?: number | null
          tx_hash?: string | null
          user_id: string
        }
        Update: {
          bonus_myth_snapshot?: number
          confirmed_at?: string | null
          created_at?: string
          delivered_at?: string | null
          delivery?: Json | null
          expected_nanoton?: string
          expires_at?: string
          first_purchase_bonus?: boolean
          fulfillment_error?: string | null
          id?: string
          idempotency_key?: string | null
          myth_snapshot?: number
          package_version?: string
          payment_address?: string | null
          payment_comment?: string | null
          payment_method?: string
          price_ton?: number
          reward_configuration_version?: number
          rewards_snapshot?: Json
          status?: string
          telegram_id?: number | null
          tx_hash?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "mythic_power_pack_purchases_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      name_mission_claims: {
        Row: {
          created_at: string
          hashtag: string
          id: string
          mission_code: string
          reward_amount: number
          reward_type: string
          telegram_auth_date: number | null
          telegram_id: number
          user_id: string
          verified_at: string
          verified_display_name: string
          verified_source: string
        }
        Insert: {
          created_at?: string
          hashtag: string
          id?: string
          mission_code?: string
          reward_amount?: number
          reward_type?: string
          telegram_auth_date?: number | null
          telegram_id: number
          user_id: string
          verified_at?: string
          verified_display_name: string
          verified_source?: string
        }
        Update: {
          created_at?: string
          hashtag?: string
          id?: string
          mission_code?: string
          reward_amount?: number
          reward_type?: string
          telegram_auth_date?: number | null
          telegram_id?: number
          user_id?: string
          verified_at?: string
          verified_display_name?: string
          verified_source?: string
        }
        Relationships: [
          {
            foreignKeyName: "name_mission_claims_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      nft_breeding_history: {
        Row: {
          breed_number_a: number | null
          breed_number_b: number | null
          breeding_id: string | null
          cost_a: number
          cost_b: number
          created_at: string
          egg_a_sub_nft_id: string | null
          egg_b_sub_nft_id: string | null
          id: string
          owner_a_user_id: string | null
          owner_b_user_id: string | null
          parent_a_nft_id: string | null
          parent_b_nft_id: string | null
        }
        Insert: {
          breed_number_a?: number | null
          breed_number_b?: number | null
          breeding_id?: string | null
          cost_a?: number
          cost_b?: number
          created_at?: string
          egg_a_sub_nft_id?: string | null
          egg_b_sub_nft_id?: string | null
          id?: string
          owner_a_user_id?: string | null
          owner_b_user_id?: string | null
          parent_a_nft_id?: string | null
          parent_b_nft_id?: string | null
        }
        Update: {
          breed_number_a?: number | null
          breed_number_b?: number | null
          breeding_id?: string | null
          cost_a?: number
          cost_b?: number
          created_at?: string
          egg_a_sub_nft_id?: string | null
          egg_b_sub_nft_id?: string | null
          id?: string
          owner_a_user_id?: string | null
          owner_b_user_id?: string | null
          parent_a_nft_id?: string | null
          parent_b_nft_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "nft_breeding_history_breeding_id_fkey"
            columns: ["breeding_id"]
            isOneToOne: false
            referencedRelation: "nft_breeding_requests"
            referencedColumns: ["id"]
          },
        ]
      }
      nft_breeding_requests: {
        Row: {
          breed_number_a: number
          breed_number_b: number
          completed_at: string | null
          cost_a: number
          cost_b: number
          created_at: string
          expires_at: string
          id: string
          initiator_user_id: string
          nft_a_id: string
          nft_b_id: string
          paid_a: boolean
          paid_b: boolean
          partner_user_id: string
          self_breed: boolean
          status: string
          updated_at: string
        }
        Insert: {
          breed_number_a: number
          breed_number_b: number
          completed_at?: string | null
          cost_a: number
          cost_b: number
          created_at?: string
          expires_at: string
          id?: string
          initiator_user_id: string
          nft_a_id: string
          nft_b_id: string
          paid_a?: boolean
          paid_b?: boolean
          partner_user_id: string
          self_breed?: boolean
          status?: string
          updated_at?: string
        }
        Update: {
          breed_number_a?: number
          breed_number_b?: number
          completed_at?: string | null
          cost_a?: number
          cost_b?: number
          created_at?: string
          expires_at?: string
          id?: string
          initiator_user_id?: string
          nft_a_id?: string
          nft_b_id?: string
          paid_a?: boolean
          paid_b?: boolean
          partner_user_id?: string
          self_breed?: boolean
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "nft_breeding_requests_initiator_user_id_fkey"
            columns: ["initiator_user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "nft_breeding_requests_nft_a_id_fkey"
            columns: ["nft_a_id"]
            isOneToOne: false
            referencedRelation: "nft_pets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "nft_breeding_requests_nft_b_id_fkey"
            columns: ["nft_b_id"]
            isOneToOne: false
            referencedRelation: "nft_pets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "nft_breeding_requests_partner_user_id_fkey"
            columns: ["partner_user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      nft_breeding_settings: {
        Row: {
          adult_hours: number
          baby_hours: number
          cooldown_days: number
          cost_breed_1: number
          cost_breed_2: number
          cost_breed_3: number
          enabled: boolean
          id: boolean
          juvenile_hours: number
          max_breeds: number
          min_claim_ton: number
          request_ttl_minutes: number
          sub_breeding_enabled: boolean
          sub_rate_per_ton: number
          updated_at: string
        }
        Insert: {
          adult_hours?: number
          baby_hours?: number
          cooldown_days?: number
          cost_breed_1?: number
          cost_breed_2?: number
          cost_breed_3?: number
          enabled?: boolean
          id?: boolean
          juvenile_hours?: number
          max_breeds?: number
          min_claim_ton?: number
          request_ttl_minutes?: number
          sub_breeding_enabled?: boolean
          sub_rate_per_ton?: number
          updated_at?: string
        }
        Update: {
          adult_hours?: number
          baby_hours?: number
          cooldown_days?: number
          cost_breed_1?: number
          cost_breed_2?: number
          cost_breed_3?: number
          enabled?: boolean
          id?: boolean
          juvenile_hours?: number
          max_breeds?: number
          min_claim_ton?: number
          request_ttl_minutes?: number
          sub_breeding_enabled?: boolean
          sub_rate_per_ton?: number
          updated_at?: string
        }
        Relationships: []
      }
      nft_equipment: {
        Row: {
          assigned_at: string | null
          created_at: string
          created_by_admin: number | null
          for_sale: boolean
          id: string
          metadata: Json
          mining_daily_myth: number
          mining_last_at: string | null
          nft_serial: number
          owner_user_id: string | null
          player_equipment_id: string | null
          price_ton: number
          status: string
          template_id: string
          unique_instance_id: string
          updated_at: string
        }
        Insert: {
          assigned_at?: string | null
          created_at?: string
          created_by_admin?: number | null
          for_sale?: boolean
          id?: string
          metadata?: Json
          mining_daily_myth?: number
          mining_last_at?: string | null
          nft_serial: number
          owner_user_id?: string | null
          player_equipment_id?: string | null
          price_ton?: number
          status?: string
          template_id: string
          unique_instance_id: string
          updated_at?: string
        }
        Update: {
          assigned_at?: string | null
          created_at?: string
          created_by_admin?: number | null
          for_sale?: boolean
          id?: string
          metadata?: Json
          mining_daily_myth?: number
          mining_last_at?: string | null
          nft_serial?: number
          owner_user_id?: string | null
          player_equipment_id?: string | null
          price_ton?: number
          status?: string
          template_id?: string
          unique_instance_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "nft_equipment_owner_user_id_fkey"
            columns: ["owner_user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "nft_equipment_player_equipment_id_fkey"
            columns: ["player_equipment_id"]
            isOneToOne: false
            referencedRelation: "player_equipment"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "nft_equipment_template_id_fkey"
            columns: ["template_id"]
            isOneToOne: false
            referencedRelation: "equipment_templates"
            referencedColumns: ["id"]
          },
        ]
      }
      nft_equipment_orders: {
        Row: {
          amount_nano: string
          confirmed_at: string | null
          created_at: string
          delivered_at: string | null
          expires_at: string
          id: string
          idempotency_key: string
          nft_equipment_id: string
          paid_at: string | null
          payment_address: string
          payment_comment: string
          price_ton: number
          status: string
          tx_hash: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          amount_nano: string
          confirmed_at?: string | null
          created_at?: string
          delivered_at?: string | null
          expires_at?: string
          id?: string
          idempotency_key: string
          nft_equipment_id: string
          paid_at?: string | null
          payment_address: string
          payment_comment: string
          price_ton: number
          status?: string
          tx_hash?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          amount_nano?: string
          confirmed_at?: string | null
          created_at?: string
          delivered_at?: string | null
          expires_at?: string
          id?: string
          idempotency_key?: string
          nft_equipment_id?: string
          paid_at?: string | null
          payment_address?: string
          payment_comment?: string
          price_ton?: number
          status?: string
          tx_hash?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "nft_equipment_orders_nft_equipment_id_fkey"
            columns: ["nft_equipment_id"]
            isOneToOne: false
            referencedRelation: "nft_equipment"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "nft_equipment_orders_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      nft_hero_history: {
        Row: {
          action: string
          admin_telegram_id: number | null
          created_at: string
          from_user_id: string | null
          id: string
          metadata: Json
          nft_hero_id: string
          reason: string | null
          to_user_id: string | null
        }
        Insert: {
          action: string
          admin_telegram_id?: number | null
          created_at?: string
          from_user_id?: string | null
          id?: string
          metadata?: Json
          nft_hero_id: string
          reason?: string | null
          to_user_id?: string | null
        }
        Update: {
          action?: string
          admin_telegram_id?: number | null
          created_at?: string
          from_user_id?: string | null
          id?: string
          metadata?: Json
          nft_hero_id?: string
          reason?: string | null
          to_user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "nft_hero_history_nft_hero_id_fkey"
            columns: ["nft_hero_id"]
            isOneToOne: false
            referencedRelation: "nft_heroes"
            referencedColumns: ["id"]
          },
        ]
      }
      nft_hero_orders: {
        Row: {
          amount_nano: string
          confirmed_at: string | null
          created_at: string
          delivered_at: string | null
          expires_at: string
          id: string
          idempotency_key: string
          nft_hero_id: string
          paid_at: string | null
          payment_address: string
          payment_comment: string
          price_ton: number
          status: string
          tx_hash: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          amount_nano: string
          confirmed_at?: string | null
          created_at?: string
          delivered_at?: string | null
          expires_at?: string
          id?: string
          idempotency_key: string
          nft_hero_id: string
          paid_at?: string | null
          payment_address: string
          payment_comment: string
          price_ton: number
          status?: string
          tx_hash?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          amount_nano?: string
          confirmed_at?: string | null
          created_at?: string
          delivered_at?: string | null
          expires_at?: string
          id?: string
          idempotency_key?: string
          nft_hero_id?: string
          paid_at?: string | null
          payment_address?: string
          payment_comment?: string
          price_ton?: number
          status?: string
          tx_hash?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "nft_hero_orders_nft_hero_id_fkey"
            columns: ["nft_hero_id"]
            isOneToOne: false
            referencedRelation: "nft_heroes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "nft_hero_orders_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      nft_heroes: {
        Row: {
          assigned_at: string | null
          created_at: string
          created_by_admin: number | null
          for_sale: boolean
          generation: number
          hero_template_id: string
          id: string
          level: number
          metadata: Json
          mining_daily_myth: number
          mining_daily_ton: number
          mining_dual: boolean
          minted: boolean
          nft_serial: number
          owner_user_id: string | null
          player_hero_id: string | null
          price_ton: number | null
          revoked_at: string | null
          rotation_retired_at: string | null
          stars: number
          status: string
          tier_ton: number | null
          unique_instance_id: string
          updated_at: string
          xp: number
          yield_locked_at: string | null
        }
        Insert: {
          assigned_at?: string | null
          created_at?: string
          created_by_admin?: number | null
          for_sale?: boolean
          generation?: number
          hero_template_id: string
          id?: string
          level?: number
          metadata?: Json
          mining_daily_myth?: number
          mining_daily_ton?: number
          mining_dual?: boolean
          minted?: boolean
          nft_serial: number
          owner_user_id?: string | null
          player_hero_id?: string | null
          price_ton?: number | null
          revoked_at?: string | null
          rotation_retired_at?: string | null
          stars?: number
          status?: string
          tier_ton?: number | null
          unique_instance_id: string
          updated_at?: string
          xp?: number
          yield_locked_at?: string | null
        }
        Update: {
          assigned_at?: string | null
          created_at?: string
          created_by_admin?: number | null
          for_sale?: boolean
          generation?: number
          hero_template_id?: string
          id?: string
          level?: number
          metadata?: Json
          mining_daily_myth?: number
          mining_daily_ton?: number
          mining_dual?: boolean
          minted?: boolean
          nft_serial?: number
          owner_user_id?: string | null
          player_hero_id?: string | null
          price_ton?: number | null
          revoked_at?: string | null
          rotation_retired_at?: string | null
          stars?: number
          status?: string
          tier_ton?: number | null
          unique_instance_id?: string
          updated_at?: string
          xp?: number
          yield_locked_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "nft_heroes_hero_template_id_fkey"
            columns: ["hero_template_id"]
            isOneToOne: false
            referencedRelation: "hero_catalog"
            referencedColumns: ["hero_key"]
          },
          {
            foreignKeyName: "nft_heroes_owner_user_id_fkey"
            columns: ["owner_user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      nft_mining_ledger: {
        Row: {
          admin_telegram_id: number | null
          amount: number
          created_at: string
          currency: string
          entry_type: string
          id: string
          meta: Json
          reference_id: string | null
          user_id: string | null
        }
        Insert: {
          admin_telegram_id?: number | null
          amount?: number
          created_at?: string
          currency: string
          entry_type: string
          id?: string
          meta?: Json
          reference_id?: string | null
          user_id?: string | null
        }
        Update: {
          admin_telegram_id?: number | null
          amount?: number
          created_at?: string
          currency?: string
          entry_type?: string
          id?: string
          meta?: Json
          reference_id?: string | null
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "nft_mining_ledger_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      nft_pet_history: {
        Row: {
          action: string
          admin_telegram_id: number | null
          created_at: string
          from_user_id: string | null
          id: string
          metadata: Json
          nft_pet_id: string
          reason: string | null
          to_user_id: string | null
        }
        Insert: {
          action: string
          admin_telegram_id?: number | null
          created_at?: string
          from_user_id?: string | null
          id?: string
          metadata?: Json
          nft_pet_id: string
          reason?: string | null
          to_user_id?: string | null
        }
        Update: {
          action?: string
          admin_telegram_id?: number | null
          created_at?: string
          from_user_id?: string | null
          id?: string
          metadata?: Json
          nft_pet_id?: string
          reason?: string | null
          to_user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "nft_pet_history_nft_pet_id_fkey"
            columns: ["nft_pet_id"]
            isOneToOne: false
            referencedRelation: "nft_pets"
            referencedColumns: ["id"]
          },
        ]
      }
      nft_pet_orders: {
        Row: {
          amount_nano: string
          confirmed_at: string | null
          created_at: string
          delivered_at: string | null
          expires_at: string
          id: string
          idempotency_key: string
          nft_pet_id: string
          paid_at: string | null
          payment_address: string
          payment_comment: string
          price_ton: number
          status: string
          tx_hash: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          amount_nano: string
          confirmed_at?: string | null
          created_at?: string
          delivered_at?: string | null
          expires_at?: string
          id?: string
          idempotency_key: string
          nft_pet_id: string
          paid_at?: string | null
          payment_address: string
          payment_comment: string
          price_ton: number
          status?: string
          tx_hash?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          amount_nano?: string
          confirmed_at?: string | null
          created_at?: string
          delivered_at?: string | null
          expires_at?: string
          id?: string
          idempotency_key?: string
          nft_pet_id?: string
          paid_at?: string | null
          payment_address?: string
          payment_comment?: string
          price_ton?: number
          status?: string
          tx_hash?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "nft_pet_orders_nft_pet_id_fkey"
            columns: ["nft_pet_id"]
            isOneToOne: false
            referencedRelation: "nft_pets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "nft_pet_orders_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      nft_pets: {
        Row: {
          appearance_family: string | null
          assigned_at: string | null
          blockchain: string | null
          breed_count: number
          breeding_cooldown_until: string | null
          breeding_locked: boolean
          contract_address: string | null
          created_at: string
          created_by_admin: number | null
          daily_yield_myth: number
          daily_yield_ton: number | null
          element: string | null
          for_sale: boolean
          generation: number
          id: string
          metadata: Json
          mining_pending_reveal: boolean
          mining_revealed_at: string | null
          minted: boolean
          nft_address: string | null
          nft_serial: number
          owner_user_id: string | null
          pet_template_id: string
          player_pet_id: string | null
          price_ton: number | null
          revoked_at: string | null
          rotation_retired_at: string | null
          status: string
          tier_ton: number | null
          token_id: string | null
          unique_instance_id: string
          updated_at: string
          yield_locked_at: string | null
        }
        Insert: {
          appearance_family?: string | null
          assigned_at?: string | null
          blockchain?: string | null
          breed_count?: number
          breeding_cooldown_until?: string | null
          breeding_locked?: boolean
          contract_address?: string | null
          created_at?: string
          created_by_admin?: number | null
          daily_yield_myth?: number
          daily_yield_ton?: number | null
          element?: string | null
          for_sale?: boolean
          generation?: number
          id?: string
          metadata?: Json
          mining_pending_reveal?: boolean
          mining_revealed_at?: string | null
          minted?: boolean
          nft_address?: string | null
          nft_serial: number
          owner_user_id?: string | null
          pet_template_id: string
          player_pet_id?: string | null
          price_ton?: number | null
          revoked_at?: string | null
          rotation_retired_at?: string | null
          status?: string
          tier_ton?: number | null
          token_id?: string | null
          unique_instance_id: string
          updated_at?: string
          yield_locked_at?: string | null
        }
        Update: {
          appearance_family?: string | null
          assigned_at?: string | null
          blockchain?: string | null
          breed_count?: number
          breeding_cooldown_until?: string | null
          breeding_locked?: boolean
          contract_address?: string | null
          created_at?: string
          created_by_admin?: number | null
          daily_yield_myth?: number
          daily_yield_ton?: number | null
          element?: string | null
          for_sale?: boolean
          generation?: number
          id?: string
          metadata?: Json
          mining_pending_reveal?: boolean
          mining_revealed_at?: string | null
          minted?: boolean
          nft_address?: string | null
          nft_serial?: number
          owner_user_id?: string | null
          pet_template_id?: string
          player_pet_id?: string | null
          price_ton?: number | null
          revoked_at?: string | null
          rotation_retired_at?: string | null
          status?: string
          tier_ton?: number | null
          token_id?: string | null
          unique_instance_id?: string
          updated_at?: string
          yield_locked_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "nft_pets_owner_user_id_fkey"
            columns: ["owner_user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "nft_pets_pet_template_id_fkey"
            columns: ["pet_template_id"]
            isOneToOne: false
            referencedRelation: "pets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "nft_pets_player_pet_fk"
            columns: ["player_pet_id"]
            isOneToOne: false
            referencedRelation: "player_pets"
            referencedColumns: ["id"]
          },
        ]
      }
      nft_pool_settings: {
        Row: {
          accrual_enabled: boolean
          health_days: Json
          health_factors: Json
          id: boolean
          min_claim_ton: number
          roi_multiplier: number
          tier20_daily_ton: number
          tier30_daily_ton: number
          updated_at: string
        }
        Insert: {
          accrual_enabled?: boolean
          health_days?: Json
          health_factors?: Json
          id?: boolean
          min_claim_ton?: number
          roi_multiplier?: number
          tier20_daily_ton?: number
          tier30_daily_ton?: number
          updated_at?: string
        }
        Update: {
          accrual_enabled?: boolean
          health_days?: Json
          health_factors?: Json
          id?: boolean
          min_claim_ton?: number
          roi_multiplier?: number
          tier20_daily_ton?: number
          tier30_daily_ton?: number
          updated_at?: string
        }
        Relationships: []
      }
      nft_pool_transactions: {
        Row: {
          amount_ton: number
          balance_after: number
          balance_before: number
          claim_id: string | null
          created_at: string
          id: string
          nft_id: string | null
          note: string | null
          telegram_id: number | null
          type: string
          user_id: string | null
        }
        Insert: {
          amount_ton: number
          balance_after: number
          balance_before: number
          claim_id?: string | null
          created_at?: string
          id?: string
          nft_id?: string | null
          note?: string | null
          telegram_id?: number | null
          type: string
          user_id?: string | null
        }
        Update: {
          amount_ton?: number
          balance_after?: number
          balance_before?: number
          claim_id?: string | null
          created_at?: string
          id?: string
          nft_id?: string | null
          note?: string | null
          telegram_id?: number | null
          type?: string
          user_id?: string | null
        }
        Relationships: []
      }
      nft_reward_pool: {
        Row: {
          balance_ton: number
          debt_ton: number
          id: boolean
          lifetime_funded_ton: number
          lifetime_paid_ton: number
          reserved_ton: number
          updated_at: string
        }
        Insert: {
          balance_ton?: number
          debt_ton?: number
          id?: boolean
          lifetime_funded_ton?: number
          lifetime_paid_ton?: number
          reserved_ton?: number
          updated_at?: string
        }
        Update: {
          balance_ton?: number
          debt_ton?: number
          id?: boolean
          lifetime_funded_ton?: number
          lifetime_paid_ton?: number
          reserved_ton?: number
          updated_at?: string
        }
        Relationships: []
      }
      nft_rotation_targets: {
        Row: {
          active_slots: number
          daily_yield_ton: number | null
          kind: string
          tier_ton: number
          updated_at: string
        }
        Insert: {
          active_slots: number
          daily_yield_ton?: number | null
          kind: string
          tier_ton: number
          updated_at?: string
        }
        Update: {
          active_slots?: number
          daily_yield_ton?: number | null
          kind?: string
          tier_ton?: number
          updated_at?: string
        }
        Relationships: []
      }
      nft_stock_pool: {
        Row: {
          asset_key: string
          created_at: string
          display_name: string
          element: string | null
          id: string
          kind: string
          name_norm: string
          released_at: string | null
          released_nft_id: string | null
          template_ref: string
          tier_ton: number
        }
        Insert: {
          asset_key: string
          created_at?: string
          display_name: string
          element?: string | null
          id?: string
          kind: string
          name_norm: string
          released_at?: string | null
          released_nft_id?: string | null
          template_ref: string
          tier_ton: number
        }
        Update: {
          asset_key?: string
          created_at?: string
          display_name?: string
          element?: string | null
          id?: string
          kind?: string
          name_norm?: string
          released_at?: string | null
          released_nft_id?: string | null
          template_ref?: string
          tier_ton?: number
        }
        Relationships: []
      }
      nft_yield_positions: {
        Row: {
          accrued_myth: number
          accrued_ton: number
          claimed_myth: number
          claimed_ton: number
          created_at: string
          daily_yield_myth: number
          daily_yield_ton: number
          id: string
          last_accrual_at: string
          last_claim_at: string | null
          nft_pet_id: string
          nft_serial: number
          owner_user_id: string | null
          roi_reached: boolean
          roi_target_ton: number
          status: string
          tier_ton: number
          updated_at: string
          yield_locked_at: string | null
        }
        Insert: {
          accrued_myth?: number
          accrued_ton?: number
          claimed_myth?: number
          claimed_ton?: number
          created_at?: string
          daily_yield_myth?: number
          daily_yield_ton?: number
          id?: string
          last_accrual_at?: string
          last_claim_at?: string | null
          nft_pet_id: string
          nft_serial: number
          owner_user_id?: string | null
          roi_reached?: boolean
          roi_target_ton?: number
          status?: string
          tier_ton?: number
          updated_at?: string
          yield_locked_at?: string | null
        }
        Update: {
          accrued_myth?: number
          accrued_ton?: number
          claimed_myth?: number
          claimed_ton?: number
          created_at?: string
          daily_yield_myth?: number
          daily_yield_ton?: number
          id?: string
          last_accrual_at?: string
          last_claim_at?: string | null
          nft_pet_id?: string
          nft_serial?: number
          owner_user_id?: string | null
          roi_reached?: boolean
          roi_target_ton?: number
          status?: string
          tier_ton?: number
          updated_at?: string
          yield_locked_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "nft_yield_positions_nft_pet_id_fkey"
            columns: ["nft_pet_id"]
            isOneToOne: true
            referencedRelation: "nft_pets"
            referencedColumns: ["id"]
          },
        ]
      }
      nft_yield_review: {
        Row: {
          created_at: string
          id: string
          instance_yield: number | null
          kind: string
          nft_id: string | null
          nft_serial: number | null
          note: string | null
          owner_user_id: string | null
          status: string
          suggested_yield: number | null
          template_yield: number | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: string
          instance_yield?: number | null
          kind: string
          nft_id?: string | null
          nft_serial?: number | null
          note?: string | null
          owner_user_id?: string | null
          status?: string
          suggested_yield?: number | null
          template_yield?: number | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          instance_yield?: number | null
          kind?: string
          nft_id?: string | null
          nft_serial?: number | null
          note?: string | null
          owner_user_id?: string | null
          status?: string
          suggested_yield?: number | null
          template_yield?: number | null
          updated_at?: string
        }
        Relationships: []
      }
      partner_channels: {
        Row: {
          created_at: string
          id: string
          is_enabled: boolean
          name: string
          reward_fc: number
          sort_order: number
          target_url: string
          telegram_chat_id: string | null
          updated_at: string
          validation_enabled: boolean
        }
        Insert: {
          created_at?: string
          id?: string
          is_enabled?: boolean
          name: string
          reward_fc?: number
          sort_order?: number
          target_url: string
          telegram_chat_id?: string | null
          updated_at?: string
          validation_enabled?: boolean
        }
        Update: {
          created_at?: string
          id?: string
          is_enabled?: boolean
          name?: string
          reward_fc?: number
          sort_order?: number
          target_url?: string
          telegram_chat_id?: string | null
          updated_at?: string
          validation_enabled?: boolean
        }
        Relationships: []
      }
      partner_claims: {
        Row: {
          claimed_at: string | null
          created_at: string
          id: string
          partner_id: string
          reward_fc: number
          status: string
          telegram_id: number
          updated_at: string
          user_id: string
          visited_at: string
        }
        Insert: {
          claimed_at?: string | null
          created_at?: string
          id?: string
          partner_id: string
          reward_fc?: number
          status?: string
          telegram_id: number
          updated_at?: string
          user_id: string
          visited_at?: string
        }
        Update: {
          claimed_at?: string | null
          created_at?: string
          id?: string
          partner_id?: string
          reward_fc?: number
          status?: string
          telegram_id?: number
          updated_at?: string
          user_id?: string
          visited_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "partner_claims_partner_id_fkey"
            columns: ["partner_id"]
            isOneToOne: false
            referencedRelation: "partner_channels"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "partner_claims_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      pass_locked_reward_orders: {
        Row: {
          amount_nano: string
          created_at: string
          delivered_at: string | null
          expires_at: string
          id: string
          idempotency_key: string | null
          method: string
          payment_address: string | null
          payment_comment: string | null
          price_ton: number
          reward_id: string
          season_id: string | null
          status: string
          telegram_id: number
          tx_hash: string | null
          user_id: string
        }
        Insert: {
          amount_nano: string
          created_at?: string
          delivered_at?: string | null
          expires_at?: string
          id?: string
          idempotency_key?: string | null
          method?: string
          payment_address?: string | null
          payment_comment?: string | null
          price_ton: number
          reward_id: string
          season_id?: string | null
          status?: string
          telegram_id: number
          tx_hash?: string | null
          user_id: string
        }
        Update: {
          amount_nano?: string
          created_at?: string
          delivered_at?: string | null
          expires_at?: string
          id?: string
          idempotency_key?: string | null
          method?: string
          payment_address?: string | null
          payment_comment?: string | null
          price_ton?: number
          reward_id?: string
          season_id?: string | null
          status?: string
          telegram_id?: number
          tx_hash?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "pass_locked_reward_orders_reward_id_fkey"
            columns: ["reward_id"]
            isOneToOne: false
            referencedRelation: "season_pass_rewards"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pass_locked_reward_orders_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      pass_version_audit: {
        Row: {
          action: string
          admin_id: number | null
          created_at: string
          id: string
          pass_type: string | null
          payload: Json
          season_id: string | null
          version_id: string | null
        }
        Insert: {
          action: string
          admin_id?: number | null
          created_at?: string
          id?: string
          pass_type?: string | null
          payload?: Json
          season_id?: string | null
          version_id?: string | null
        }
        Update: {
          action?: string
          admin_id?: number | null
          created_at?: string
          id?: string
          pass_type?: string | null
          payload?: Json
          season_id?: string | null
          version_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "pass_version_audit_version_id_fkey"
            columns: ["version_id"]
            isOneToOne: false
            referencedRelation: "pass_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      pass_versions: {
        Row: {
          activate_at: string | null
          activated_at: string | null
          archived_at: string | null
          audience_config: Json
          audience_mode: string
          cloned_from_version_id: string | null
          created_at: string
          created_by: number | null
          id: string
          levels: number
          notes: string | null
          pass_type: string
          price_ton_snapshot: number
          season_id: string
          status: string
          updated_at: string
          version_number: number
          xp_per_level: number
        }
        Insert: {
          activate_at?: string | null
          activated_at?: string | null
          archived_at?: string | null
          audience_config?: Json
          audience_mode?: string
          cloned_from_version_id?: string | null
          created_at?: string
          created_by?: number | null
          id?: string
          levels?: number
          notes?: string | null
          pass_type: string
          price_ton_snapshot?: number
          season_id: string
          status?: string
          updated_at?: string
          version_number: number
          xp_per_level?: number
        }
        Update: {
          activate_at?: string | null
          activated_at?: string | null
          archived_at?: string | null
          audience_config?: Json
          audience_mode?: string
          cloned_from_version_id?: string | null
          created_at?: string
          created_by?: number | null
          id?: string
          levels?: number
          notes?: string | null
          pass_type?: string
          price_ton_snapshot?: number
          season_id?: string
          status?: string
          updated_at?: string
          version_number?: number
          xp_per_level?: number
        }
        Relationships: [
          {
            foreignKeyName: "pass_versions_cloned_from_version_id_fkey"
            columns: ["cloned_from_version_id"]
            isOneToOne: false
            referencedRelation: "pass_versions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pass_versions_season_id_fkey"
            columns: ["season_id"]
            isOneToOne: false
            referencedRelation: "season_pass_seasons"
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
      pet_attribute_pool: {
        Row: {
          allowed_rarities: Json
          buff_key: string
          created_at: string
          enabled: boolean
          label: string
          max_override: number | null
          min_override: number | null
          updated_at: string
          weight: number
        }
        Insert: {
          allowed_rarities?: Json
          buff_key: string
          created_at?: string
          enabled?: boolean
          label: string
          max_override?: number | null
          min_override?: number | null
          updated_at?: string
          weight?: number
        }
        Update: {
          allowed_rarities?: Json
          buff_key?: string
          created_at?: string
          enabled?: boolean
          label?: string
          max_override?: number | null
          min_override?: number | null
          updated_at?: string
          weight?: number
        }
        Relationships: []
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
      pet_discoveries: {
        Row: {
          created_at: string
          discovered_at: string
          id: string
          pet_id: string
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          discovered_at?: string
          id?: string
          pet_id: string
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          discovered_at?: string
          id?: string
          pet_id?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "pet_discoveries_pet_id_fkey"
            columns: ["pet_id"]
            isOneToOne: false
            referencedRelation: "pets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pet_discoveries_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
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
          veteran_dragon_pet_id: string | null
          veteran_line: boolean
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
          veteran_dragon_pet_id?: string | null
          veteran_line?: boolean
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
          veteran_dragon_pet_id?: string | null
          veteran_line?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "pet_eggs_veteran_dragon_pet_id_fkey"
            columns: ["veteran_dragon_pet_id"]
            isOneToOne: false
            referencedRelation: "pets"
            referencedColumns: ["id"]
          },
        ]
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
      pet_expeditions: {
        Row: {
          ad_boosts_used: number
          claimed_at: string | null
          created_at: string
          finishes_at: string
          hero_ids: string[]
          id: string
          mission_id: string
          pet_ids: string[]
          rewards: Json
          started_at: string
          status: string
          success: boolean | null
          success_chance: number
          team_power: number
          user_id: string
        }
        Insert: {
          ad_boosts_used?: number
          claimed_at?: string | null
          created_at?: string
          finishes_at: string
          hero_ids?: string[]
          id?: string
          mission_id: string
          pet_ids: string[]
          rewards?: Json
          started_at?: string
          status?: string
          success?: boolean | null
          success_chance?: number
          team_power?: number
          user_id: string
        }
        Update: {
          ad_boosts_used?: number
          claimed_at?: string | null
          created_at?: string
          finishes_at?: string
          hero_ids?: string[]
          id?: string
          mission_id?: string
          pet_ids?: string[]
          rewards?: Json
          started_at?: string
          status?: string
          success?: boolean | null
          success_chance?: number
          team_power?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "pet_expeditions_mission_id_fkey"
            columns: ["mission_id"]
            isOneToOne: false
            referencedRelation: "expedition_missions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pet_expeditions_user_id_fkey"
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
      pet_rarity_config: {
        Row: {
          attr_max: number
          attr_min: number
          color_primary: string
          color_secondary: string
          created_at: string
          enabled: boolean
          glow: string
          label: string
          label_pt: string
          multiplier: number
          power: number
          rarity: string
          sort_order: number
          updated_at: string
        }
        Insert: {
          attr_max?: number
          attr_min?: number
          color_primary?: string
          color_secondary?: string
          created_at?: string
          enabled?: boolean
          glow?: string
          label: string
          label_pt: string
          multiplier?: number
          power?: number
          rarity: string
          sort_order: number
          updated_at?: string
        }
        Update: {
          attr_max?: number
          attr_min?: number
          color_primary?: string
          color_secondary?: string
          created_at?: string
          enabled?: boolean
          glow?: string
          label?: string
          label_pt?: string
          multiplier?: number
          power?: number
          rarity?: string
          sort_order?: number
          updated_at?: string
        }
        Relationships: []
      }
      pet_rarity_mismatch_audit: {
        Row: {
          created_at: string
          entity_id: string | null
          id: string
          new_rarity: string | null
          note: string | null
          old_rarity: string | null
          pet_id: string | null
          pet_slug: string | null
          scope: string
        }
        Insert: {
          created_at?: string
          entity_id?: string | null
          id?: string
          new_rarity?: string | null
          note?: string | null
          old_rarity?: string | null
          pet_id?: string | null
          pet_slug?: string | null
          scope: string
        }
        Update: {
          created_at?: string
          entity_id?: string | null
          id?: string
          new_rarity?: string | null
          note?: string | null
          old_rarity?: string | null
          pet_id?: string | null
          pet_slug?: string | null
          scope?: string
        }
        Relationships: []
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
      pet_xp_transfers: {
        Row: {
          balance_after: number | null
          balance_before: number | null
          created_at: string
          fc_cost: number
          id: string
          source_level_before: number
          source_pet_name: string | null
          source_player_pet_id: string
          target_level_after: number
          target_level_before: number
          target_pet_name: string | null
          target_player_pet_id: string
          telegram_id: number | null
          updated_at: string
          user_id: string
          xp_transferred: number
        }
        Insert: {
          balance_after?: number | null
          balance_before?: number | null
          created_at?: string
          fc_cost?: number
          id?: string
          source_level_before: number
          source_pet_name?: string | null
          source_player_pet_id: string
          target_level_after: number
          target_level_before: number
          target_pet_name?: string | null
          target_player_pet_id: string
          telegram_id?: number | null
          updated_at?: string
          user_id: string
          xp_transferred: number
        }
        Update: {
          balance_after?: number | null
          balance_before?: number | null
          created_at?: string
          fc_cost?: number
          id?: string
          source_level_before?: number
          source_pet_name?: string | null
          source_player_pet_id?: string
          target_level_after?: number
          target_level_before?: number
          target_pet_name?: string | null
          target_player_pet_id?: string
          telegram_id?: number | null
          updated_at?: string
          user_id?: string
          xp_transferred?: number
        }
        Relationships: []
      }
      pets: {
        Row: {
          active_skill: Json | null
          availability_type: string
          base_passives: Json
          category: string
          created_at: string
          description: string | null
          egg_eligible: boolean
          exclusive_badge: string | null
          exclusive_pass_tier: string | null
          exclusive_passive: Json
          exclusive_season_id: string | null
          hide_name_until_discovered: boolean
          id: string
          image_adult_url: string | null
          image_ancestral_url: string | null
          image_baby_url: string | null
          image_base_url: string | null
          image_evo1_url: string | null
          image_evo2_url: string | null
          image_evo3_url: string | null
          image_evo4_url: string | null
          image_final_url: string | null
          image_young_url: string | null
          is_enabled: boolean
          is_nft_exclusive: boolean
          is_pass_exclusive: boolean
          is_season_exclusive: boolean
          name: string
          obtainable_from: Json
          primary_attribute_key: string | null
          primary_attribute_value: number | null
          rarity: string
          show_in_catalog: boolean
          slug: string
          species: string
          updated_at: string
          veteran_line: boolean
          veteran_role: string | null
        }
        Insert: {
          active_skill?: Json | null
          availability_type?: string
          base_passives?: Json
          category: string
          created_at?: string
          description?: string | null
          egg_eligible?: boolean
          exclusive_badge?: string | null
          exclusive_pass_tier?: string | null
          exclusive_passive?: Json
          exclusive_season_id?: string | null
          hide_name_until_discovered?: boolean
          id?: string
          image_adult_url?: string | null
          image_ancestral_url?: string | null
          image_baby_url?: string | null
          image_base_url?: string | null
          image_evo1_url?: string | null
          image_evo2_url?: string | null
          image_evo3_url?: string | null
          image_evo4_url?: string | null
          image_final_url?: string | null
          image_young_url?: string | null
          is_enabled?: boolean
          is_nft_exclusive?: boolean
          is_pass_exclusive?: boolean
          is_season_exclusive?: boolean
          name: string
          obtainable_from?: Json
          primary_attribute_key?: string | null
          primary_attribute_value?: number | null
          rarity?: string
          show_in_catalog?: boolean
          slug: string
          species: string
          updated_at?: string
          veteran_line?: boolean
          veteran_role?: string | null
        }
        Update: {
          active_skill?: Json | null
          availability_type?: string
          base_passives?: Json
          category?: string
          created_at?: string
          description?: string | null
          egg_eligible?: boolean
          exclusive_badge?: string | null
          exclusive_pass_tier?: string | null
          exclusive_passive?: Json
          exclusive_season_id?: string | null
          hide_name_until_discovered?: boolean
          id?: string
          image_adult_url?: string | null
          image_ancestral_url?: string | null
          image_baby_url?: string | null
          image_base_url?: string | null
          image_evo1_url?: string | null
          image_evo2_url?: string | null
          image_evo3_url?: string | null
          image_evo4_url?: string | null
          image_final_url?: string | null
          image_young_url?: string | null
          is_enabled?: boolean
          is_nft_exclusive?: boolean
          is_pass_exclusive?: boolean
          is_season_exclusive?: boolean
          name?: string
          obtainable_from?: Json
          primary_attribute_key?: string | null
          primary_attribute_value?: number | null
          rarity?: string
          show_in_catalog?: boolean
          slug?: string
          species?: string
          updated_at?: string
          veteran_line?: boolean
          veteran_role?: string | null
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
      player_entitlements: {
        Row: {
          code: string
          equipped: boolean
          granted_at: string
          id: string
          source: string | null
          user_id: string
        }
        Insert: {
          code: string
          equipped?: boolean
          granted_at?: string
          id?: string
          source?: string | null
          user_id: string
        }
        Update: {
          code?: string
          equipped?: boolean
          granted_at?: string
          id?: string
          source?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "player_entitlements_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      player_equipment: {
        Row: {
          created_at: string
          hero_id: string | null
          id: string
          level: number
          locked: boolean
          market_locked: boolean
          mining_daily_myth: number
          mining_last_at: string | null
          premium_source: string | null
          source: string
          source_ref: string | null
          template_id: string
          updated_at: string
          user_id: string
          veteran_line: boolean
        }
        Insert: {
          created_at?: string
          hero_id?: string | null
          id?: string
          level?: number
          locked?: boolean
          market_locked?: boolean
          mining_daily_myth?: number
          mining_last_at?: string | null
          premium_source?: string | null
          source?: string
          source_ref?: string | null
          template_id: string
          updated_at?: string
          user_id: string
          veteran_line?: boolean
        }
        Update: {
          created_at?: string
          hero_id?: string | null
          id?: string
          level?: number
          locked?: boolean
          market_locked?: boolean
          mining_daily_myth?: number
          mining_last_at?: string | null
          premium_source?: string | null
          source?: string
          source_ref?: string | null
          template_id?: string
          updated_at?: string
          user_id?: string
          veteran_line?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "player_equipment_template_id_fkey"
            columns: ["template_id"]
            isOneToOne: false
            referencedRelation: "equipment_templates"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "player_equipment_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
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
          crit_rate: number | null
          defense: number | null
          equip_atk: number
          equip_def: number
          equip_hp: number
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
          is_nft_exclusive: boolean
          is_season_exclusive: boolean
          level: number
          locked: boolean
          market_locked: boolean
          mining_daily_myth: number
          mining_last_at: string | null
          mining_pending_reveal: boolean
          mining_revealed_at: string | null
          mining_ton_override: number | null
          name: string
          nft_hero_id: string | null
          nft_instance_id: string | null
          nft_serial: number | null
          pass_exclusive: boolean
          premium_source: string | null
          rarity: string
          skill_power: number | null
          speed: number | null
          stats_generated_at: string | null
          stats_seed: string
          tradable: boolean
          updated_at: string
          user_id: string
          veteran_line: boolean
          xp: number
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
          crit_rate?: number | null
          defense?: number | null
          equip_atk?: number
          equip_def?: number
          equip_hp?: number
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
          is_nft_exclusive?: boolean
          is_season_exclusive?: boolean
          level?: number
          locked?: boolean
          market_locked?: boolean
          mining_daily_myth?: number
          mining_last_at?: string | null
          mining_pending_reveal?: boolean
          mining_revealed_at?: string | null
          mining_ton_override?: number | null
          name: string
          nft_hero_id?: string | null
          nft_instance_id?: string | null
          nft_serial?: number | null
          pass_exclusive?: boolean
          premium_source?: string | null
          rarity: string
          skill_power?: number | null
          speed?: number | null
          stats_generated_at?: string | null
          stats_seed: string
          tradable?: boolean
          updated_at?: string
          user_id: string
          veteran_line?: boolean
          xp?: number
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
          crit_rate?: number | null
          defense?: number | null
          equip_atk?: number
          equip_def?: number
          equip_hp?: number
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
          is_nft_exclusive?: boolean
          is_season_exclusive?: boolean
          level?: number
          locked?: boolean
          market_locked?: boolean
          mining_daily_myth?: number
          mining_last_at?: string | null
          mining_pending_reveal?: boolean
          mining_revealed_at?: string | null
          mining_ton_override?: number | null
          name?: string
          nft_hero_id?: string | null
          nft_instance_id?: string | null
          nft_serial?: number | null
          pass_exclusive?: boolean
          premium_source?: string | null
          rarity?: string
          skill_power?: number | null
          speed?: number | null
          stats_generated_at?: string | null
          stats_seed?: string
          tradable?: boolean
          updated_at?: string
          user_id?: string
          veteran_line?: boolean
          xp?: number
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
          market_locked: boolean
          mining_daily_myth: number
          mining_last_at: string | null
          nft_pet_id: string | null
          obtained_at: string
          pass_exclusive: boolean
          passives_override: Json | null
          pet_id: string
          premium_source: string | null
          rarity: string
          secondary_buffs: Json
          sub_nft_id: string | null
          tradable: boolean
          updated_at: string
          user_id: string
          veteran_line: boolean
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
          market_locked?: boolean
          mining_daily_myth?: number
          mining_last_at?: string | null
          nft_pet_id?: string | null
          obtained_at?: string
          pass_exclusive?: boolean
          passives_override?: Json | null
          pet_id: string
          premium_source?: string | null
          rarity: string
          secondary_buffs?: Json
          sub_nft_id?: string | null
          tradable?: boolean
          updated_at?: string
          user_id: string
          veteran_line?: boolean
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
          market_locked?: boolean
          mining_daily_myth?: number
          mining_last_at?: string | null
          nft_pet_id?: string | null
          obtained_at?: string
          pass_exclusive?: boolean
          passives_override?: Json | null
          pet_id?: string
          premium_source?: string | null
          rarity?: string
          secondary_buffs?: Json
          sub_nft_id?: string | null
          tradable?: boolean
          updated_at?: string
          user_id?: string
          veteran_line?: boolean
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
            foreignKeyName: "player_pets_nft_pet_id_fkey"
            columns: ["nft_pet_id"]
            isOneToOne: false
            referencedRelation: "nft_pets"
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
            foreignKeyName: "player_pets_sub_nft_id_fkey"
            columns: ["sub_nft_id"]
            isOneToOne: false
            referencedRelation: "sub_nfts"
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
          expires_at: string | null
          legendary_owned: boolean
          pass_version: number
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
          expires_at?: string | null
          legendary_owned?: boolean
          pass_version?: number
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
          expires_at?: string | null
          legendary_owned?: boolean
          pass_version?: number
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
          game_day: string | null
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
          game_day?: string | null
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
          game_day?: string | null
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
      pool_ranking_tiers: {
        Row: {
          end_rank: number
          id: string
          pool_percent: number
          reward_mode: string
          start_rank: number
          updated_at: string
        }
        Insert: {
          end_rank: number
          id?: string
          pool_percent: number
          reward_mode?: string
          start_rank: number
          updated_at?: string
        }
        Update: {
          end_rank?: number
          id?: string
          pool_percent?: number
          reward_mode?: string
          start_rank?: number
          updated_at?: string
        }
        Relationships: []
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
      pool_reward_adjustments: {
        Row: {
          applied_at: string | null
          applied_history_id: string | null
          created_at: string
          created_by_admin: number | null
          delta_ton: number
          id: string
          pool_id: string | null
          reason: string | null
          user_id: string
        }
        Insert: {
          applied_at?: string | null
          applied_history_id?: string | null
          created_at?: string
          created_by_admin?: number | null
          delta_ton: number
          id?: string
          pool_id?: string | null
          reason?: string | null
          user_id: string
        }
        Update: {
          applied_at?: string | null
          applied_history_id?: string | null
          created_at?: string
          created_by_admin?: number | null
          delta_ton?: number
          id?: string
          pool_id?: string | null
          reason?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "pool_reward_adjustments_user_id_fkey"
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
      premium_myth_mining_pools: {
        Row: {
          allocated_myth: number
          distributed_myth: number
          offer_type: string
          updated_at: string
        }
        Insert: {
          allocated_myth?: number
          distributed_myth?: number
          offer_type: string
          updated_at?: string
        }
        Update: {
          allocated_myth?: number
          distributed_myth?: number
          offer_type?: string
          updated_at?: string
        }
        Relationships: []
      }
      premium_offer_impressions: {
        Row: {
          admin_reset_at: string | null
          admin_reset_by: number | null
          clicked_at: string | null
          created_at: string
          dismissed_at: string | null
          id: string
          impression_date: string
          offer_id: string
          purchased_at: string | null
          shown_at: string
          user_id: string
        }
        Insert: {
          admin_reset_at?: string | null
          admin_reset_by?: number | null
          clicked_at?: string | null
          created_at?: string
          dismissed_at?: string | null
          id?: string
          impression_date: string
          offer_id: string
          purchased_at?: string | null
          shown_at?: string
          user_id: string
        }
        Update: {
          admin_reset_at?: string | null
          admin_reset_by?: number | null
          clicked_at?: string | null
          created_at?: string
          dismissed_at?: string | null
          id?: string
          impression_date?: string
          offer_id?: string
          purchased_at?: string | null
          shown_at?: string
          user_id?: string
        }
        Relationships: []
      }
      premium_offer_popup_views: {
        Row: {
          day_key: string
          dismissed_at: string | null
          id: string
          offer_type: string
          purchase_id: string | null
          shown_at: string
          user_id: string
        }
        Insert: {
          day_key: string
          dismissed_at?: string | null
          id?: string
          offer_type: string
          purchase_id?: string | null
          shown_at?: string
          user_id: string
        }
        Update: {
          day_key?: string
          dismissed_at?: string | null
          id?: string
          offer_type?: string
          purchase_id?: string | null
          shown_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "premium_offer_popup_views_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      premium_offer_settings: {
        Row: {
          id: boolean
          reset_timezone: string
          updated_at: string
        }
        Insert: {
          id?: boolean
          reset_timezone?: string
          updated_at?: string
        }
        Update: {
          id?: boolean
          reset_timezone?: string
          updated_at?: string
        }
        Relationships: []
      }
      private_trade_events: {
        Row: {
          actor_user_id: string | null
          created_at: string
          details: Json
          event: string
          id: string
          trade_id: string | null
        }
        Insert: {
          actor_user_id?: string | null
          created_at?: string
          details?: Json
          event: string
          id?: string
          trade_id?: string | null
        }
        Update: {
          actor_user_id?: string | null
          created_at?: string
          details?: Json
          event?: string
          id?: string
          trade_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "private_trade_events_trade_id_fkey"
            columns: ["trade_id"]
            isOneToOne: false
            referencedRelation: "private_trades"
            referencedColumns: ["id"]
          },
        ]
      }
      private_trade_idempotency: {
        Row: {
          action: string
          created_at: string
          request_id: string
          result: Json
          trade_id: string | null
        }
        Insert: {
          action: string
          created_at?: string
          request_id: string
          result?: Json
          trade_id?: string | null
        }
        Update: {
          action?: string
          created_at?: string
          request_id?: string
          result?: Json
          trade_id?: string | null
        }
        Relationships: []
      }
      private_trade_items: {
        Row: {
          created_at: string
          id: string
          item_code: string | null
          item_instance_id: string | null
          item_type: string
          owner_user_id: string
          quantity: number
          side: string
          snapshot: Json
          trade_id: string
          value_fc: number
        }
        Insert: {
          created_at?: string
          id?: string
          item_code?: string | null
          item_instance_id?: string | null
          item_type: string
          owner_user_id: string
          quantity?: number
          side: string
          snapshot?: Json
          trade_id: string
          value_fc?: number
        }
        Update: {
          created_at?: string
          id?: string
          item_code?: string | null
          item_instance_id?: string | null
          item_type?: string
          owner_user_id?: string
          quantity?: number
          side?: string
          snapshot?: Json
          trade_id?: string
          value_fc?: number
        }
        Relationships: [
          {
            foreignKeyName: "private_trade_items_owner_user_id_fkey"
            columns: ["owner_user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "private_trade_items_trade_id_fkey"
            columns: ["trade_id"]
            isOneToOne: false
            referencedRelation: "private_trades"
            referencedColumns: ["id"]
          },
        ]
      }
      private_trade_ledger: {
        Row: {
          created_at: string
          fc: number
          from_user_id: string | null
          id: string
          items: Json
          myth: number
          risk_flags: string[]
          risk_score: number
          to_user_id: string | null
          ton: number
          trade_id: string | null
        }
        Insert: {
          created_at?: string
          fc?: number
          from_user_id?: string | null
          id?: string
          items?: Json
          myth?: number
          risk_flags?: string[]
          risk_score?: number
          to_user_id?: string | null
          ton?: number
          trade_id?: string | null
        }
        Update: {
          created_at?: string
          fc?: number
          from_user_id?: string | null
          id?: string
          items?: Json
          myth?: number
          risk_flags?: string[]
          risk_score?: number
          to_user_id?: string | null
          ton?: number
          trade_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "private_trade_ledger_trade_id_fkey"
            columns: ["trade_id"]
            isOneToOne: false
            referencedRelation: "private_trades"
            referencedColumns: ["id"]
          },
        ]
      }
      private_trade_settings: {
        Row: {
          admin_only: boolean
          enabled: boolean
          expire_hours: number
          fee_percent: number
          high_rarity_risk: number
          high_value_min_deposit_ton: number
          id: number
          max_items: number
          min_account_days: number
          new_account_risk: number
          nft_transfer_risk: number
          one_sided_risk: number
          repeated_pair_risk: number
          require_deposit_for_high_value: boolean
          risk_critical: number
          risk_high: number
          risk_medium: number
          same_device_risk: number
          same_network_risk: number
          same_wallet_risk: number
          suspicious_cooldown_hours: number
          updated_at: string
        }
        Insert: {
          admin_only?: boolean
          enabled?: boolean
          expire_hours?: number
          fee_percent?: number
          high_rarity_risk?: number
          high_value_min_deposit_ton?: number
          id?: number
          max_items?: number
          min_account_days?: number
          new_account_risk?: number
          nft_transfer_risk?: number
          one_sided_risk?: number
          repeated_pair_risk?: number
          require_deposit_for_high_value?: boolean
          risk_critical?: number
          risk_high?: number
          risk_medium?: number
          same_device_risk?: number
          same_network_risk?: number
          same_wallet_risk?: number
          suspicious_cooldown_hours?: number
          updated_at?: string
        }
        Update: {
          admin_only?: boolean
          enabled?: boolean
          expire_hours?: number
          fee_percent?: number
          high_rarity_risk?: number
          high_value_min_deposit_ton?: number
          id?: number
          max_items?: number
          min_account_days?: number
          new_account_risk?: number
          nft_transfer_risk?: number
          one_sided_risk?: number
          repeated_pair_risk?: number
          require_deposit_for_high_value?: boolean
          risk_critical?: number
          risk_high?: number
          risk_medium?: number
          same_device_risk?: number
          same_network_risk?: number
          same_wallet_risk?: number
          suspicious_cooldown_hours?: number
          updated_at?: string
        }
        Relationships: []
      }
      private_trades: {
        Row: {
          admin_note: string | null
          cancel_reason: string | null
          cancelled_by: string | null
          code: string
          completed_at: string | null
          created_at: string
          expires_at: string
          id: string
          initiator_confirmed: boolean
          initiator_escrowed: boolean
          initiator_fc: number
          initiator_locked: boolean
          initiator_myth: number
          initiator_ton: number
          initiator_user_id: string
          recipient_confirmed: boolean
          recipient_escrowed: boolean
          recipient_fc: number
          recipient_locked: boolean
          recipient_myth: number
          recipient_ton: number
          recipient_user_id: string
          risk_flags: string[]
          risk_score: number
          status: string
          updated_at: string
        }
        Insert: {
          admin_note?: string | null
          cancel_reason?: string | null
          cancelled_by?: string | null
          code?: string
          completed_at?: string | null
          created_at?: string
          expires_at?: string
          id?: string
          initiator_confirmed?: boolean
          initiator_escrowed?: boolean
          initiator_fc?: number
          initiator_locked?: boolean
          initiator_myth?: number
          initiator_ton?: number
          initiator_user_id: string
          recipient_confirmed?: boolean
          recipient_escrowed?: boolean
          recipient_fc?: number
          recipient_locked?: boolean
          recipient_myth?: number
          recipient_ton?: number
          recipient_user_id: string
          risk_flags?: string[]
          risk_score?: number
          status?: string
          updated_at?: string
        }
        Update: {
          admin_note?: string | null
          cancel_reason?: string | null
          cancelled_by?: string | null
          code?: string
          completed_at?: string | null
          created_at?: string
          expires_at?: string
          id?: string
          initiator_confirmed?: boolean
          initiator_escrowed?: boolean
          initiator_fc?: number
          initiator_locked?: boolean
          initiator_myth?: number
          initiator_ton?: number
          initiator_user_id?: string
          recipient_confirmed?: boolean
          recipient_escrowed?: boolean
          recipient_fc?: number
          recipient_locked?: boolean
          recipient_myth?: number
          recipient_ton?: number
          recipient_user_id?: string
          risk_flags?: string[]
          risk_score?: number
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "private_trades_initiator_user_id_fkey"
            columns: ["initiator_user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "private_trades_recipient_user_id_fkey"
            columns: ["recipient_user_id"]
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
      pvp_ad_views: {
        Row: {
          block_id: string | null
          created_at: string
          cycle_date: string
          id: string
          provider: string
          rewarded_at: string | null
          source: string | null
          status: string
          user_id: string
        }
        Insert: {
          block_id?: string | null
          created_at?: string
          cycle_date?: string
          id?: string
          provider?: string
          rewarded_at?: string | null
          source?: string | null
          status?: string
          user_id: string
        }
        Update: {
          block_id?: string | null
          created_at?: string
          cycle_date?: string
          id?: string
          provider?: string
          rewarded_at?: string | null
          source?: string | null
          status?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "pvp_ad_views_user_id_fkey"
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
          defender_bot_id: string | null
          defender_id: string | null
          defender_power: number
          defender_team_snapshot: Json
          id: string
          is_bot_battle: boolean
          pet_debug: Json | null
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
          defender_bot_id?: string | null
          defender_id?: string | null
          defender_power: number
          defender_team_snapshot: Json
          id?: string
          is_bot_battle?: boolean
          pet_debug?: Json | null
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
          defender_bot_id?: string | null
          defender_id?: string | null
          defender_power?: number
          defender_team_snapshot?: Json
          id?: string
          is_bot_battle?: boolean
          pet_debug?: Json | null
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
            foreignKeyName: "pvp_battles_defender_bot_id_fkey"
            columns: ["defender_bot_id"]
            isOneToOne: false
            referencedRelation: "pvp_bots"
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
      pvp_bots: {
        Row: {
          attacker_power: number | null
          avatar_color: string
          avatar_letter: string
          created_at: string
          id: string
          league: string
          name: string
          power: number
          strategy: string
          target_user_id: string | null
          team: Json
          trophies: number
          used_at: string | null
        }
        Insert: {
          attacker_power?: number | null
          avatar_color: string
          avatar_letter: string
          created_at?: string
          id?: string
          league?: string
          name: string
          power?: number
          strategy?: string
          target_user_id?: string | null
          team?: Json
          trophies?: number
          used_at?: string | null
        }
        Update: {
          attacker_power?: number | null
          avatar_color?: string
          avatar_letter?: string
          created_at?: string
          id?: string
          league?: string
          name?: string
          power?: number
          strategy?: string
          target_user_id?: string | null
          team?: Json
          trophies?: number
          used_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "pvp_bots_target_user_id_fkey"
            columns: ["target_user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      pvp_league_events: {
        Row: {
          created_at: string
          duration_days: number
          enabled: boolean
          ends_at: string | null
          finished_at: string | null
          id: string
          min_matches: number
          name: string
          prize_pool_ton: number
          started_at: string | null
          status: string
          top_limit: number
          updated_at: string
        }
        Insert: {
          created_at?: string
          duration_days?: number
          enabled?: boolean
          ends_at?: string | null
          finished_at?: string | null
          id?: string
          min_matches?: number
          name?: string
          prize_pool_ton?: number
          started_at?: string | null
          status?: string
          top_limit?: number
          updated_at?: string
        }
        Update: {
          created_at?: string
          duration_days?: number
          enabled?: boolean
          ends_at?: string | null
          finished_at?: string | null
          id?: string
          min_matches?: number
          name?: string
          prize_pool_ton?: number
          started_at?: string | null
          status?: string
          top_limit?: number
          updated_at?: string
        }
        Relationships: []
      }
      pvp_league_payouts: {
        Row: {
          created_at: string
          event_id: string
          id: string
          paid_at: string | null
          rank: number
          reward_ton: number
          score: number
          status: string
          user_id: string
        }
        Insert: {
          created_at?: string
          event_id: string
          id?: string
          paid_at?: string | null
          rank: number
          reward_ton: number
          score?: number
          status?: string
          user_id: string
        }
        Update: {
          created_at?: string
          event_id?: string
          id?: string
          paid_at?: string | null
          rank?: number
          reward_ton?: number
          score?: number
          status?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "pvp_league_payouts_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "pvp_league_events"
            referencedColumns: ["id"]
          },
        ]
      }
      pvp_league_rewards: {
        Row: {
          event_id: string
          rank: number
          reward_ton: number
        }
        Insert: {
          event_id: string
          rank: number
          reward_ton: number
        }
        Update: {
          event_id?: string
          rank?: number
          reward_ton?: number
        }
        Relationships: [
          {
            foreignKeyName: "pvp_league_rewards_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "pvp_league_events"
            referencedColumns: ["id"]
          },
        ]
      }
      pvp_league_score_events: {
        Row: {
          created_at: string
          event_id: string
          id: string
          match_id: string
          role: string
          score_delta: number
          user_id: string
        }
        Insert: {
          created_at?: string
          event_id: string
          id?: string
          match_id: string
          role?: string
          score_delta: number
          user_id: string
        }
        Update: {
          created_at?: string
          event_id?: string
          id?: string
          match_id?: string
          role?: string
          score_delta?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "pvp_league_score_events_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "pvp_league_events"
            referencedColumns: ["id"]
          },
        ]
      }
      pvp_league_scores: {
        Row: {
          best_score: number
          best_score_at: string | null
          created_at: string
          event_id: string
          losses: number
          matches: number
          score: number
          updated_at: string
          user_id: string
          wins: number
        }
        Insert: {
          best_score?: number
          best_score_at?: string | null
          created_at?: string
          event_id: string
          losses?: number
          matches?: number
          score?: number
          updated_at?: string
          user_id: string
          wins?: number
        }
        Update: {
          best_score?: number
          best_score_at?: string | null
          created_at?: string
          event_id?: string
          losses?: number
          matches?: number
          score?: number
          updated_at?: string
          user_id?: string
          wins?: number
        }
        Relationships: [
          {
            foreignKeyName: "pvp_league_scores_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "pvp_league_events"
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
          search_power: number | null
          shown_count: number
          user_id: string
        }
        Insert: {
          last_shown_at?: string
          opponent_id: string
          search_power?: number | null
          shown_count?: number
          user_id: string
        }
        Update: {
          last_shown_at?: string
          opponent_id?: string
          search_power?: number | null
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
      pvp_reward_settlements: {
        Row: {
          battle_id: string
          created_at: string
          fc_awarded: number
          finalized_at: string
          id: string
          note: string | null
          opponent_id: string | null
          opponent_type: string
          player_id: string
          result: string
          status: string
          trophies_awarded: number
          xp_awarded: number
        }
        Insert: {
          battle_id: string
          created_at?: string
          fc_awarded?: number
          finalized_at?: string
          id?: string
          note?: string | null
          opponent_id?: string | null
          opponent_type: string
          player_id: string
          result: string
          status?: string
          trophies_awarded?: number
          xp_awarded?: number
        }
        Update: {
          battle_id?: string
          created_at?: string
          fc_awarded?: number
          finalized_at?: string
          id?: string
          note?: string | null
          opponent_id?: string | null
          opponent_type?: string
          player_id?: string
          result?: string
          status?: string
          trophies_awarded?: number
          xp_awarded?: number
        }
        Relationships: [
          {
            foreignKeyName: "pvp_reward_settlements_battle_id_fkey"
            columns: ["battle_id"]
            isOneToOne: true
            referencedRelation: "pvp_battles"
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
          reward_hero_xp: boolean
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
          reward_hero_xp?: boolean
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
          reward_hero_xp?: boolean
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
      rare_myth_mining_balances: {
        Row: {
          last_claim_at: string | null
          lifetime_myth: number
          unclaimed_myth: number
          updated_at: string
          user_id: string
        }
        Insert: {
          last_claim_at?: string | null
          lifetime_myth?: number
          unclaimed_myth?: number
          updated_at?: string
          user_id: string
        }
        Update: {
          last_claim_at?: string | null
          lifetime_myth?: number
          unclaimed_myth?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      rare_myth_mining_daily: {
        Row: {
          day_key: string
          effective_units: number
          emitted_myth: number
          last_accrued_at: string
          rare_count: number
          updated_at: string
          user_id: string
        }
        Insert: {
          day_key: string
          effective_units?: number
          emitted_myth?: number
          last_accrued_at?: string
          rare_count?: number
          updated_at?: string
          user_id: string
        }
        Update: {
          day_key?: string
          effective_units?: number
          emitted_myth?: number
          last_accrued_at?: string
          rare_count?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      rare_myth_mining_settings: {
        Row: {
          created_at: string
          daily_budget_myth: number
          enabled: boolean
          id: boolean
          min_claim_myth: number
          player_daily_cap_myth: number
          tier1_max: number
          tier1_weight: number
          tier2_max: number
          tier2_weight: number
          tier3_max: number
          tier3_weight: number
          tier4_weight: number
          updated_at: string
        }
        Insert: {
          created_at?: string
          daily_budget_myth?: number
          enabled?: boolean
          id?: boolean
          min_claim_myth?: number
          player_daily_cap_myth?: number
          tier1_max?: number
          tier1_weight?: number
          tier2_max?: number
          tier2_weight?: number
          tier3_max?: number
          tier3_weight?: number
          tier4_weight?: number
          updated_at?: string
        }
        Update: {
          created_at?: string
          daily_budget_myth?: number
          enabled?: boolean
          id?: boolean
          min_claim_myth?: number
          player_daily_cap_myth?: number
          tier1_max?: number
          tier1_weight?: number
          tier2_max?: number
          tier2_weight?: number
          tier3_max?: number
          tier3_weight?: number
          tier4_weight?: number
          updated_at?: string
        }
        Relationships: []
      }
      rare_myth_mining_snapshots: {
        Row: {
          created_at: string
          daily_budget_myth: number
          day_key: string
          emitted_myth: number
          global_units: number
          players: number
          updated_at: string
        }
        Insert: {
          created_at?: string
          daily_budget_myth?: number
          day_key: string
          emitted_myth?: number
          global_units?: number
          players?: number
          updated_at?: string
        }
        Update: {
          created_at?: string
          daily_budget_myth?: number
          day_key?: string
          emitted_myth?: number
          global_units?: number
          players?: number
          updated_at?: string
        }
        Relationships: []
      }
      realm_bounties: {
        Row: {
          bounty_day: string
          bounty_type: string
          claimed_at: string | null
          expires_at: string
          id: string
          progress: number
          reward: Json
          status: string
          target: number
          title: string
          user_id: string
        }
        Insert: {
          bounty_day?: string
          bounty_type: string
          claimed_at?: string | null
          expires_at: string
          id?: string
          progress?: number
          reward?: Json
          status?: string
          target?: number
          title: string
          user_id: string
        }
        Update: {
          bounty_day?: string
          bounty_type?: string
          claimed_at?: string | null
          expires_at?: string
          id?: string
          progress?: number
          reward?: Json
          status?: string
          target?: number
          title?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "realm_bounties_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      realm_building_types: {
        Row: {
          base_fc_cost: number
          base_seconds: number
          cost_materials: Json
          description: string
          enabled: boolean
          id: string
          image_url: string | null
          max_level: number
          name: string
          order_index: number
        }
        Insert: {
          base_fc_cost?: number
          base_seconds?: number
          cost_materials?: Json
          description?: string
          enabled?: boolean
          id: string
          image_url?: string | null
          max_level?: number
          name: string
          order_index?: number
        }
        Update: {
          base_fc_cost?: number
          base_seconds?: number
          cost_materials?: Json
          description?: string
          enabled?: boolean
          id?: string
          image_url?: string | null
          max_level?: number
          name?: string
          order_index?: number
        }
        Relationships: []
      }
      realm_buildings: {
        Row: {
          building_type: string
          id: string
          level: number
          status: string
          updated_at: string
          upgrade_finishes_at: string | null
          upgrade_started_at: string | null
          user_id: string
        }
        Insert: {
          building_type: string
          id?: string
          level?: number
          status?: string
          updated_at?: string
          upgrade_finishes_at?: string | null
          upgrade_started_at?: string | null
          user_id: string
        }
        Update: {
          building_type?: string
          id?: string
          level?: number
          status?: string
          updated_at?: string
          upgrade_finishes_at?: string | null
          upgrade_started_at?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "realm_buildings_building_type_fkey"
            columns: ["building_type"]
            isOneToOne: false
            referencedRelation: "realm_building_types"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "realm_buildings_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      realm_crafting_jobs: {
        Row: {
          claimed_at: string | null
          finishes_at: string
          id: string
          idempotency_key: string | null
          quantity: number
          recipe_id: string
          started_at: string
          status: string
          user_id: string
        }
        Insert: {
          claimed_at?: string | null
          finishes_at: string
          id?: string
          idempotency_key?: string | null
          quantity?: number
          recipe_id: string
          started_at?: string
          status?: string
          user_id: string
        }
        Update: {
          claimed_at?: string | null
          finishes_at?: string
          id?: string
          idempotency_key?: string | null
          quantity?: number
          recipe_id?: string
          started_at?: string
          status?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "realm_crafting_jobs_recipe_id_fkey"
            columns: ["recipe_id"]
            isOneToOne: false
            referencedRelation: "realm_recipes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "realm_crafting_jobs_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      realm_expeditions: {
        Row: {
          claimed_at: string | null
          expedition_type: string
          finishes_at: string
          id: string
          idempotency_key: string | null
          region_id: string
          reward: Json | null
          reward_seed: number
          started_at: string
          status: string
          user_id: string
        }
        Insert: {
          claimed_at?: string | null
          expedition_type: string
          finishes_at: string
          id?: string
          idempotency_key?: string | null
          region_id: string
          reward?: Json | null
          reward_seed: number
          started_at?: string
          status?: string
          user_id: string
        }
        Update: {
          claimed_at?: string | null
          expedition_type?: string
          finishes_at?: string
          id?: string
          idempotency_key?: string | null
          region_id?: string
          reward?: Json | null
          reward_seed?: number
          started_at?: string
          status?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "realm_expeditions_region_id_fkey"
            columns: ["region_id"]
            isOneToOne: false
            referencedRelation: "realm_regions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "realm_expeditions_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      realm_explore_nodes: {
        Row: {
          config: Json
          depth: number
          id: string
          lane: number
          node_type: string
          resolved_at: string | null
          run_id: string
          status: string
        }
        Insert: {
          config?: Json
          depth: number
          id?: string
          lane: number
          node_type: string
          resolved_at?: string | null
          run_id: string
          status?: string
        }
        Update: {
          config?: Json
          depth?: number
          id?: string
          lane?: number
          node_type?: string
          resolved_at?: string | null
          run_id?: string
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "realm_explore_nodes_run_id_fkey"
            columns: ["run_id"]
            isOneToOne: false
            referencedRelation: "realm_explore_runs"
            referencedColumns: ["id"]
          },
        ]
      }
      realm_explore_runs: {
        Row: {
          auto: boolean
          completed_at: string | null
          depth: number
          depth_level: number
          difficulty: Json
          entry_cost: number
          final_depth: number
          hp: number
          id: string
          log: Json
          loot: Json
          loot_multiplier: number
          pending: Json | null
          region_id: string
          risk: number
          seed: number
          started_at: string
          status: string
          user_id: string
        }
        Insert: {
          auto?: boolean
          completed_at?: string | null
          depth?: number
          depth_level?: number
          difficulty?: Json
          entry_cost?: number
          final_depth?: number
          hp?: number
          id?: string
          log?: Json
          loot?: Json
          loot_multiplier?: number
          pending?: Json | null
          region_id: string
          risk?: number
          seed?: number
          started_at?: string
          status?: string
          user_id: string
        }
        Update: {
          auto?: boolean
          completed_at?: string | null
          depth?: number
          depth_level?: number
          difficulty?: Json
          entry_cost?: number
          final_depth?: number
          hp?: number
          id?: string
          log?: Json
          loot?: Json
          loot_multiplier?: number
          pending?: Json | null
          region_id?: string
          risk?: number
          seed?: number
          started_at?: string
          status?: string
          user_id?: string
        }
        Relationships: []
      }
      realm_material_balances: {
        Row: {
          amount: number
          material_id: string
          updated_at: string
          user_id: string
        }
        Insert: {
          amount?: number
          material_id: string
          updated_at?: string
          user_id: string
        }
        Update: {
          amount?: number
          material_id?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "realm_material_balances_material_id_fkey"
            columns: ["material_id"]
            isOneToOne: false
            referencedRelation: "realm_materials"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "realm_material_balances_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      realm_material_ledger: {
        Row: {
          amount: number
          balance_after: number
          balance_before: number
          created_at: string
          id: string
          material_id: string
          reason: string
          source_id: string | null
          user_id: string
        }
        Insert: {
          amount: number
          balance_after: number
          balance_before: number
          created_at?: string
          id?: string
          material_id: string
          reason: string
          source_id?: string | null
          user_id: string
        }
        Update: {
          amount?: number
          balance_after?: number
          balance_before?: number
          created_at?: string
          id?: string
          material_id?: string
          reason?: string
          source_id?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "realm_material_ledger_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      realm_materials: {
        Row: {
          enabled: boolean
          id: string
          image_url: string | null
          name: string
          order_index: number
          rarity: string
          region_id: string | null
        }
        Insert: {
          enabled?: boolean
          id: string
          image_url?: string | null
          name: string
          order_index?: number
          rarity?: string
          region_id?: string | null
        }
        Update: {
          enabled?: boolean
          id?: string
          image_url?: string | null
          name?: string
          order_index?: number
          rarity?: string
          region_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "realm_materials_region_id_fkey"
            columns: ["region_id"]
            isOneToOne: false
            referencedRelation: "realm_regions"
            referencedColumns: ["id"]
          },
        ]
      }
      realm_profiles: {
        Row: {
          bounties_day: string | null
          buildings_upgraded: number
          crafts_completed: number
          created_at: string
          current_region: string | null
          realm_level: number
          realm_xp: number
          ruins_completed: number
          stronghold_level: number
          updated_at: string
          user_id: string
        }
        Insert: {
          bounties_day?: string | null
          buildings_upgraded?: number
          crafts_completed?: number
          created_at?: string
          current_region?: string | null
          realm_level?: number
          realm_xp?: number
          ruins_completed?: number
          stronghold_level?: number
          updated_at?: string
          user_id: string
        }
        Update: {
          bounties_day?: string | null
          buildings_upgraded?: number
          crafts_completed?: number
          created_at?: string
          current_region?: string | null
          realm_level?: number
          realm_xp?: number
          ruins_completed?: number
          stronghold_level?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "realm_profiles_current_region_fkey"
            columns: ["current_region"]
            isOneToOne: false
            referencedRelation: "realm_regions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "realm_profiles_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      realm_recipes: {
        Row: {
          category: string
          craft_seconds: number
          enabled: boolean
          fc_cost: number
          id: string
          image_url: string | null
          inputs: Json
          min_forge_level: number
          name: string
          order_index: number
          output_kind: string
          output_qty: number
          output_ref: string
        }
        Insert: {
          category?: string
          craft_seconds?: number
          enabled?: boolean
          fc_cost?: number
          id: string
          image_url?: string | null
          inputs?: Json
          min_forge_level?: number
          name: string
          order_index?: number
          output_kind?: string
          output_qty?: number
          output_ref: string
        }
        Update: {
          category?: string
          craft_seconds?: number
          enabled?: boolean
          fc_cost?: number
          id?: string
          image_url?: string | null
          inputs?: Json
          min_forge_level?: number
          name?: string
          order_index?: number
          output_kind?: string
          output_qty?: number
          output_ref?: string
        }
        Relationships: []
      }
      realm_region_progress: {
        Row: {
          current_depth: number
          failed_runs: number
          highest_completed_depth: number
          id: string
          region_id: string
          successful_runs: number
          total_runs: number
          updated_at: string
          user_id: string
        }
        Insert: {
          current_depth?: number
          failed_runs?: number
          highest_completed_depth?: number
          id?: string
          region_id: string
          successful_runs?: number
          total_runs?: number
          updated_at?: string
          user_id: string
        }
        Update: {
          current_depth?: number
          failed_runs?: number
          highest_completed_depth?: number
          id?: string
          region_id?: string
          successful_runs?: number
          total_runs?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "realm_region_progress_region_id_fkey"
            columns: ["region_id"]
            isOneToOne: false
            referencedRelation: "realm_regions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "realm_region_progress_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      realm_regions: {
        Row: {
          atk_growth: number
          boss_interval: number
          created_at: string
          def_growth: number
          enabled: boolean
          entry_cost_base: number
          entry_cost_growth: number
          entry_cost_max: number
          hp_growth: number
          id: string
          image_url: string | null
          loot_growth: number
          loot_growth_max: number
          max_depth: number
          name: string
          order_index: number
          power_base: number
          power_growth: number
          recommended_power: number
          ruin_enabled: boolean
          tagline: string
          unlock_requires_region: string | null
          unlock_stronghold_level: number
        }
        Insert: {
          atk_growth?: number
          boss_interval?: number
          created_at?: string
          def_growth?: number
          enabled?: boolean
          entry_cost_base?: number
          entry_cost_growth?: number
          entry_cost_max?: number
          hp_growth?: number
          id: string
          image_url?: string | null
          loot_growth?: number
          loot_growth_max?: number
          max_depth?: number
          name: string
          order_index?: number
          power_base?: number
          power_growth?: number
          recommended_power?: number
          ruin_enabled?: boolean
          tagline?: string
          unlock_requires_region?: string | null
          unlock_stronghold_level?: number
        }
        Update: {
          atk_growth?: number
          boss_interval?: number
          created_at?: string
          def_growth?: number
          enabled?: boolean
          entry_cost_base?: number
          entry_cost_growth?: number
          entry_cost_max?: number
          hp_growth?: number
          id?: string
          image_url?: string | null
          loot_growth?: number
          loot_growth_max?: number
          max_depth?: number
          name?: string
          order_index?: number
          power_base?: number
          power_growth?: number
          recommended_power?: number
          ruin_enabled?: boolean
          tagline?: string
          unlock_requires_region?: string | null
          unlock_stronghold_level?: number
        }
        Relationships: []
      }
      realm_ruin_entry_config: {
        Row: {
          fc_cost: number
          id: boolean
          ton_cost: number
          ton_reward_multiplier: number
          updated_at: string
        }
        Insert: {
          fc_cost?: number
          id?: boolean
          ton_cost?: number
          ton_reward_multiplier?: number
          updated_at?: string
        }
        Update: {
          fc_cost?: number
          id?: boolean
          ton_cost?: number
          ton_reward_multiplier?: number
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
          amount_fc: number | null
          amount_ton: number
          created_at: string
          from_user: string
          id: string
          idempotency_key: string | null
          level: number
          purchase_id: string
          source_amount_ton: number | null
          source_type: string | null
          user_id: string
        }
        Insert: {
          amount_fc?: number | null
          amount_ton: number
          created_at?: string
          from_user: string
          id?: string
          idempotency_key?: string | null
          level: number
          purchase_id: string
          source_amount_ton?: number | null
          source_type?: string | null
          user_id: string
        }
        Update: {
          amount_fc?: number | null
          amount_ton?: number
          created_at?: string
          from_user?: string
          id?: string
          idempotency_key?: string | null
          level?: number
          purchase_id?: string
          source_amount_ton?: number | null
          source_type?: string | null
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
      referral_first_ton_events: {
        Row: {
          amount_ton: number
          buyer_id: string
          commission_ton: number
          created_at: string
          processed_at: string
          source_id: string
          source_type: string
          updated_at: string
        }
        Insert: {
          amount_ton: number
          buyer_id: string
          commission_ton?: number
          created_at?: string
          processed_at?: string
          source_id: string
          source_type: string
          updated_at?: string
        }
        Update: {
          amount_ton?: number
          buyer_id?: string
          commission_ton?: number
          created_at?: string
          processed_at?: string
          source_id?: string
          source_type?: string
          updated_at?: string
        }
        Relationships: []
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
      reward_pet_pool: {
        Row: {
          created_at: string
          enabled: boolean
          id: string
          pet_id: string
          rarity: string
          source_key: string
          source_type: string
          updated_at: string
          weight: number
        }
        Insert: {
          created_at?: string
          enabled?: boolean
          id?: string
          pet_id: string
          rarity: string
          source_key: string
          source_type: string
          updated_at?: string
          weight?: number
        }
        Update: {
          created_at?: string
          enabled?: boolean
          id?: string
          pet_id?: string
          rarity?: string
          source_key?: string
          source_type?: string
          updated_at?: string
          weight?: number
        }
        Relationships: [
          {
            foreignKeyName: "reward_pet_pool_pet_id_fkey"
            columns: ["pet_id"]
            isOneToOne: false
            referencedRelation: "pets"
            referencedColumns: ["id"]
          },
        ]
      }
      roulette_celestial_awards: {
        Row: {
          awarded_at: string
          cycle_id: string | null
          hero_key: string
          player_hero_id: string | null
          spin_id: string | null
          user_id: string
        }
        Insert: {
          awarded_at?: string
          cycle_id?: string | null
          hero_key: string
          player_hero_id?: string | null
          spin_id?: string | null
          user_id: string
        }
        Update: {
          awarded_at?: string
          cycle_id?: string | null
          hero_key?: string
          player_hero_id?: string | null
          spin_id?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "roulette_celestial_awards_cycle_id_fkey"
            columns: ["cycle_id"]
            isOneToOne: false
            referencedRelation: "global_roulette_cycles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "roulette_celestial_awards_spin_id_fkey"
            columns: ["spin_id"]
            isOneToOne: false
            referencedRelation: "global_roulette_spins"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "roulette_celestial_awards_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      roulette_myth_reserve: {
        Row: {
          allocated_myth: number
          distributed_myth: number
          id: boolean
          updated_at: string
        }
        Insert: {
          allocated_myth?: number
          distributed_myth?: number
          id?: boolean
          updated_at?: string
        }
        Update: {
          allocated_myth?: number
          distributed_myth?: number
          id?: boolean
          updated_at?: string
        }
        Relationships: []
      }
      roulette_reward_config: {
        Row: {
          created_at: string
          enabled: boolean
          id: string
          label: string
          metadata: Json
          quantity: number
          reference_cost_nanoton: number
          requires_global_threshold: boolean
          reward_class: string
          reward_key: string
          updated_at: string
          weight: number
        }
        Insert: {
          created_at?: string
          enabled?: boolean
          id?: string
          label?: string
          metadata?: Json
          quantity?: number
          reference_cost_nanoton?: number
          requires_global_threshold?: boolean
          reward_class: string
          reward_key: string
          updated_at?: string
          weight?: number
        }
        Update: {
          created_at?: string
          enabled?: boolean
          id?: string
          label?: string
          metadata?: Json
          quantity?: number
          reference_cost_nanoton?: number
          requires_global_threshold?: boolean
          reward_class?: string
          reward_key?: string
          updated_at?: string
          weight?: number
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
      season_mythic_egg_openings: {
        Row: {
          created_at: string
          id: string
          idempotency_key: string
          player_pet_id: string | null
          reward_id: string
          season_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          idempotency_key: string
          player_pet_id?: string | null
          reward_id: string
          season_id: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          idempotency_key?: string
          player_pet_id?: string | null
          reward_id?: string
          season_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "season_mythic_egg_openings_reward_id_fkey"
            columns: ["reward_id"]
            isOneToOne: false
            referencedRelation: "season_exclusive_rewards"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "season_mythic_egg_openings_season_id_fkey"
            columns: ["season_id"]
            isOneToOne: false
            referencedRelation: "season_pass_seasons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "season_mythic_egg_openings_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      season_pass_claim_audit: {
        Row: {
          claim_status: string
          created_at: string
          error_message: string | null
          id: string
          inventory_after: number | null
          inventory_before: number | null
          item_id: string | null
          level: number | null
          quantity: number | null
          reward_code: string | null
          reward_id: string | null
          reward_type: string | null
          season_id: string | null
          telegram_id: number | null
          user_id: string
        }
        Insert: {
          claim_status: string
          created_at?: string
          error_message?: string | null
          id?: string
          inventory_after?: number | null
          inventory_before?: number | null
          item_id?: string | null
          level?: number | null
          quantity?: number | null
          reward_code?: string | null
          reward_id?: string | null
          reward_type?: string | null
          season_id?: string | null
          telegram_id?: number | null
          user_id: string
        }
        Update: {
          claim_status?: string
          created_at?: string
          error_message?: string | null
          id?: string
          inventory_after?: number | null
          inventory_before?: number | null
          item_id?: string | null
          level?: number | null
          quantity?: number | null
          reward_code?: string | null
          reward_id?: string | null
          reward_type?: string | null
          season_id?: string | null
          telegram_id?: number | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "season_pass_claim_audit_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
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
          image_url: string | null
          is_highlight: boolean
          level: number
          min_pass_version: number
          requires_asset: boolean
          reward_asset: string | null
          reward_code: string | null
          reward_slot: number
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
          image_url?: string | null
          is_highlight?: boolean
          level: number
          min_pass_version?: number
          requires_asset?: boolean
          reward_asset?: string | null
          reward_code?: string | null
          reward_slot?: number
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
          image_url?: string | null
          is_highlight?: boolean
          level?: number
          min_pass_version?: number
          requires_asset?: boolean
          reward_asset?: string | null
          reward_code?: string | null
          reward_slot?: number
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
      sovereign_pack_config: {
        Row: {
          account_ton_bonus_percent: number
          celestial_armors: number
          enabled: boolean
          ends_at: string | null
          fc_reward: number
          id: boolean
          legendary_chests: number
          mythic_armors: number
          mythic_chests: number
          nft_weapons: number
          package_version: string
          popup_enabled: boolean
          popup_frequency: string
          popup_priority: number
          price_ton: number
          purchase_limit: number
          random_items: number
          random_items_pool: Json
          reward_configuration_version: number
          sales_paused: boolean
          sold_out_visible: boolean
          start_at: string | null
          stock_total: number | null
          updated_at: string
        }
        Insert: {
          account_ton_bonus_percent?: number
          celestial_armors?: number
          enabled?: boolean
          ends_at?: string | null
          fc_reward?: number
          id?: boolean
          legendary_chests?: number
          mythic_armors?: number
          mythic_chests?: number
          nft_weapons?: number
          package_version?: string
          popup_enabled?: boolean
          popup_frequency?: string
          popup_priority?: number
          price_ton?: number
          purchase_limit?: number
          random_items?: number
          random_items_pool?: Json
          reward_configuration_version?: number
          sales_paused?: boolean
          sold_out_visible?: boolean
          start_at?: string | null
          stock_total?: number | null
          updated_at?: string
        }
        Update: {
          account_ton_bonus_percent?: number
          celestial_armors?: number
          enabled?: boolean
          ends_at?: string | null
          fc_reward?: number
          id?: boolean
          legendary_chests?: number
          mythic_armors?: number
          mythic_chests?: number
          nft_weapons?: number
          package_version?: string
          popup_enabled?: boolean
          popup_frequency?: string
          popup_priority?: number
          price_ton?: number
          purchase_limit?: number
          random_items?: number
          random_items_pool?: Json
          reward_configuration_version?: number
          sales_paused?: boolean
          sold_out_visible?: boolean
          start_at?: string | null
          stock_total?: number | null
          updated_at?: string
        }
        Relationships: []
      }
      sovereign_pack_items: {
        Row: {
          created_at: string
          id: string
          instance_id: string | null
          item_type: string
          mining_pending_reveal: boolean
          purchase_id: string
          revealed_at: string | null
          revealed_myth: number | null
          revealed_ton: number | null
          template_id: string | null
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          instance_id?: string | null
          item_type: string
          mining_pending_reveal?: boolean
          purchase_id: string
          revealed_at?: string | null
          revealed_myth?: number | null
          revealed_ton?: number | null
          template_id?: string | null
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          instance_id?: string | null
          item_type?: string
          mining_pending_reveal?: boolean
          purchase_id?: string
          revealed_at?: string | null
          revealed_myth?: number | null
          revealed_ton?: number | null
          template_id?: string | null
          user_id?: string
        }
        Relationships: []
      }
      sovereign_pack_ledger: {
        Row: {
          created_at: string
          fc_amount: number | null
          id: string
          kind: string
          note: string | null
          purchase_id: string | null
          ton_amount: number | null
          user_id: string | null
        }
        Insert: {
          created_at?: string
          fc_amount?: number | null
          id?: string
          kind: string
          note?: string | null
          purchase_id?: string | null
          ton_amount?: number | null
          user_id?: string | null
        }
        Update: {
          created_at?: string
          fc_amount?: number | null
          id?: string
          kind?: string
          note?: string | null
          purchase_id?: string | null
          ton_amount?: number | null
          user_id?: string | null
        }
        Relationships: []
      }
      sovereign_pack_purchases: {
        Row: {
          bonus_percent_snapshot: number
          confirmed_at: string | null
          created_at: string
          delivered_at: string | null
          delivery: Json | null
          expected_nanoton: string
          expires_at: string
          fc_snapshot: number
          id: string
          idempotency_key: string | null
          package_version: string
          payment_address: string | null
          payment_comment: string | null
          payment_method: string
          price_ton: number
          reward_configuration_version: number
          status: string
          telegram_id: number | null
          tx_hash: string | null
          user_id: string
        }
        Insert: {
          bonus_percent_snapshot?: number
          confirmed_at?: string | null
          created_at?: string
          delivered_at?: string | null
          delivery?: Json | null
          expected_nanoton: string
          expires_at?: string
          fc_snapshot?: number
          id?: string
          idempotency_key?: string | null
          package_version: string
          payment_address?: string | null
          payment_comment?: string | null
          payment_method?: string
          price_ton: number
          reward_configuration_version?: number
          status?: string
          telegram_id?: number | null
          tx_hash?: string | null
          user_id: string
        }
        Update: {
          bonus_percent_snapshot?: number
          confirmed_at?: string | null
          created_at?: string
          delivered_at?: string | null
          delivery?: Json | null
          expected_nanoton?: string
          expires_at?: string
          fc_snapshot?: number
          id?: string
          idempotency_key?: string | null
          package_version?: string
          payment_address?: string | null
          payment_comment?: string | null
          payment_method?: string
          price_ton?: number
          reward_configuration_version?: number
          status?: string
          telegram_id?: number | null
          tx_hash?: string | null
          user_id?: string
        }
        Relationships: []
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
      spending_event_entries: {
        Row: {
          conversion_rate_fc: number
          created_at: string
          currency: string
          event_id: string
          id: string
          is_reversal: boolean
          original_amount: number
          source_transaction_id: string
          source_type: string
          spending_points: number
          user_id: string
        }
        Insert: {
          conversion_rate_fc?: number
          created_at?: string
          currency: string
          event_id: string
          id?: string
          is_reversal?: boolean
          original_amount?: number
          source_transaction_id: string
          source_type: string
          spending_points?: number
          user_id: string
        }
        Update: {
          conversion_rate_fc?: number
          created_at?: string
          currency?: string
          event_id?: string
          id?: string
          is_reversal?: boolean
          original_amount?: number
          source_transaction_id?: string
          source_type?: string
          spending_points?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "spending_event_entries_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "spending_events"
            referencedColumns: ["id"]
          },
        ]
      }
      spending_event_popup_views: {
        Row: {
          created_at: string
          event_id: string
          first_seen_at: string
          id: string
          last_seen_at: string
          times_seen: number
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          event_id: string
          first_seen_at?: string
          id?: string
          last_seen_at?: string
          times_seen?: number
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          event_id?: string
          first_seen_at?: string
          id?: string
          last_seen_at?: string
          times_seen?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "spending_event_popup_views_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "spending_events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "spending_event_popup_views_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      spending_event_results: {
        Row: {
          created_at: string
          event_id: string
          final_points: number
          final_rank: number
          id: string
          reward_json: Json
          reward_status: string
          reward_ton: number
          user_id: string
        }
        Insert: {
          created_at?: string
          event_id: string
          final_points?: number
          final_rank: number
          id?: string
          reward_json?: Json
          reward_status?: string
          reward_ton?: number
          user_id: string
        }
        Update: {
          created_at?: string
          event_id?: string
          final_points?: number
          final_rank?: number
          id?: string
          reward_json?: Json
          reward_status?: string
          reward_ton?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "spending_event_results_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "spending_events"
            referencedColumns: ["id"]
          },
        ]
      }
      spending_event_rewards: {
        Row: {
          created_at: string
          event_id: string | null
          id: string
          items: Json
          label: string
          position_from: number
          position_to: number
          updated_at: string
        }
        Insert: {
          created_at?: string
          event_id?: string | null
          id?: string
          items?: Json
          label: string
          position_from: number
          position_to: number
          updated_at?: string
        }
        Update: {
          created_at?: string
          event_id?: string | null
          id?: string
          items?: Json
          label?: string
          position_from?: number
          position_to?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "spending_event_rewards_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "spending_events"
            referencedColumns: ["id"]
          },
        ]
      }
      spending_event_scores: {
        Row: {
          event_id: string
          fc_points: number
          fc_spent: number
          score_reached_at: string
          ton_points: number
          ton_spent: number
          total_points: number
          updated_at: string
          user_id: string
        }
        Insert: {
          event_id: string
          fc_points?: number
          fc_spent?: number
          score_reached_at?: string
          ton_points?: number
          ton_spent?: number
          total_points?: number
          updated_at?: string
          user_id: string
        }
        Update: {
          event_id?: string
          fc_points?: number
          fc_spent?: number
          score_reached_at?: string
          ton_points?: number
          ton_spent?: number
          total_points?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "spending_event_scores_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "spending_events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "spending_event_scores_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      spending_event_ticker: {
        Row: {
          event_id: string
          participants: number
          total_fc: number
          total_points: number
          total_ton: number
          updated_at: string
        }
        Insert: {
          event_id: string
          participants?: number
          total_fc?: number
          total_points?: number
          total_ton?: number
          updated_at?: string
        }
        Update: {
          event_id?: string
          participants?: number
          total_fc?: number
          total_points?: number
          total_ton?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "spending_event_ticker_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: true
            referencedRelation: "spending_events"
            referencedColumns: ["id"]
          },
        ]
      }
      spending_events: {
        Row: {
          created_at: string
          ends_at: string
          id: string
          name: string
          starts_at: string
          status: string
          ton_rate_fc: number
          top_limit: number
          updated_at: string
        }
        Insert: {
          created_at?: string
          ends_at?: string
          id?: string
          name?: string
          starts_at?: string
          status?: string
          ton_rate_fc?: number
          top_limit?: number
          updated_at?: string
        }
        Update: {
          created_at?: string
          ends_at?: string
          id?: string
          name?: string
          starts_at?: string
          status?: string
          ton_rate_fc?: number
          top_limit?: number
          updated_at?: string
        }
        Relationships: []
      }
      sub_nft_templates: {
        Row: {
          appearance_family: string | null
          code: string
          created_at: string
          description: string | null
          element: string
          enabled: boolean
          id: string
          image_url: string
          name: string
          pet_template_id: string | null
          secondary_element: string | null
          updated_at: string
        }
        Insert: {
          appearance_family?: string | null
          code: string
          created_at?: string
          description?: string | null
          element: string
          enabled?: boolean
          id?: string
          image_url: string
          name: string
          pet_template_id?: string | null
          secondary_element?: string | null
          updated_at?: string
        }
        Update: {
          appearance_family?: string | null
          code?: string
          created_at?: string
          description?: string | null
          element?: string
          enabled?: boolean
          id?: string
          image_url?: string
          name?: string
          pet_template_id?: string | null
          secondary_element?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "sub_nft_templates_pet_template_id_fkey"
            columns: ["pet_template_id"]
            isOneToOne: false
            referencedRelation: "pets"
            referencedColumns: ["id"]
          },
        ]
      }
      sub_nft_traits: {
        Row: {
          code: string
          effect_key: string
          effect_value: number
          enabled: boolean
          name: string
          updated_at: string
          weight: number
        }
        Insert: {
          code: string
          effect_key: string
          effect_value: number
          enabled?: boolean
          name: string
          updated_at?: string
          weight?: number
        }
        Update: {
          code?: string
          effect_key?: string
          effect_value?: number
          enabled?: boolean
          name?: string
          updated_at?: string
          weight?: number
        }
        Relationships: []
      }
      sub_nfts: {
        Row: {
          accrued_at: string
          birth_time: string
          breeding_id: string | null
          created_at: string
          generation: number
          id: string
          lifetime_mined_ton: number
          matures_at: string
          maturity_stage: string
          mining_cap_ton: number
          mining_rate_ton_day: number
          mining_status: string
          owner_user_id: string | null
          parent_a_nft_id: string | null
          parent_b_nft_id: string | null
          player_pet_id: string | null
          serial: number
          template_id: string
          trait_code: string | null
          unclaimed_ton: number
          unique_instance_id: string
          updated_at: string
        }
        Insert: {
          accrued_at?: string
          birth_time?: string
          breeding_id?: string | null
          created_at?: string
          generation?: number
          id?: string
          lifetime_mined_ton?: number
          matures_at: string
          maturity_stage?: string
          mining_cap_ton?: number
          mining_rate_ton_day?: number
          mining_status?: string
          owner_user_id?: string | null
          parent_a_nft_id?: string | null
          parent_b_nft_id?: string | null
          player_pet_id?: string | null
          serial?: number
          template_id: string
          trait_code?: string | null
          unclaimed_ton?: number
          unique_instance_id: string
          updated_at?: string
        }
        Update: {
          accrued_at?: string
          birth_time?: string
          breeding_id?: string | null
          created_at?: string
          generation?: number
          id?: string
          lifetime_mined_ton?: number
          matures_at?: string
          maturity_stage?: string
          mining_cap_ton?: number
          mining_rate_ton_day?: number
          mining_status?: string
          owner_user_id?: string | null
          parent_a_nft_id?: string | null
          parent_b_nft_id?: string | null
          player_pet_id?: string | null
          serial?: number
          template_id?: string
          trait_code?: string | null
          unclaimed_ton?: number
          unique_instance_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "sub_nfts_breeding_id_fkey"
            columns: ["breeding_id"]
            isOneToOne: false
            referencedRelation: "nft_breeding_requests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sub_nfts_owner_user_id_fkey"
            columns: ["owner_user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sub_nfts_parent_a_nft_id_fkey"
            columns: ["parent_a_nft_id"]
            isOneToOne: false
            referencedRelation: "nft_pets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sub_nfts_parent_b_nft_id_fkey"
            columns: ["parent_b_nft_id"]
            isOneToOne: false
            referencedRelation: "nft_pets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sub_nfts_player_pet_id_fkey"
            columns: ["player_pet_id"]
            isOneToOne: false
            referencedRelation: "player_pets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sub_nfts_template_id_fkey"
            columns: ["template_id"]
            isOneToOne: false
            referencedRelation: "sub_nft_templates"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sub_nfts_trait_code_fkey"
            columns: ["trait_code"]
            isOneToOne: false
            referencedRelation: "sub_nft_traits"
            referencedColumns: ["code"]
          },
        ]
      }
      tactical_actions: {
        Row: {
          auto: boolean
          client_key: string | null
          created_at: string
          id: string
          match_id: string
          side: string
          skill_key: string
          target_uid: string | null
          turn: number
          user_id: string | null
        }
        Insert: {
          auto?: boolean
          client_key?: string | null
          created_at?: string
          id?: string
          match_id: string
          side: string
          skill_key: string
          target_uid?: string | null
          turn: number
          user_id?: string | null
        }
        Update: {
          auto?: boolean
          client_key?: string | null
          created_at?: string
          id?: string
          match_id?: string
          side?: string
          skill_key?: string
          target_uid?: string | null
          turn?: number
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "tactical_actions_match_id_fkey"
            columns: ["match_id"]
            isOneToOne: false
            referencedRelation: "tactical_matches"
            referencedColumns: ["id"]
          },
        ]
      }
      tactical_battle_log: {
        Row: {
          created_at: string
          entries: Json
          id: number
          match_id: string
          turn: number
        }
        Insert: {
          created_at?: string
          entries?: Json
          id?: number
          match_id: string
          turn: number
        }
        Update: {
          created_at?: string
          entries?: Json
          id?: number
          match_id?: string
          turn?: number
        }
        Relationships: [
          {
            foreignKeyName: "tactical_battle_log_match_id_fkey"
            columns: ["match_id"]
            isOneToOne: false
            referencedRelation: "tactical_matches"
            referencedColumns: ["id"]
          },
        ]
      }
      tactical_decks: {
        Row: {
          created_at: string
          id: string
          position: number
          skill_key: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          position: number
          skill_key: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          position?: number
          skill_key?: string
          user_id?: string
        }
        Relationships: []
      }
      tactical_matches: {
        Row: {
          a_seen_at: string
          b_seen_at: string
          created_at: string
          damage_scale: number
          finished_at: string | null
          id: string
          is_practice: boolean
          player_a: string
          player_b: string | null
          rating_a: number | null
          rating_a_delta: number | null
          rating_b: number | null
          rating_b_delta: number | null
          seed: string
          stagnant_turns: number
          state: Json
          status: string
          turn: number
          turn_started_at: string
          updated_at: string
          winner_id: string | null
        }
        Insert: {
          a_seen_at?: string
          b_seen_at?: string
          created_at?: string
          damage_scale?: number
          finished_at?: string | null
          id?: string
          is_practice?: boolean
          player_a: string
          player_b?: string | null
          rating_a?: number | null
          rating_a_delta?: number | null
          rating_b?: number | null
          rating_b_delta?: number | null
          seed: string
          stagnant_turns?: number
          state?: Json
          status?: string
          turn?: number
          turn_started_at?: string
          updated_at?: string
          winner_id?: string | null
        }
        Update: {
          a_seen_at?: string
          b_seen_at?: string
          created_at?: string
          damage_scale?: number
          finished_at?: string | null
          id?: string
          is_practice?: boolean
          player_a?: string
          player_b?: string | null
          rating_a?: number | null
          rating_a_delta?: number | null
          rating_b?: number | null
          rating_b_delta?: number | null
          seed?: string
          stagnant_turns?: number
          state?: Json
          status?: string
          turn?: number
          turn_started_at?: string
          updated_at?: string
          winner_id?: string | null
        }
        Relationships: []
      }
      tactical_queue: {
        Row: {
          enqueued_at: string
          match_id: string | null
          rating: number
          status: string
          updated_at: string
          user_id: string
        }
        Insert: {
          enqueued_at?: string
          match_id?: string | null
          rating?: number
          status?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          enqueued_at?: string
          match_id?: string | null
          rating?: number
          status?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      tactical_ratings: {
        Row: {
          best_rating: number
          created_at: string
          last_match_at: string | null
          losses: number
          matches: number
          rating: number
          updated_at: string
          user_id: string
          wins: number
        }
        Insert: {
          best_rating?: number
          created_at?: string
          last_match_at?: string | null
          losses?: number
          matches?: number
          rating?: number
          updated_at?: string
          user_id: string
          wins?: number
        }
        Update: {
          best_rating?: number
          created_at?: string
          last_match_at?: string | null
          losses?: number
          matches?: number
          rating?: number
          updated_at?: string
          user_id?: string
          wins?: number
        }
        Relationships: []
      }
      tactical_skills: {
        Row: {
          cooldown: number
          created_at: string
          duration: number
          effect_config: Json
          enabled: boolean
          hero_class: string
          id: string
          name_key: string
          power_multiplier: number
          skill_key: string
          skill_type: string
          sort_order: number
          target_type: string
          updated_at: string
        }
        Insert: {
          cooldown?: number
          created_at?: string
          duration?: number
          effect_config?: Json
          enabled?: boolean
          hero_class: string
          id?: string
          name_key: string
          power_multiplier?: number
          skill_key: string
          skill_type: string
          sort_order?: number
          target_type: string
          updated_at?: string
        }
        Update: {
          cooldown?: number
          created_at?: string
          duration?: number
          effect_config?: Json
          enabled?: boolean
          hero_class?: string
          id?: string
          name_key?: string
          power_multiplier?: number
          skill_key?: string
          skill_type?: string
          sort_order?: number
          target_type?: string
          updated_at?: string
        }
        Relationships: []
      }
      tactical_teams: {
        Row: {
          created_at: string
          id: string
          player_hero_id: string
          slot: number
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          player_hero_id: string
          slot: number
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          player_hero_id?: string
          slot?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      ton_auto_withdraw_log: {
        Row: {
          amount_ton: number | null
          created_at: string
          error: string | null
          id: string
          status: string
          telegram_id: number | null
          tx_hash: string | null
          withdrawal_id: string | null
        }
        Insert: {
          amount_ton?: number | null
          created_at?: string
          error?: string | null
          id?: string
          status: string
          telegram_id?: number | null
          tx_hash?: string | null
          withdrawal_id?: string | null
        }
        Update: {
          amount_ton?: number | null
          created_at?: string
          error?: string | null
          id?: string
          status?: string
          telegram_id?: number | null
          tx_hash?: string | null
          withdrawal_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ton_auto_withdraw_log_withdrawal_id_fkey"
            columns: ["withdrawal_id"]
            isOneToOne: false
            referencedRelation: "wallet_withdrawals"
            referencedColumns: ["id"]
          },
        ]
      }
      ton_auto_withdraw_settings: {
        Row: {
          batch_size: number
          daily_cap_ton: number
          enabled: boolean
          hot_wallet: string | null
          id: boolean
          last_error: string | null
          last_run_at: string | null
          max_auto_ton: number
          min_auto_ton: number
          per_user_daily_count: number
          per_user_daily_ton: number
          per_user_window_hours: number
          updated_at: string
          worker_key: string | null
        }
        Insert: {
          batch_size?: number
          daily_cap_ton?: number
          enabled?: boolean
          hot_wallet?: string | null
          id?: boolean
          last_error?: string | null
          last_run_at?: string | null
          max_auto_ton?: number
          min_auto_ton?: number
          per_user_daily_count?: number
          per_user_daily_ton?: number
          per_user_window_hours?: number
          updated_at?: string
          worker_key?: string | null
        }
        Update: {
          batch_size?: number
          daily_cap_ton?: number
          enabled?: boolean
          hot_wallet?: string | null
          id?: boolean
          last_error?: string | null
          last_run_at?: string | null
          max_auto_ton?: number
          min_auto_ton?: number
          per_user_daily_count?: number
          per_user_daily_ton?: number
          per_user_window_hours?: number
          updated_at?: string
          worker_key?: string | null
        }
        Relationships: []
      }
      ton_mine_claims: {
        Row: {
          amount_ton: number
          claim_type: string
          created_at: string
          holding_id: string | null
          id: string
          template_id: string | null
          user_id: string
        }
        Insert: {
          amount_ton: number
          claim_type?: string
          created_at?: string
          holding_id?: string | null
          id?: string
          template_id?: string | null
          user_id: string
        }
        Update: {
          amount_ton?: number
          claim_type?: string
          created_at?: string
          holding_id?: string | null
          id?: string
          template_id?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "ton_mine_claims_holding_id_fkey"
            columns: ["holding_id"]
            isOneToOne: false
            referencedRelation: "ton_mine_holdings"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ton_mine_claims_template_id_fkey"
            columns: ["template_id"]
            isOneToOne: false
            referencedRelation: "ton_mine_templates"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ton_mine_claims_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      ton_mine_holdings: {
        Row: {
          active: boolean
          created_at: string
          id: string
          last_accrual_at: string
          paid_ton: number
          purchased_at: string
          stored_ton: number
          template_id: string
          total_claimed_ton: number
          updated_at: string
          user_id: string
        }
        Insert: {
          active?: boolean
          created_at?: string
          id?: string
          last_accrual_at?: string
          paid_ton?: number
          purchased_at?: string
          stored_ton?: number
          template_id: string
          total_claimed_ton?: number
          updated_at?: string
          user_id: string
        }
        Update: {
          active?: boolean
          created_at?: string
          id?: string
          last_accrual_at?: string
          paid_ton?: number
          purchased_at?: string
          stored_ton?: number
          template_id?: string
          total_claimed_ton?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "ton_mine_holdings_template_id_fkey"
            columns: ["template_id"]
            isOneToOne: false
            referencedRelation: "ton_mine_templates"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ton_mine_holdings_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      ton_mine_orders: {
        Row: {
          amount_nano: string
          confirmed_at: string | null
          created_at: string
          delivered_at: string | null
          expires_at: string
          holding_id: string | null
          id: string
          idempotency_key: string | null
          paid_at: string | null
          payment_address: string
          payment_comment: string
          price_ton: number
          status: string
          template_id: string
          tx_hash: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          amount_nano: string
          confirmed_at?: string | null
          created_at?: string
          delivered_at?: string | null
          expires_at?: string
          holding_id?: string | null
          id?: string
          idempotency_key?: string | null
          paid_at?: string | null
          payment_address: string
          payment_comment: string
          price_ton: number
          status?: string
          template_id: string
          tx_hash?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          amount_nano?: string
          confirmed_at?: string | null
          created_at?: string
          delivered_at?: string | null
          expires_at?: string
          holding_id?: string | null
          id?: string
          idempotency_key?: string | null
          paid_at?: string | null
          payment_address?: string
          payment_comment?: string
          price_ton?: number
          status?: string
          template_id?: string
          tx_hash?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "ton_mine_orders_template_id_fkey"
            columns: ["template_id"]
            isOneToOne: false
            referencedRelation: "ton_mine_templates"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ton_mine_orders_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      ton_mine_settings: {
        Row: {
          admin_only: boolean
          allowed_telegram_ids: number[]
          bonus_30_pct: number
          bonus_60_pct: number
          created_at: string
          enabled: boolean
          id: boolean
          loyalty_enabled: boolean
          max_total_per_player: number
          paused: boolean
          payment_ttl_minutes: number
          updated_at: string
        }
        Insert: {
          admin_only?: boolean
          allowed_telegram_ids?: number[]
          bonus_30_pct?: number
          bonus_60_pct?: number
          created_at?: string
          enabled?: boolean
          id?: boolean
          loyalty_enabled?: boolean
          max_total_per_player?: number
          paused?: boolean
          payment_ttl_minutes?: number
          updated_at?: string
        }
        Update: {
          admin_only?: boolean
          allowed_telegram_ids?: number[]
          bonus_30_pct?: number
          bonus_60_pct?: number
          created_at?: string
          enabled?: boolean
          id?: boolean
          loyalty_enabled?: boolean
          max_total_per_player?: number
          paused?: boolean
          payment_ttl_minutes?: number
          updated_at?: string
        }
        Relationships: []
      }
      ton_mine_templates: {
        Row: {
          created_at: string
          daily_ton: number
          description: string
          enabled: boolean
          id: string
          image_url: string | null
          max_per_player: number
          mine_key: string
          name: string
          paused: boolean
          price_ton: number
          sort_order: number
          storage_days: number
          updated_at: string
        }
        Insert: {
          created_at?: string
          daily_ton: number
          description?: string
          enabled?: boolean
          id?: string
          image_url?: string | null
          max_per_player?: number
          mine_key: string
          name: string
          paused?: boolean
          price_ton: number
          sort_order?: number
          storage_days?: number
          updated_at?: string
        }
        Update: {
          created_at?: string
          daily_ton?: number
          description?: string
          enabled?: boolean
          id?: string
          image_url?: string | null
          max_per_player?: number
          mine_key?: string
          name?: string
          paused?: boolean
          price_ton?: number
          sort_order?: number
          storage_days?: number
          updated_at?: string
        }
        Relationships: []
      }
      ton_mining_access: {
        Row: {
          access_type: string
          created_at: string
          expires_at: string | null
          granted_at: string | null
          mining_access_granted_at: string | null
          note: string | null
          revoked_at: string | null
          source: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          access_type?: string
          created_at?: string
          expires_at?: string | null
          granted_at?: string | null
          mining_access_granted_at?: string | null
          note?: string | null
          revoked_at?: string | null
          source?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          access_type?: string
          created_at?: string
          expires_at?: string | null
          granted_at?: string | null
          mining_access_granted_at?: string | null
          note?: string | null
          revoked_at?: string | null
          source?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "ton_mining_access_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      ton_mining_bonus_entitlements: {
        Row: {
          created_at: string
          id: string
          note: string | null
          percent: number
          source: string
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          note?: string | null
          percent?: number
          source: string
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          note?: string | null
          percent?: number
          source?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      ton_mining_bonus_settings: {
        Row: {
          id: boolean
          policy: string
          updated_at: string
        }
        Insert: {
          id?: boolean
          policy?: string
          updated_at?: string
        }
        Update: {
          id?: boolean
          policy?: string
          updated_at?: string
        }
        Relationships: []
      }
      ton_mining_suspended: {
        Row: {
          created_at: string
          note: string | null
          required_pass_ton: number
          user_id: string
        }
        Insert: {
          created_at?: string
          note?: string | null
          required_pass_ton?: number
          user_id: string
        }
        Update: {
          created_at?: string
          note?: string | null
          required_pass_ton?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "ton_mining_suspended_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      ton_mining_v2_cohort: {
        Row: {
          created_at: string
          note: string | null
          user_id: string
        }
        Insert: {
          created_at?: string
          note?: string | null
          user_id: string
        }
        Update: {
          created_at?: string
          note?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "ton_mining_v2_cohort_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
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
      ton_reward_ledger: {
        Row: {
          amount_ton: number
          balance_after: number | null
          created_at: string
          direction: string
          id: string
          note: string | null
          source_id: string | null
          source_type: string
          status: string
          user_id: string
        }
        Insert: {
          amount_ton: number
          balance_after?: number | null
          created_at?: string
          direction: string
          id?: string
          note?: string | null
          source_id?: string | null
          source_type: string
          status?: string
          user_id: string
        }
        Update: {
          amount_ton?: number
          balance_after?: number | null
          created_at?: string
          direction?: string
          id?: string
          note?: string | null
          source_id?: string | null
          source_type?: string
          status?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "ton_reward_ledger_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      ton_staking_idempotency: {
        Row: {
          created_at: string
          key: string
          result: Json
          user_id: string | null
        }
        Insert: {
          created_at?: string
          key: string
          result: Json
          user_id?: string | null
        }
        Update: {
          created_at?: string
          key?: string
          result?: Json
          user_id?: string | null
        }
        Relationships: []
      }
      ton_staking_ledger: {
        Row: {
          amount_ton: number
          created_at: string
          entry_type: string
          id: string
          note: string | null
          position_id: string | null
          request_id: string | null
          source: string | null
          user_id: string
        }
        Insert: {
          amount_ton?: number
          created_at?: string
          entry_type: string
          id?: string
          note?: string | null
          position_id?: string | null
          request_id?: string | null
          source?: string | null
          user_id: string
        }
        Update: {
          amount_ton?: number
          created_at?: string
          entry_type?: string
          id?: string
          note?: string | null
          position_id?: string | null
          request_id?: string | null
          source?: string | null
          user_id?: string
        }
        Relationships: []
      }
      ton_staking_plans: {
        Row: {
          auto_compound_allowed: boolean
          bonus_rate: number
          code: string
          created_at: string
          early_unstake_allowed: boolean
          enabled: boolean
          id: string
          lock_days: number
          max_stake_ton: number
          min_stake_ton: number
          monthly_rate: number
          name: string
          reward_claim_mode: string
          sort_order: number
          updated_at: string
        }
        Insert: {
          auto_compound_allowed?: boolean
          bonus_rate?: number
          code: string
          created_at?: string
          early_unstake_allowed?: boolean
          enabled?: boolean
          id?: string
          lock_days: number
          max_stake_ton?: number
          min_stake_ton?: number
          monthly_rate?: number
          name: string
          reward_claim_mode?: string
          sort_order?: number
          updated_at?: string
        }
        Update: {
          auto_compound_allowed?: boolean
          bonus_rate?: number
          code?: string
          created_at?: string
          early_unstake_allowed?: boolean
          enabled?: boolean
          id?: string
          lock_days?: number
          max_stake_ton?: number
          min_stake_ton?: number
          monthly_rate?: number
          name?: string
          reward_claim_mode?: string
          sort_order?: number
          updated_at?: string
        }
        Relationships: []
      }
      ton_staking_positions: {
        Row: {
          accrued_reward_ton: number
          auto_compound: boolean
          bonus_snapshot: number
          claim_mode_snapshot: string
          claimed_reward_ton: number
          compounded_ton: number
          created_at: string
          id: string
          initial_principal_ton: number
          last_accrual_at: string
          lock_days_snapshot: number
          plan_id: string
          principal_ton: number
          rate_snapshot: number
          source: string
          started_at: string
          status: string
          total_earned_ton: number
          unlock_at: string
          updated_at: string
          user_id: string
          withdrawn_at: string | null
        }
        Insert: {
          accrued_reward_ton?: number
          auto_compound?: boolean
          bonus_snapshot?: number
          claim_mode_snapshot?: string
          claimed_reward_ton?: number
          compounded_ton?: number
          created_at?: string
          id?: string
          initial_principal_ton: number
          last_accrual_at?: string
          lock_days_snapshot: number
          plan_id: string
          principal_ton: number
          rate_snapshot: number
          source?: string
          started_at?: string
          status?: string
          total_earned_ton?: number
          unlock_at: string
          updated_at?: string
          user_id: string
          withdrawn_at?: string | null
        }
        Update: {
          accrued_reward_ton?: number
          auto_compound?: boolean
          bonus_snapshot?: number
          claim_mode_snapshot?: string
          claimed_reward_ton?: number
          compounded_ton?: number
          created_at?: string
          id?: string
          initial_principal_ton?: number
          last_accrual_at?: string
          lock_days_snapshot?: number
          plan_id?: string
          principal_ton?: number
          rate_snapshot?: number
          source?: string
          started_at?: string
          status?: string
          total_earned_ton?: number
          unlock_at?: string
          updated_at?: string
          user_id?: string
          withdrawn_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ton_staking_positions_plan_id_fkey"
            columns: ["plan_id"]
            isOneToOne: false
            referencedRelation: "ton_staking_plans"
            referencedColumns: ["id"]
          },
        ]
      }
      ton_staking_preferences: {
        Row: {
          auto_compound: boolean
          auto_stake_plan_id: string | null
          mine_auto_stake_enabled: boolean
          mine_auto_stake_percent: number
          pending_auto_stake_ton: number
          updated_at: string
          user_id: string
        }
        Insert: {
          auto_compound?: boolean
          auto_stake_plan_id?: string | null
          mine_auto_stake_enabled?: boolean
          mine_auto_stake_percent?: number
          pending_auto_stake_ton?: number
          updated_at?: string
          user_id: string
        }
        Update: {
          auto_compound?: boolean
          auto_stake_plan_id?: string | null
          mine_auto_stake_enabled?: boolean
          mine_auto_stake_percent?: number
          pending_auto_stake_ton?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "ton_staking_preferences_auto_stake_plan_id_fkey"
            columns: ["auto_stake_plan_id"]
            isOneToOne: false
            referencedRelation: "ton_staking_plans"
            referencedColumns: ["id"]
          },
        ]
      }
      ton_staking_settings: {
        Row: {
          accrue_after_maturity: boolean
          allowed_percents: number[]
          auto_compound_allowed: boolean
          auto_stake_min_ton: number
          early_unstake_allowed: boolean
          early_unstake_penalty_percent: number
          early_unstake_reward_forfeit_percent: number
          enabled: boolean
          id: boolean
          max_stake_ton: number
          min_stake_ton: number
          month_days: number
          paused: boolean
          pool_gate_enabled: boolean
          reward_pool_min_available: number
          reward_pool_paid: number
          reward_pool_total: number
          updated_at: string
        }
        Insert: {
          accrue_after_maturity?: boolean
          allowed_percents?: number[]
          auto_compound_allowed?: boolean
          auto_stake_min_ton?: number
          early_unstake_allowed?: boolean
          early_unstake_penalty_percent?: number
          early_unstake_reward_forfeit_percent?: number
          enabled?: boolean
          id?: boolean
          max_stake_ton?: number
          min_stake_ton?: number
          month_days?: number
          paused?: boolean
          pool_gate_enabled?: boolean
          reward_pool_min_available?: number
          reward_pool_paid?: number
          reward_pool_total?: number
          updated_at?: string
        }
        Update: {
          accrue_after_maturity?: boolean
          allowed_percents?: number[]
          auto_compound_allowed?: boolean
          auto_stake_min_ton?: number
          early_unstake_allowed?: boolean
          early_unstake_penalty_percent?: number
          early_unstake_reward_forfeit_percent?: number
          enabled?: boolean
          id?: boolean
          max_stake_ton?: number
          min_stake_ton?: number
          month_days?: number
          paused?: boolean
          pool_gate_enabled?: boolean
          reward_pool_min_available?: number
          reward_pool_paid?: number
          reward_pool_total?: number
          updated_at?: string
        }
        Relationships: []
      }
      tower_bosses: {
        Row: {
          base_atk: number
          base_def: number
          base_hp: number
          base_speed: number
          behavior: string
          boss_key: string
          created_at: string
          floor_index: number
          id: string
          name: string
          role: string
          theme: string
          updated_at: string
        }
        Insert: {
          base_atk?: number
          base_def?: number
          base_hp?: number
          base_speed?: number
          behavior?: string
          boss_key: string
          created_at?: string
          floor_index: number
          id?: string
          name: string
          role?: string
          theme?: string
          updated_at?: string
        }
        Update: {
          base_atk?: number
          base_def?: number
          base_hp?: number
          base_speed?: number
          behavior?: string
          boss_key?: string
          created_at?: string
          floor_index?: number
          id?: string
          name?: string
          role?: string
          theme?: string
          updated_at?: string
        }
        Relationships: []
      }
      tower_equipment_drops: {
        Row: {
          created_at: string
          floor: number
          id: string
          instance_id: string | null
          rarity: string | null
          slot: string | null
          template_id: string | null
          user_id: string
        }
        Insert: {
          created_at?: string
          floor: number
          id?: string
          instance_id?: string | null
          rarity?: string | null
          slot?: string | null
          template_id?: string | null
          user_id: string
        }
        Update: {
          created_at?: string
          floor?: number
          id?: string
          instance_id?: string | null
          rarity?: string | null
          slot?: string | null
          template_id?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "tower_equipment_drops_instance_id_fkey"
            columns: ["instance_id"]
            isOneToOne: false
            referencedRelation: "player_equipment"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tower_equipment_drops_template_id_fkey"
            columns: ["template_id"]
            isOneToOne: false
            referencedRelation: "equipment_templates"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tower_equipment_drops_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      tower_key_catalog: {
        Row: {
          code: string
          created_at: string
          description: string
          image_url: string | null
          name: string
          rarity: string
          sort_order: number
        }
        Insert: {
          code: string
          created_at?: string
          description?: string
          image_url?: string | null
          name: string
          rarity: string
          sort_order?: number
        }
        Update: {
          code?: string
          created_at?: string
          description?: string
          image_url?: string | null
          name?: string
          rarity?: string
          sort_order?: number
        }
        Relationships: []
      }
      tower_key_purchases: {
        Row: {
          confirmed_at: string | null
          created_at: string
          delivered_at: string | null
          expected_nanoton: string
          expires_at: string
          id: string
          idempotency_key: string | null
          key_code: string
          payment_address: string | null
          payment_comment: string | null
          payment_method: string
          price_ton: number
          quantity: number
          status: string
          telegram_id: number
          tx_hash: string | null
          user_id: string
        }
        Insert: {
          confirmed_at?: string | null
          created_at?: string
          delivered_at?: string | null
          expected_nanoton: string
          expires_at?: string
          id?: string
          idempotency_key?: string | null
          key_code: string
          payment_address?: string | null
          payment_comment?: string | null
          payment_method?: string
          price_ton: number
          quantity?: number
          status?: string
          telegram_id: number
          tx_hash?: string | null
          user_id: string
        }
        Update: {
          confirmed_at?: string | null
          created_at?: string
          delivered_at?: string | null
          expected_nanoton?: string
          expires_at?: string
          id?: string
          idempotency_key?: string | null
          key_code?: string
          payment_address?: string | null
          payment_comment?: string | null
          payment_method?: string
          price_ton?: number
          quantity?: number
          status?: string
          telegram_id?: number
          tx_hash?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "tower_key_purchases_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      tower_key_shop_config: {
        Row: {
          enabled: boolean
          key_code: string
          price_ton: number
          updated_at: string
        }
        Insert: {
          enabled?: boolean
          key_code: string
          price_ton: number
          updated_at?: string
        }
        Update: {
          enabled?: boolean
          key_code?: string
          price_ton?: number
          updated_at?: string
        }
        Relationships: []
      }
      tower_progress: {
        Row: {
          attempts_date: string
          attempts_used: number
          created_at: string
          current_floor: number
          highest_floor: number
          updated_at: string
          user_id: string
        }
        Insert: {
          attempts_date?: string
          attempts_used?: number
          created_at?: string
          current_floor?: number
          highest_floor?: number
          updated_at?: string
          user_id: string
        }
        Update: {
          attempts_date?: string
          attempts_used?: number
          created_at?: string
          current_floor?: number
          highest_floor?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "tower_progress_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      tower_runs: {
        Row: {
          boss_key: string
          cost_fc: number
          created_at: string
          first_clear: boolean
          floor: number
          id: string
          result: string
          rewards: Json
          turns: number
          user_id: string
        }
        Insert: {
          boss_key: string
          cost_fc?: number
          created_at?: string
          first_clear?: boolean
          floor: number
          id?: string
          result: string
          rewards?: Json
          turns?: number
          user_id: string
        }
        Update: {
          boss_key?: string
          cost_fc?: number
          created_at?: string
          first_clear?: boolean
          floor?: number
          id?: string
          result?: string
          rewards?: Json
          turns?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "tower_runs_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      tower_team_slots: {
        Row: {
          created_at: string
          hero_id: string
          id: string
          slot: number
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          hero_id: string
          id?: string
          slot: number
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          hero_id?: string
          id?: string
          slot?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "tower_team_slots_hero_id_fkey"
            columns: ["hero_id"]
            isOneToOne: false
            referencedRelation: "player_heroes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tower_team_slots_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      user_campaign_popup: {
        Row: {
          campaign_id: string
          clicked_join_at: string | null
          created_at: string
          dismissed_at: string | null
          id: string
          shown_at: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          campaign_id: string
          clicked_join_at?: string | null
          created_at?: string
          dismissed_at?: string | null
          id?: string
          shown_at?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          campaign_id?: string
          clicked_join_at?: string | null
          created_at?: string
          dismissed_at?: string | null
          id?: string
          shown_at?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_campaign_popup_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
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
      vanguard_pack_config: {
        Row: {
          account_ton_bonus_percent: number
          enabled: boolean
          ends_at: string | null
          fc_reward: number
          grant_pass_tier: string
          hero_rarity: string
          id: boolean
          legendary_armors: number
          legendary_chests: number
          lock_mining_after_reveal: boolean
          max_reward_rarity: string
          mythic_chests: number
          nft_weapons: number
          package_version: string
          popup_enabled: boolean
          popup_frequency: string
          popup_priority: number
          price_ton: number
          purchase_limit: number
          random_items: number
          random_items_pool: Json
          reward_configuration_version: number
          sales_paused: boolean
          sold_out_visible: boolean
          start_at: string | null
          stock_total: number | null
          updated_at: string
        }
        Insert: {
          account_ton_bonus_percent?: number
          enabled?: boolean
          ends_at?: string | null
          fc_reward?: number
          grant_pass_tier?: string
          hero_rarity?: string
          id?: boolean
          legendary_armors?: number
          legendary_chests?: number
          lock_mining_after_reveal?: boolean
          max_reward_rarity?: string
          mythic_chests?: number
          nft_weapons?: number
          package_version?: string
          popup_enabled?: boolean
          popup_frequency?: string
          popup_priority?: number
          price_ton?: number
          purchase_limit?: number
          random_items?: number
          random_items_pool?: Json
          reward_configuration_version?: number
          sales_paused?: boolean
          sold_out_visible?: boolean
          start_at?: string | null
          stock_total?: number | null
          updated_at?: string
        }
        Update: {
          account_ton_bonus_percent?: number
          enabled?: boolean
          ends_at?: string | null
          fc_reward?: number
          grant_pass_tier?: string
          hero_rarity?: string
          id?: boolean
          legendary_armors?: number
          legendary_chests?: number
          lock_mining_after_reveal?: boolean
          max_reward_rarity?: string
          mythic_chests?: number
          nft_weapons?: number
          package_version?: string
          popup_enabled?: boolean
          popup_frequency?: string
          popup_priority?: number
          price_ton?: number
          purchase_limit?: number
          random_items?: number
          random_items_pool?: Json
          reward_configuration_version?: number
          sales_paused?: boolean
          sold_out_visible?: boolean
          start_at?: string | null
          stock_total?: number | null
          updated_at?: string
        }
        Relationships: []
      }
      vanguard_pack_items: {
        Row: {
          created_at: string
          id: string
          instance_id: string | null
          item_type: string
          mining_locked: boolean
          mining_pending_reveal: boolean
          purchase_id: string
          quantity: number
          rarity: string | null
          revealed_at: string | null
          revealed_myth: number | null
          revealed_ton: number | null
          template_id: string | null
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          instance_id?: string | null
          item_type: string
          mining_locked?: boolean
          mining_pending_reveal?: boolean
          purchase_id: string
          quantity?: number
          rarity?: string | null
          revealed_at?: string | null
          revealed_myth?: number | null
          revealed_ton?: number | null
          template_id?: string | null
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          instance_id?: string | null
          item_type?: string
          mining_locked?: boolean
          mining_pending_reveal?: boolean
          purchase_id?: string
          quantity?: number
          rarity?: string | null
          revealed_at?: string | null
          revealed_myth?: number | null
          revealed_ton?: number | null
          template_id?: string | null
          user_id?: string
        }
        Relationships: []
      }
      vanguard_pack_ledger: {
        Row: {
          created_at: string
          fc_amount: number | null
          id: string
          kind: string
          note: string | null
          purchase_id: string | null
          ton_amount: number | null
          user_id: string | null
        }
        Insert: {
          created_at?: string
          fc_amount?: number | null
          id?: string
          kind: string
          note?: string | null
          purchase_id?: string | null
          ton_amount?: number | null
          user_id?: string | null
        }
        Update: {
          created_at?: string
          fc_amount?: number | null
          id?: string
          kind?: string
          note?: string | null
          purchase_id?: string | null
          ton_amount?: number | null
          user_id?: string | null
        }
        Relationships: []
      }
      vanguard_pack_purchases: {
        Row: {
          bonus_percent_snapshot: number
          confirmed_at: string | null
          created_at: string
          delivered_at: string | null
          delivery: Json | null
          expected_nanoton: string
          expires_at: string
          fc_snapshot: number
          fulfillment_error: string | null
          id: string
          idempotency_key: string | null
          package_version: string
          pass_tier_snapshot: string
          payment_address: string | null
          payment_comment: string | null
          payment_method: string
          price_ton: number
          reward_configuration_version: number
          status: string
          telegram_id: number | null
          tx_hash: string | null
          user_id: string
        }
        Insert: {
          bonus_percent_snapshot?: number
          confirmed_at?: string | null
          created_at?: string
          delivered_at?: string | null
          delivery?: Json | null
          expected_nanoton: string
          expires_at?: string
          fc_snapshot?: number
          fulfillment_error?: string | null
          id?: string
          idempotency_key?: string | null
          package_version: string
          pass_tier_snapshot?: string
          payment_address?: string | null
          payment_comment?: string | null
          payment_method?: string
          price_ton: number
          reward_configuration_version?: number
          status?: string
          telegram_id?: number | null
          tx_hash?: string | null
          user_id: string
        }
        Update: {
          bonus_percent_snapshot?: number
          confirmed_at?: string | null
          created_at?: string
          delivered_at?: string | null
          delivery?: Json | null
          expected_nanoton?: string
          expires_at?: string
          fc_snapshot?: number
          fulfillment_error?: string | null
          id?: string
          idempotency_key?: string | null
          package_version?: string
          pass_tier_snapshot?: string
          payment_address?: string | null
          payment_comment?: string | null
          payment_method?: string
          price_ton?: number
          reward_configuration_version?: number
          status?: string
          telegram_id?: number | null
          tx_hash?: string | null
          user_id?: string
        }
        Relationships: []
      }
      vanguard_pack_reveal_audit: {
        Row: {
          admin_id: number
          id: string
          item_id: string
          item_instance_id: string | null
          item_type: string
          new_myth: number | null
          new_ton: number | null
          old_myth: number | null
          old_ton: number | null
          override: boolean
          purchase_id: string | null
          reason: string | null
          revealed_at: string
          user_id: string
        }
        Insert: {
          admin_id: number
          id?: string
          item_id: string
          item_instance_id?: string | null
          item_type: string
          new_myth?: number | null
          new_ton?: number | null
          old_myth?: number | null
          old_ton?: number | null
          override?: boolean
          purchase_id?: string | null
          reason?: string | null
          revealed_at?: string
          user_id: string
        }
        Update: {
          admin_id?: number
          id?: string
          item_id?: string
          item_instance_id?: string | null
          item_type?: string
          new_myth?: number | null
          new_ton?: number | null
          old_myth?: number | null
          old_ton?: number | null
          override?: boolean
          purchase_id?: string | null
          reason?: string | null
          revealed_at?: string
          user_id?: string
        }
        Relationships: []
      }
      veteran_myth_pools: {
        Row: {
          id: boolean
          mining_distributed: number
          mining_funded: number
          reward_distributed: number
          reward_funded: number
          updated_at: string
        }
        Insert: {
          id?: boolean
          mining_distributed?: number
          mining_funded?: number
          reward_distributed?: number
          reward_funded?: number
          updated_at?: string
        }
        Update: {
          id?: boolean
          mining_distributed?: number
          mining_funded?: number
          reward_distributed?: number
          reward_funded?: number
          updated_at?: string
        }
        Relationships: []
      }
      veteran_vault_claims: {
        Row: {
          created_at: string
          id: string
          myth_amount: number
          payload: Json
          purchase_id: string
          reward_day: number
          reward_type: string
          ton_amount: number
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          myth_amount?: number
          payload?: Json
          purchase_id: string
          reward_day: number
          reward_type: string
          ton_amount?: number
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          myth_amount?: number
          payload?: Json
          purchase_id?: string
          reward_day?: number
          reward_type?: string
          ton_amount?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "veteran_vault_claims_purchase_id_fkey"
            columns: ["purchase_id"]
            isOneToOne: false
            referencedRelation: "veteran_vault_purchases"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "veteran_vault_claims_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      veteran_vault_config: {
        Row: {
          badge_enabled: boolean
          cycle_days: number
          daily_myth: number
          enabled: boolean
          equipment_chest_code: string
          final_reward: Json
          fragments: number
          frame_enabled: boolean
          hero_key: string | null
          id: boolean
          initial_myth: number
          launch_at: string
          max_ton_reward: number
          min_account_age_days: number
          pass_tier: string
          pet_slug: string | null
          price_ton: number
          reference_values: Json
          resource_chest_code: string
          resource_chest_qty: number
          reward_schedule: Json
          sales_paused: boolean
          target_reference_ton: number
          updated_at: string
          vault_version: string
        }
        Insert: {
          badge_enabled?: boolean
          cycle_days?: number
          daily_myth?: number
          enabled?: boolean
          equipment_chest_code?: string
          final_reward?: Json
          fragments?: number
          frame_enabled?: boolean
          hero_key?: string | null
          id?: boolean
          initial_myth?: number
          launch_at?: string
          max_ton_reward?: number
          min_account_age_days?: number
          pass_tier?: string
          pet_slug?: string | null
          price_ton?: number
          reference_values?: Json
          resource_chest_code?: string
          resource_chest_qty?: number
          reward_schedule?: Json
          sales_paused?: boolean
          target_reference_ton?: number
          updated_at?: string
          vault_version?: string
        }
        Update: {
          badge_enabled?: boolean
          cycle_days?: number
          daily_myth?: number
          enabled?: boolean
          equipment_chest_code?: string
          final_reward?: Json
          fragments?: number
          frame_enabled?: boolean
          hero_key?: string | null
          id?: boolean
          initial_myth?: number
          launch_at?: string
          max_ton_reward?: number
          min_account_age_days?: number
          pass_tier?: string
          pet_slug?: string | null
          price_ton?: number
          reference_values?: Json
          resource_chest_code?: string
          resource_chest_qty?: number
          reward_schedule?: Json
          sales_paused?: boolean
          target_reference_ton?: number
          updated_at?: string
          vault_version?: string
        }
        Relationships: []
      }
      veteran_vault_ledger: {
        Row: {
          created_at: string
          id: string
          kind: string
          myth_amount: number
          note: string | null
          purchase_id: string | null
          ton_amount: number
          user_id: string | null
        }
        Insert: {
          created_at?: string
          id?: string
          kind: string
          myth_amount?: number
          note?: string | null
          purchase_id?: string | null
          ton_amount?: number
          user_id?: string | null
        }
        Update: {
          created_at?: string
          id?: string
          kind?: string
          myth_amount?: number
          note?: string | null
          purchase_id?: string | null
          ton_amount?: number
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "veteran_vault_ledger_purchase_id_fkey"
            columns: ["purchase_id"]
            isOneToOne: false
            referencedRelation: "veteran_vault_purchases"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "veteran_vault_ledger_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      veteran_vault_pool: {
        Row: {
          id: boolean
          myth_distributed: number
          myth_funded: number
          myth_reserved: number
          ton_distributed: number
          ton_funded: number
          ton_reserved: number
          updated_at: string
        }
        Insert: {
          id?: boolean
          myth_distributed?: number
          myth_funded?: number
          myth_reserved?: number
          ton_distributed?: number
          ton_funded?: number
          ton_reserved?: number
          updated_at?: string
        }
        Update: {
          id?: boolean
          myth_distributed?: number
          myth_funded?: number
          myth_reserved?: number
          ton_distributed?: number
          ton_funded?: number
          ton_reserved?: number
          updated_at?: string
        }
        Relationships: []
      }
      veteran_vault_purchases: {
        Row: {
          amount_nano: string
          completed_at: string | null
          confirmed_at: string | null
          created_at: string
          cycle_end_at: string | null
          cycle_start_at: string | null
          delivery: Json | null
          expires_at: string
          id: string
          idempotency_key: string | null
          myth_distributed: number
          myth_reserved: number
          payment_address: string | null
          payment_comment: string | null
          payment_method: string
          price_ton: number
          reward_snapshot: Json
          settled_at: string | null
          status: string
          telegram_id: number
          ton_distributed: number
          ton_reserved: number
          tx_hash: string | null
          user_id: string
          vault_version: string
        }
        Insert: {
          amount_nano: string
          completed_at?: string | null
          confirmed_at?: string | null
          created_at?: string
          cycle_end_at?: string | null
          cycle_start_at?: string | null
          delivery?: Json | null
          expires_at?: string
          id?: string
          idempotency_key?: string | null
          myth_distributed?: number
          myth_reserved?: number
          payment_address?: string | null
          payment_comment?: string | null
          payment_method?: string
          price_ton: number
          reward_snapshot?: Json
          settled_at?: string | null
          status?: string
          telegram_id: number
          ton_distributed?: number
          ton_reserved?: number
          tx_hash?: string | null
          user_id: string
          vault_version: string
        }
        Update: {
          amount_nano?: string
          completed_at?: string | null
          confirmed_at?: string | null
          created_at?: string
          cycle_end_at?: string | null
          cycle_start_at?: string | null
          delivery?: Json | null
          expires_at?: string
          id?: string
          idempotency_key?: string | null
          myth_distributed?: number
          myth_reserved?: number
          payment_address?: string | null
          payment_comment?: string | null
          payment_method?: string
          price_ton?: number
          reward_snapshot?: Json
          settled_at?: string | null
          status?: string
          telegram_id?: number
          ton_distributed?: number
          ton_reserved?: number
          tx_hash?: string | null
          user_id?: string
          vault_version?: string
        }
        Relationships: [
          {
            foreignKeyName: "veteran_vault_purchases_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      veteran_vault_v2_config: {
        Row: {
          boost_percent: number
          dragon_daily_myth: number
          enabled: boolean
          ends_at: string | null
          fragments: number
          hero_daily_myth: number
          id: boolean
          legendary_chests: number
          myth_reference_rate: number
          myth_reward: number
          package_version: string
          pet_daily_myth: number
          popup_enabled: boolean
          popup_frequency: string
          popup_priority: number
          price_ton: number
          reward_configuration_version: number
          sales_paused: boolean
          start_at: string
          updated_at: string
          weapons_per_purchase: number
        }
        Insert: {
          boost_percent?: number
          dragon_daily_myth?: number
          enabled?: boolean
          ends_at?: string | null
          fragments?: number
          hero_daily_myth?: number
          id?: boolean
          legendary_chests?: number
          myth_reference_rate?: number
          myth_reward?: number
          package_version?: string
          pet_daily_myth?: number
          popup_enabled?: boolean
          popup_frequency?: string
          popup_priority?: number
          price_ton?: number
          reward_configuration_version?: number
          sales_paused?: boolean
          start_at?: string
          updated_at?: string
          weapons_per_purchase?: number
        }
        Update: {
          boost_percent?: number
          dragon_daily_myth?: number
          enabled?: boolean
          ends_at?: string | null
          fragments?: number
          hero_daily_myth?: number
          id?: boolean
          legendary_chests?: number
          myth_reference_rate?: number
          myth_reward?: number
          package_version?: string
          pet_daily_myth?: number
          popup_enabled?: boolean
          popup_frequency?: string
          popup_priority?: number
          price_ton?: number
          reward_configuration_version?: number
          sales_paused?: boolean
          start_at?: string
          updated_at?: string
          weapons_per_purchase?: number
        }
        Relationships: []
      }
      veteran_vault_v2_items: {
        Row: {
          created_at: string
          id: string
          instance_id: string | null
          item_type: string
          purchase_id: string
          source: string
          template_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          instance_id?: string | null
          item_type: string
          purchase_id: string
          source?: string
          template_id: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          instance_id?: string | null
          item_type?: string
          purchase_id?: string
          source?: string
          template_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "veteran_vault_v2_items_purchase_id_fkey"
            columns: ["purchase_id"]
            isOneToOne: false
            referencedRelation: "veteran_vault_v2_purchases"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "veteran_vault_v2_items_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      veteran_vault_v2_ledger: {
        Row: {
          created_at: string
          id: string
          kind: string
          myth_amount: number
          note: string | null
          purchase_id: string | null
          ton_amount: number
          user_id: string | null
        }
        Insert: {
          created_at?: string
          id?: string
          kind: string
          myth_amount?: number
          note?: string | null
          purchase_id?: string | null
          ton_amount?: number
          user_id?: string | null
        }
        Update: {
          created_at?: string
          id?: string
          kind?: string
          myth_amount?: number
          note?: string | null
          purchase_id?: string | null
          ton_amount?: number
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "veteran_vault_v2_ledger_purchase_id_fkey"
            columns: ["purchase_id"]
            isOneToOne: false
            referencedRelation: "veteran_vault_v2_purchases"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "veteran_vault_v2_ledger_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "game_players"
            referencedColumns: ["id"]
          },
        ]
      }
      veteran_vault_v2_purchases: {
        Row: {
          boost_percent_snapshot: number
          confirmed_at: string | null
          created_at: string
          delivered_at: string | null
          delivery: Json | null
          expected_nanoton: string
          expires_at: string
          id: string
          idempotency_key: string | null
          myth_reward_snapshot: number
          package_version: string
          payment_address: string | null
          payment_comment: string | null
          payment_method: string
          price_ton: number
          reward_configuration_version: number
          reward_snapshot: Json
          status: string
          telegram_id: number
          tx_hash: string | null
          user_id: string
        }
        Insert: {
          boost_percent_snapshot?: number
          confirmed_at?: string | null
          created_at?: string
          delivered_at?: string | null
          delivery?: Json | null
          expected_nanoton: string
          expires_at?: string
          id?: string
          idempotency_key?: string | null
          myth_reward_snapshot?: number
          package_version: string
          payment_address?: string | null
          payment_comment?: string | null
          payment_method?: string
          price_ton: number
          reward_configuration_version?: number
          reward_snapshot?: Json
          status?: string
          telegram_id: number
          tx_hash?: string | null
          user_id: string
        }
        Update: {
          boost_percent_snapshot?: number
          confirmed_at?: string | null
          created_at?: string
          delivered_at?: string | null
          delivery?: Json | null
          expected_nanoton?: string
          expires_at?: string
          id?: string
          idempotency_key?: string | null
          myth_reward_snapshot?: number
          package_version?: string
          payment_address?: string | null
          payment_comment?: string | null
          payment_method?: string
          price_ton?: number
          reward_configuration_version?: number
          reward_snapshot?: Json
          status?: string
          telegram_id?: number
          tx_hash?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "veteran_vault_v2_purchases_user_id_fkey"
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
          deposit_type: string
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
          deposit_type?: string
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
          deposit_type?: string
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
          source: string
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
          source?: string
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
          source?: string
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
      accounts_share_device: {
        Args: { p_a: string; p_b: string }
        Returns: boolean
      }
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
      active_spending_event: {
        Args: never
        Returns: {
          created_at: string
          ends_at: string
          id: string
          name: string
          starts_at: string
          status: string
          ton_rate_fc: number
          top_limit: number
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "spending_events"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      activity_daily_progress: { Args: { p_user_id: string }; Returns: Json }
      activity_rewards_config: { Args: never; Returns: Json }
      ad_reward_begin: { Args: { p_telegram_id: number }; Returns: Json }
      ad_reward_claim: {
        Args: { p_source?: string; p_telegram_id: number; p_view_id?: string }
        Returns: Json
      }
      ad_reward_period_reset_at: { Args: never; Returns: string }
      ad_rewards_state: { Args: { p_user_id: string }; Returns: Json }
      add_universal_fragments: {
        Args: { p_quantity: number; p_user_id: string }
        Returns: number
      }
      admin_ad_rewards_overview: { Args: { p_admin_id: number }; Returns: Json }
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
      admin_adjust_ton_balance: {
        Args: {
          p_admin_id: number
          p_amount: number
          p_idempotency_key: string
          p_operation: string
          p_reason: string
          p_target_telegram_id: number
        }
        Returns: Json
      }
      admin_ads_overview: { Args: { p_admin_id: number }; Returns: Json }
      admin_adventurer_pack_overview: {
        Args: { p_admin_id: number }
        Returns: Json
      }
      admin_adventurer_pack_retry: {
        Args: { p_admin_id: number; p_purchase_id: string }
        Returns: Json
      }
      admin_adventurer_pack_reveal: {
        Args: {
          p_admin_id: number
          p_daily_myth?: number
          p_daily_ton: number
          p_item_id: string
          p_override?: boolean
          p_reason?: string
        }
        Returns: Json
      }
      admin_adventurer_pack_set: {
        Args: { p_admin_id: number; p_field: string; p_value: string }
        Returns: Json
      }
      admin_antifake_allowlist: {
        Args: {
          p_admin_id: number
          p_reason?: string
          p_ref: string
          p_remove?: boolean
        }
        Returns: Json
      }
      admin_antifake_overview: { Args: { p_admin_id: number }; Returns: Json }
      admin_antifake_reviews: {
        Args: { p_admin_id: number; p_limit?: number }
        Returns: Json
      }
      admin_antifake_search: {
        Args: { p_admin_id: number; p_ref: string }
        Returns: Json
      }
      admin_antifake_set_enabled: {
        Args: { p_admin_id: number; p_enabled: boolean; p_limit?: number }
        Returns: Json
      }
      admin_antifake_unblock: {
        Args: { p_admin_id: number; p_reason?: string; p_ref: string }
        Returns: Json
      }
      admin_assert: { Args: { p_admin_id: number }; Returns: undefined }
      admin_auction_overview: { Args: { p_telegram_id: number }; Returns: Json }
      admin_auction_set: {
        Args: { p_key: string; p_telegram_id: number; p_value: Json }
        Returns: Json
      }
      admin_auto_withdraw_overview: {
        Args: { p_admin_id: number }
        Returns: Json
      }
      admin_auto_withdraw_set: {
        Args: { p_admin_id: number; p_field: string; p_value: string }
        Returns: Json
      }
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
      admin_celestial_pack_overview: {
        Args: { p_admin_id: number }
        Returns: Json
      }
      admin_celestial_pack_reveal: {
        Args: {
          p_admin_id: number
          p_daily_myth: number
          p_daily_ton: number
          p_item_id: string
        }
        Returns: Json
      }
      admin_celestial_pack_set: {
        Args: { p_admin_id: number; p_field: string; p_value: string }
        Returns: Json
      }
      admin_channel_rewards_overview: {
        Args: { p_admin_id: number }
        Returns: Json
      }
      admin_channels_overview: { Args: { p_admin_id: number }; Returns: Json }
      admin_check_missing_pass_rewards: {
        Args: { p_limit?: number }
        Returns: Json
      }
      admin_chest_diagnostics: { Args: { p_admin_id: number }; Returns: Json }
      admin_clan_anti_abuse: {
        Args: {
          p_action?: string
          p_admin_id: number
          p_target?: string
          p_value?: string
        }
        Returns: Json
      }
      admin_clan_boss: {
        Args: {
          p_action?: string
          p_admin_id: number
          p_payload?: Json
          p_ref?: string
        }
        Returns: Json
      }
      admin_clan_boss_balance: {
        Args: {
          p_action?: string
          p_admin_id: number
          p_payload?: Json
          p_ref?: string
        }
        Returns: Json
      }
      admin_clan_boss_clan: {
        Args: {
          p_action?: string
          p_admin_id: number
          p_clan_id: string
          p_payload?: Json
        }
        Returns: Json
      }
      admin_clan_boss_personal: {
        Args: {
          p_action?: string
          p_admin_id: number
          p_payload?: Json
          p_ref?: string
        }
        Returns: Json
      }
      admin_clan_boss_personal_set_fc: {
        Args: { p_admin_id: number; p_value: number }
        Returns: Json
      }
      admin_clan_boss_personal_set_player_fc: {
        Args: { p_admin_id: number; p_telegram_id: number; p_value: number }
        Returns: Json
      }
      admin_clan_raid_audit: { Args: { p_clan: string }; Returns: Json }
      admin_clan_raid_set: {
        Args: { p_field: string; p_value: number }
        Returns: Json
      }
      admin_clan_raid_settings: { Args: never; Returns: Json }
      admin_clan_settings: {
        Args: { p_action?: string; p_admin_id: number; p_value?: number }
        Returns: Json
      }
      admin_clan_system: {
        Args: { p_action: string; p_payload?: Json }
        Returns: Json
      }
      admin_clan_war_action: {
        Args: {
          p_action: string
          p_admin_id: number
          p_payload?: Json
          p_ref?: string
        }
        Returns: Json
      }
      admin_clan_war_overview: { Args: { p_admin_id: number }; Returns: Json }
      admin_clan_war_set: {
        Args: { p_admin_id: number; p_key: string; p_value: Json }
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
      admin_create_egg_visual: {
        Args: {
          p_admin_id: number
          p_currency: string
          p_image_url: string
          p_name: string
          p_price: number
        }
        Returns: Json
      }
      admin_create_pet_visual: {
        Args: {
          p_admin_id: number
          p_attribute_key: string
          p_attribute_value: number
          p_availability?: string
          p_category?: string
          p_description?: string
          p_image_url: string
          p_name: string
          p_rarity: string
          p_show_in_catalog?: boolean
          p_sources?: Json
        }
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
      admin_deposit_settings: {
        Args: { p_admin_id: number; p_key?: string; p_value?: number }
        Returns: Json
      }
      admin_egg_detail: {
        Args: { p_admin_id: number; p_egg_id: string }
        Returns: Json
      }
      admin_egg_list: { Args: { p_admin_id: number }; Returns: Json }
      admin_events: {
        Args: {
          p_action: string
          p_admin_id: number
          p_payload?: Json
          p_ref?: string
        }
        Returns: Json
      }
      admin_familiar_hunt_overview: { Args: never; Returns: Json }
      admin_familiar_hunt_set: {
        Args: { p_key: string; p_value: string }
        Returns: Json
      }
      admin_founder_pack_overview: {
        Args: { p_admin_id: number }
        Returns: Json
      }
      admin_founder_pack_set: {
        Args: { p_admin_id: number; p_field: string; p_value: string }
        Returns: Json
      }
      admin_game_balance_overview: {
        Args: { p_admin_id: number }
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
      admin_global_boss_difficulty: {
        Args: { p_admin_id: number }
        Returns: Json
      }
      admin_global_boss_multiplier: {
        Args: {
          p_admin_id: number
          p_kind: string
          p_reason?: string
          p_value: number
        }
        Returns: Json
      }
      admin_global_boss_restart_rotation: {
        Args: { p_admin_id: number; p_reason?: string }
        Returns: Json
      }
      admin_global_boss_roster: { Args: { p_admin_id: number }; Returns: Json }
      admin_global_boss_template_set: {
        Args: {
          p_admin_id: number
          p_code: string
          p_field: string
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
      admin_hero_mining_overview: {
        Args: { p_admin_id: number }
        Returns: Json
      }
      admin_hero_mining_set_currency: {
        Args: { p_admin_id: number; p_currency: string; p_daily?: number }
        Returns: Json
      }
      admin_hero_mining_set_limit: {
        Args: { p_admin_id: number; p_amount_ton: number; p_ref: string }
        Returns: Json
      }
      admin_hero_mining_set_min_claim: {
        Args: { p_admin_id: number; p_min_ton: number }
        Returns: Json
      }
      admin_hero_mining_set_min_claim_myth: {
        Args: { p_admin_id: number; p_min_myth: number }
        Returns: Json
      }
      admin_hero_mining_set_myth_rate: {
        Args: { p_admin_id: number; p_myth_per_day: number }
        Returns: Json
      }
      admin_hero_mining_set_rate: {
        Args: { p_admin_id: number; p_rarity: string; p_ton_per_day: number }
        Returns: Json
      }
      admin_hero_mining_toggle: {
        Args: { p_admin_id: number; p_enabled: boolean }
        Returns: Json
      }
      admin_hero_mining_user: {
        Args: { p_admin_id: number; p_ref: string }
        Returns: Json
      }
      admin_hero_progression_overview: {
        Args: { p_admin_id: number }
        Returns: Json
      }
      admin_hero_progression_set: {
        Args: {
          p_admin_id: number
          p_field: string
          p_target: string
          p_value: number
        }
        Returns: Json
      }
      admin_hero_rarity_flags: { Args: { p_admin_id: number }; Returns: Json }
      admin_hero_real_odds: { Args: { p_admin_id: number }; Returns: Json }
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
      admin_log:
        | {
            Args: { p_action: string; p_admin_id: number; p_context: Json }
            Returns: string
          }
        | {
            Args: {
              p_action: string
              p_admin_id: number
              p_context: Json
              p_target_id: string
            }
            Returns: string
          }
        | {
            Args: {
              p_action: string
              p_admin_id: number
              p_context?: Json
              p_new?: Json
              p_old?: Json
              p_reason?: string
              p_target_id: string
              p_target_type: string
            }
            Returns: string
          }
      admin_market_approve_trade: {
        Args: { p_admin_id: number; p_transaction_id: string }
        Returns: Json
      }
      admin_market_audit: {
        Args: { p_admin_id: number; p_limit?: number }
        Returns: Json
      }
      admin_market_cancel_listing: {
        Args: { p_admin_id: number; p_listing_id: string; p_reason?: string }
        Returns: Json
      }
      admin_market_listings: {
        Args: { p_admin_id: number; p_limit?: number; p_status?: string }
        Returns: Json
      }
      admin_market_overview: { Args: { p_admin_id: number }; Returns: Json }
      admin_market_price_ranges: { Args: { p_admin_id: number }; Returns: Json }
      admin_market_restrict_user: {
        Args: { p_admin_id: number; p_hours?: number; p_query: string }
        Returns: Json
      }
      admin_market_revenue: { Args: { p_admin_id: number }; Returns: Json }
      admin_market_reverse_trade: {
        Args: {
          p_admin_id: number
          p_reason?: string
          p_transaction_id: string
        }
        Returns: Json
      }
      admin_market_review_queue: {
        Args: { p_admin_id: number; p_limit?: number }
        Returns: Json
      }
      admin_market_search: {
        Args: { p_admin_id: number; p_limit?: number; p_query: string }
        Returns: Json
      }
      admin_market_security_audit: {
        Args: { p_admin_id: number; p_limit?: number }
        Returns: Json
      }
      admin_market_set_enabled: {
        Args: { p_admin_id: number; p_enabled: boolean }
        Returns: Json
      }
      admin_market_set_fee: {
        Args: { p_admin_id: number; p_percent: number }
        Returns: Json
      }
      admin_market_set_limit: {
        Args: { p_admin_id: number; p_max_active: number }
        Returns: Json
      }
      admin_market_set_min_price: {
        Args: { p_admin_id: number; p_item_type: string; p_value: number }
        Returns: Json
      }
      admin_market_set_price_range: {
        Args: {
          p_admin_id: number
          p_item_type: string
          p_max: number
          p_min: number
          p_rarity: string
          p_recommended?: number
        }
        Returns: Json
      }
      admin_market_set_security: {
        Args: { p_admin_id: number; p_key: string; p_value: Json }
        Returns: Json
      }
      admin_market_trade_detail: {
        Args: { p_admin_id: number; p_code: string }
        Returns: Json
      }
      admin_market_user_connections: {
        Args: { p_admin_id: number; p_query: string }
        Returns: Json
      }
      admin_market_user_history: {
        Args: { p_admin_id: number; p_limit?: number; p_query: string }
        Returns: Json
      }
      admin_market_user_listings: {
        Args: { p_admin_id: number; p_limit?: number; p_ref: string }
        Returns: Json
      }
      admin_marketing_pool_add_expense: {
        Args: {
          p_admin_id: number
          p_amount: number
          p_category: string
          p_description: string
          p_note?: string
          p_spent_at?: string
        }
        Returns: Json
      }
      admin_marketing_pool_delete_expense: {
        Args: { p_admin_id: number; p_id: string }
        Returns: Json
      }
      admin_marketing_pool_overview: {
        Args: { p_admin_id: number; p_limit?: number }
        Returns: Json
      }
      admin_marketing_pool_reset: {
        Args: { p_admin_id: number; p_mode?: string }
        Returns: Json
      }
      admin_marketing_pool_set_total: {
        Args: { p_admin_id: number; p_total: number }
        Returns: Json
      }
      admin_marketing_pool_toggle: {
        Args: { p_admin_id: number; p_enabled: boolean }
        Returns: Json
      }
      admin_marketing_pool_update_expense: {
        Args: {
          p_admin_id: number
          p_amount?: number
          p_category?: string
          p_description?: string
          p_id: string
          p_note?: string
          p_spent_at?: string
        }
        Returns: Json
      }
      admin_missions_overview: { Args: { p_admin_id: number }; Returns: Json }
      admin_myth_adjust: {
        Args: { p_admin_id: number; p_amount: number; p_ref: string }
        Returns: Json
      }
      admin_myth_burn: {
        Args: { p_admin_id: number; p_amount: number; p_reason?: string }
        Returns: Json
      }
      admin_myth_mining_pool: { Args: { p_admin_id: number }; Returns: Json }
      admin_myth_mining_pool_set: {
        Args: { p_admin_id: number; p_allocated: number }
        Returns: Json
      }
      admin_myth_overview: { Args: { p_admin_id: number }; Returns: Json }
      admin_myth_player: {
        Args: { p_admin_id: number; p_ref: string }
        Returns: Json
      }
      admin_myth_rename: {
        Args: { p_admin_id: number; p_name: string; p_symbol: string }
        Returns: Json
      }
      admin_myth_sale_history: {
        Args: { p_admin_id: number; p_limit?: number }
        Returns: Json
      }
      admin_myth_sale_overview: { Args: { p_admin_id: number }; Returns: Json }
      admin_myth_sale_set: {
        Args: { p_admin_id: number; p_key: string; p_value: number }
        Returns: Json
      }
      admin_myth_sale_status: {
        Args: { p_admin_id: number; p_status: string }
        Returns: Json
      }
      admin_myth_set_supply: {
        Args: { p_admin_id: number; p_total: number }
        Returns: Json
      }
      admin_myth_set_visibility: {
        Args: { p_admin_id: number; p_visible: boolean }
        Returns: Json
      }
      admin_myth_staking_overview: {
        Args: { p_admin_id: number }
        Returns: Json
      }
      admin_myth_staking_plan_set: {
        Args: {
          p_active: boolean
          p_admin_id: number
          p_apr: number
          p_code: string
        }
        Returns: Json
      }
      admin_myth_staking_set: {
        Args: { p_admin_id: number; p_field: string; p_value: number }
        Returns: Json
      }
      admin_myth_supply_adjust: {
        Args: { p_admin_id: number; p_amount: number; p_reason?: string }
        Returns: Json
      }
      admin_myth_utility_overview: {
        Args: { p_admin_id: number }
        Returns: Json
      }
      admin_myth_utility_set: {
        Args: {
          p_admin_id: number
          p_feature?: string
          p_field: string
          p_value: string
        }
        Returns: Json
      }
      admin_mythic_power_pack_overview: {
        Args: { p_admin_id: number }
        Returns: Json
      }
      admin_mythic_power_pack_retry: {
        Args: { p_admin_id: number; p_purchase_id: string }
        Returns: Json
      }
      admin_mythic_power_pack_set: {
        Args: { p_admin_id: number; p_field: string; p_value: string }
        Returns: Json
      }
      admin_name_mission: {
        Args: { p_action?: string; p_admin_id: number; p_payload?: Json }
        Returns: Json
      }
      admin_next_hero_key: {
        Args: { p_admin_id: number; p_name: string }
        Returns: string
      }
      admin_nft_available: {
        Args: { p_admin_id: number; p_limit?: number; p_slug?: string }
        Returns: Json
      }
      admin_nft_create: {
        Args: { p_admin_id: number; p_quantity?: number; p_slug: string }
        Returns: Json
      }
      admin_nft_equipment_create: {
        Args: {
          p_admin_id: number
          p_atk: number
          p_def: number
          p_hero_class: string
          p_hp: number
          p_image: string
          p_name: string
          p_price_ton: number
          p_slot: string
        }
        Returns: Json
      }
      admin_nft_equipment_overview: {
        Args: { p_admin_id: number; p_slot?: string }
        Returns: Json
      }
      admin_nft_give: {
        Args: {
          p_admin_id: number
          p_nft_id: string
          p_reason?: string
          p_ref: string
        }
        Returns: Json
      }
      admin_nft_hero_available: {
        Args: { p_admin_id: number; p_hero_key?: string; p_limit?: number }
        Returns: Json
      }
      admin_nft_hero_create: {
        Args: { p_admin_id: number; p_hero_key: string; p_quantity?: number }
        Returns: Json
      }
      admin_nft_hero_give: {
        Args: {
          p_admin_id: number
          p_nft_id: string
          p_reason?: string
          p_ref: string
        }
        Returns: Json
      }
      admin_nft_hero_history: {
        Args: { p_admin_id: number; p_limit?: number }
        Returns: Json
      }
      admin_nft_hero_overview: { Args: { p_admin_id: number }; Returns: Json }
      admin_nft_hero_registry: {
        Args: { p_admin_id: number; p_limit?: number; p_offset?: number }
        Returns: Json
      }
      admin_nft_hero_revoke: {
        Args: { p_admin_id: number; p_nft_id: string; p_reason?: string }
        Returns: Json
      }
      admin_nft_hero_search: {
        Args: { p_admin_id: number; p_query: string }
        Returns: Json
      }
      admin_nft_hero_set_stats: {
        Args: {
          p_admin_id: number
          p_hero_key: string
          p_patch: Json
          p_reason?: string
        }
        Returns: Json
      }
      admin_nft_hero_stats: { Args: { p_admin_id: number }; Returns: Json }
      admin_nft_history: {
        Args: { p_admin_id: number; p_limit?: number }
        Returns: Json
      }
      admin_nft_mining_history: {
        Args: { p_admin_id: number; p_limit?: number }
        Returns: Json
      }
      admin_nft_overview: { Args: { p_admin_id: number }; Returns: Json }
      admin_nft_pool_config: {
        Args: { p_admin_id: number; p_key: string; p_value: number }
        Returns: Json
      }
      admin_nft_pool_fund: {
        Args: {
          p_admin_id: number
          p_amount_ton: number
          p_note?: string
          p_type?: string
        }
        Returns: Json
      }
      admin_nft_pool_ledger: {
        Args: { p_admin_id: number; p_limit?: number }
        Returns: Json
      }
      admin_nft_pool_overview: { Args: { p_admin_id: number }; Returns: Json }
      admin_nft_pool_set_tier: {
        Args: { p_admin_id: number; p_serial: number; p_tier_ton: number }
        Returns: Json
      }
      admin_nft_pool_toggle: {
        Args: { p_admin_id: number; p_serial: number }
        Returns: Json
      }
      admin_nft_pool_units: { Args: { p_admin_id: number }; Returns: Json }
      admin_nft_pricing_overview: {
        Args: { p_admin_id: number }
        Returns: Json
      }
      admin_nft_pricing_set: {
        Args: {
          p_admin_id: number
          p_key: string
          p_target: string
          p_value: number
        }
        Returns: Json
      }
      admin_nft_registry: {
        Args: { p_admin_id: number; p_limit?: number; p_offset?: number }
        Returns: Json
      }
      admin_nft_reserve_overview: {
        Args: { p_admin_id: number }
        Returns: Json
      }
      admin_nft_reserve_refill: {
        Args: { p_admin_id: number; p_kind: string; p_limit?: number }
        Returns: Json
      }
      admin_nft_revoke: {
        Args: { p_admin_id: number; p_nft_id: string; p_reason?: string }
        Returns: Json
      }
      admin_nft_search: {
        Args: { p_admin_id: number; p_query: string }
        Returns: Json
      }
      admin_nft_stock_overview: { Args: { p_admin_id: number }; Returns: Json }
      admin_nft_stock_refill: {
        Args: { p_admin_id: number; p_kind: string }
        Returns: Json
      }
      admin_nft_yield_apply_existing: {
        Args: {
          p_admin_id: number
          p_key: string
          p_reason: string
          p_target: string
          p_value: number
        }
        Returns: Json
      }
      admin_nft_yield_review: { Args: { p_admin_id: number }; Returns: Json }
      admin_partners: {
        Args: {
          p_action?: string
          p_admin_id: number
          p_partner_id?: string
          p_payload?: Json
        }
        Returns: Json
      }
      admin_pass_history: {
        Args: { p_admin_id: number; p_limit?: number }
        Returns: Json
      }
      admin_pass_overview: { Args: { p_admin_id: number }; Returns: Json }
      admin_pass_reward_assets: {
        Args: { p_admin_id: number; p_kind: string; p_rarity?: string }
        Returns: Json
      }
      admin_pass_reward_set: {
        Args: {
          p_admin_id: number
          p_amount?: number
          p_asset?: string
          p_enabled?: boolean
          p_highlight?: boolean
          p_reward_code?: string
          p_reward_id: string
          p_reward_type?: string
          p_title?: string
        }
        Returns: Json
      }
      admin_pass_reward_track: {
        Args: { p_admin_id: number; p_tier?: string; p_version_id: string }
        Returns: Json
      }
      admin_pass_reward_view: {
        Args: { p_admin_id: number; p_reward_id: string }
        Returns: Json
      }
      admin_pass_version_activate: {
        Args: { p_admin_id: number; p_version_id: string }
        Returns: Json
      }
      admin_pass_version_cancel: {
        Args: { p_admin_id: number; p_version_id: string }
        Returns: Json
      }
      admin_pass_version_create: {
        Args: {
          p_admin_id: number
          p_adventurer_price?: number
          p_clone?: boolean
          p_days?: number
          p_legendary_price?: number
          p_levels?: number
          p_name?: string
          p_xp_per_level?: number
        }
        Returns: Json
      }
      admin_pass_version_purchases: {
        Args: { p_admin_id: number; p_version_id: string }
        Returns: Json
      }
      admin_pass_version_schedule: {
        Args: { p_admin_id: number; p_at: string; p_version_id: string }
        Returns: Json
      }
      admin_pass_version_set_audience: {
        Args: {
          p_admin_id: number
          p_config?: Json
          p_mode: string
          p_version_id: string
        }
        Returns: Json
      }
      admin_pass_version_validate: {
        Args: { p_admin_id: number; p_version_id: string }
        Returns: Json
      }
      admin_pass_versions_overview: {
        Args: { p_admin_id: number }
        Returns: Json
      }
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
      admin_pet_catalog: {
        Args: {
          p_admin_id: number
          p_limit?: number
          p_offset?: number
          p_search?: string
        }
        Returns: Json
      }
      admin_pet_config: { Args: { p_admin_id: number }; Returns: Json }
      admin_pet_detail_cms: {
        Args: { p_admin_id: number; p_pet_id: string }
        Returns: Json
      }
      admin_pet_power_audit: {
        Args: never
        Returns: {
          buff_sum: number
          evolution_stage: number
          has_zero_buff: boolean
          level: number
          pet_name: string
          player_pet_id: string
          power: number
          rarity: string
          rarity_order: number
        }[]
      }
      admin_pet_rarities: { Args: { p_admin_id: number }; Returns: Json }
      admin_pet_rarity_audit: {
        Args: { p_admin_id: number; p_limit?: number }
        Returns: Json
      }
      admin_pet_stage_images: {
        Args: { p_admin_id: number; p_pet_id: string }
        Returns: Json
      }
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
      admin_pool_ranking_tier_set: {
        Args: {
          p_admin_id: number
          p_end: number
          p_percent: number
          p_start: number
        }
        Returns: Json
      }
      admin_pool_ranking_tiers: { Args: { p_admin_id: number }; Returns: Json }
      admin_premium_offer_eligibility: {
        Args: { p_admin_id: number; p_offer_id?: string; p_query: string }
        Returns: Json
      }
      admin_premium_offer_metrics: {
        Args: { p_admin_id: number; p_offer_id?: string }
        Returns: Json
      }
      admin_premium_offer_reset_today: {
        Args: { p_admin_id: number; p_offer_id?: string; p_query: string }
        Returns: Json
      }
      admin_premium_offers_overview: {
        Args: { p_admin_id: number }
        Returns: Json
      }
      admin_premium_offers_set: {
        Args: {
          p_admin_id: number
          p_field: string
          p_offer: string
          p_value: string
        }
        Returns: Json
      }
      admin_private_trade_action: {
        Args: {
          p_action: string
          p_admin_id: number
          p_note?: string
          p_trade: string
        }
        Returns: Json
      }
      admin_private_trade_detail: {
        Args: { p_admin_id: number; p_trade: string }
        Returns: Json
      }
      admin_private_trade_overview: {
        Args: { p_admin_id: number; p_limit?: number; p_status?: string }
        Returns: Json
      }
      admin_private_trade_set: {
        Args: { p_admin_id: number; p_field: string; p_value: number }
        Returns: Json
      }
      admin_pvp_league_activate: { Args: { p_admin_id: number }; Returns: Json }
      admin_pvp_league_cancel: { Args: { p_admin_id: number }; Returns: Json }
      admin_pvp_league_configure: {
        Args: { p_admin_id: number; p_patch: Json }
        Returns: Json
      }
      admin_pvp_league_end: { Args: { p_admin_id: number }; Returns: Json }
      admin_pvp_league_overview: { Args: { p_admin_id: number }; Returns: Json }
      admin_pvp_league_ranking: {
        Args: { p_admin_id: number; p_limit?: number; p_query?: string }
        Returns: Json
      }
      admin_pvp_overview: {
        Args: { p_admin_id: number; p_top?: number }
        Returns: Json
      }
      admin_quests_overview: { Args: { p_admin_id: number }; Returns: Json }
      admin_rare_myth_mining_overview: {
        Args: { p_admin_id: number }
        Returns: Json
      }
      admin_rare_myth_mining_set: {
        Args: { p_admin_id: number; p_field: string; p_value: number }
        Returns: Json
      }
      admin_rare_myth_mining_toggle: {
        Args: { p_admin_id: number; p_enabled: boolean }
        Returns: Json
      }
      admin_rare_myth_pool_add: {
        Args: { p_admin_id: number; p_amount: number }
        Returns: Json
      }
      admin_rarity_fusion_audit: {
        Args: { p_admin_id: number; p_limit?: number; p_ref?: string }
        Returns: Json
      }
      admin_rarity_fusion_overview: {
        Args: { p_admin_id: number }
        Returns: Json
      }
      admin_realm_exploration_overview: { Args: never; Returns: Json }
      admin_realm_exploration_set: {
        Args: { p_patch: Json; p_region: string }
        Returns: Json
      }
      admin_realm_player_depth: {
        Args: { p_depth?: number; p_region: string; p_user: string }
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
      admin_repair_missing_pass_rewards: {
        Args: { p_dry_run?: boolean; p_telegram_id?: number }
        Returns: Json
      }
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
      admin_roll_pet_attribute: {
        Args: { p_admin_id: number; p_exclude?: string; p_rarity: string }
        Returns: Json
      }
      admin_roulette_cycle_cancel: {
        Args: { p_admin_id: number; p_reason?: string }
        Returns: Json
      }
      admin_roulette_history: {
        Args: { p_admin_id: number; p_limit?: number }
        Returns: Json
      }
      admin_roulette_overview: { Args: { p_admin_id: number }; Returns: Json }
      admin_roulette_reward_list: {
        Args: { p_admin_id: number; p_class: string }
        Returns: Json
      }
      admin_roulette_reward_recovery: {
        Args: { p_action?: string; p_admin_id: number; p_cycle?: string }
        Returns: Json
      }
      admin_roulette_reward_set: {
        Args: {
          p_admin_id: number
          p_class: string
          p_field: string
          p_key: string
          p_value: string
        }
        Returns: Json
      }
      admin_roulette_set: {
        Args: { p_admin_id: number; p_field: string; p_value: string }
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
      admin_set_activity_reward: {
        Args: {
          p_activity: string
          p_admin_id: number
          p_field: string
          p_value: number
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
      admin_set_egg_odds: {
        Args: { p_admin_id: number; p_egg_id: string; p_rates: Json }
        Returns: Json
      }
      admin_set_egg_pet_weight: {
        Args: {
          p_admin_id: number
          p_egg_id: string
          p_pet_id: string
          p_rarity: string
          p_weight: number
        }
        Returns: Json
      }
      admin_set_egg_price_visual: {
        Args: {
          p_admin_id: number
          p_currency: string
          p_egg_id: string
          p_price: number
        }
        Returns: Json
      }
      admin_set_fragment_config: {
        Args: { p_admin_id: number; p_quantity?: number; p_rates?: Json }
        Returns: Json
      }
      admin_set_fragment_utility: {
        Args: {
          p_admin_id: number
          p_common_chance?: number
          p_fragments_per_fusion?: number
          p_fragments_per_hero?: number
          p_uncommon_chance?: number
        }
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
      admin_set_hero_rarity_enabled: {
        Args: { p_admin_id: number; p_enabled: boolean; p_rarity: string }
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
      admin_set_hero_real_summon_rates: {
        Args: { p_admin_id: number; p_rates: Json; p_reason?: string }
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
      admin_set_pet_stage_image: {
        Args: {
          p_admin_id: number
          p_pet_id: string
          p_stage: string
          p_url: string
        }
        Returns: Json
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
      admin_set_premium_title: {
        Args: { p_admin_id: number; p_telegram_id: number; p_title: string }
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
      admin_sovereign_pack_overview: {
        Args: { p_admin_id: number }
        Returns: Json
      }
      admin_sovereign_pack_reveal: {
        Args: {
          p_admin_id: number
          p_daily_myth: number
          p_daily_ton: number
          p_item_id: string
        }
        Returns: Json
      }
      admin_sovereign_pack_set: {
        Args: { p_admin_id: number; p_field: string; p_value: string }
        Returns: Json
      }
      admin_spending_event_audit: {
        Args: { p_admin_id: number; p_event_id: string; p_limit?: number }
        Returns: Json
      }
      admin_spending_event_create: {
        Args: { p_admin_id: number; p_days?: number; p_name?: string }
        Returns: Json
      }
      admin_spending_event_finalize: {
        Args: { p_admin_id: number; p_event_id: string }
        Returns: Json
      }
      admin_spending_event_overview: {
        Args: { p_admin_id: number }
        Returns: Json
      }
      admin_spending_event_pay: {
        Args: { p_admin_id: number; p_event_id: string }
        Returns: Json
      }
      admin_spending_event_popup_config: {
        Args: { p_admin_id: number; p_enabled?: boolean; p_frequency?: string }
        Returns: Json
      }
      admin_spending_event_ranking: {
        Args: { p_admin_id: number; p_event_id: string; p_limit?: number }
        Returns: Json
      }
      admin_spending_event_rules: {
        Args: { p_admin_id: number }
        Returns: Json
      }
      admin_spending_event_set_duration: {
        Args: { p_admin_id: number; p_days: number; p_event_id: string }
        Returns: Json
      }
      admin_spending_event_set_rate: {
        Args: { p_admin_id: number; p_currency: string; p_value: number }
        Returns: Json
      }
      admin_spending_event_set_reward: {
        Args: {
          p_admin_id: number
          p_event_id: string
          p_from: number
          p_label: string
          p_to: number
        }
        Returns: Json
      }
      admin_spending_event_set_status: {
        Args: { p_admin_id: number; p_event_id: string; p_status: string }
        Returns: Json
      }
      admin_spending_event_toggle_source: {
        Args: { p_admin_id: number; p_enabled?: boolean; p_source: string }
        Returns: Json
      }
      admin_status_overview: { Args: { p_admin_id: number }; Returns: Json }
      admin_super_id: { Args: never; Returns: number }
      admin_tactical_matches: {
        Args: { p_admin_id: number; p_limit?: number }
        Returns: Json
      }
      admin_tactical_overview: { Args: { p_admin_id: number }; Returns: Json }
      admin_tactical_ranking: {
        Args: { p_admin_id: number; p_limit?: number }
        Returns: Json
      }
      admin_tactical_reset: { Args: { p_admin_id: number }; Returns: Json }
      admin_tactical_set: {
        Args: { p_admin_id: number; p_key: string; p_value: Json }
        Returns: Json
      }
      admin_tactical_skill_set: {
        Args: {
          p_admin_id: number
          p_field: string
          p_skill_key: string
          p_value: number
        }
        Returns: Json
      }
      admin_toggle_egg_pet: {
        Args: {
          p_admin_id: number
          p_egg_id: string
          p_pet_id: string
          p_rarity: string
          p_weight?: number
        }
        Returns: Json
      }
      admin_ton_adjust: {
        Args: {
          p_admin_id: number
          p_amount_ton: number
          p_direction: string
          p_reason: string
          p_user_id: string
        }
        Returns: Json
      }
      admin_ton_adjust_history: {
        Args: { p_admin_id: number; p_limit?: number }
        Returns: Json
      }
      admin_ton_audit: {
        Args: { p_admin_id: number; p_limit?: number }
        Returns: Json
      }
      admin_ton_balance: {
        Args: { p_admin_id: number; p_query: string }
        Returns: Json
      }
      admin_ton_lookup: {
        Args: { p_admin_id: number; p_telegram_id: number }
        Returns: Json
      }
      admin_ton_mine_set: {
        Args: {
          p_admin_id: number
          p_field: string
          p_key: string
          p_value: string
        }
        Returns: Json
      }
      admin_ton_mines_allow: {
        Args: { p_add: boolean; p_admin_id: number; p_telegram_id: number }
        Returns: Json
      }
      admin_ton_mines_flag: {
        Args: { p_admin_id: number; p_field: string; p_value: boolean }
        Returns: Json
      }
      admin_ton_mines_overview: { Args: { p_admin_id: number }; Returns: Json }
      admin_ton_mines_set: {
        Args: { p_admin_id: number; p_field: string; p_value: number }
        Returns: Json
      }
      admin_ton_mining_gate: { Args: { p_admin_id: number }; Returns: Json }
      admin_ton_mining_gate_audit: {
        Args: { p_admin_id: number; p_telegram_id: number }
        Returns: Json
      }
      admin_ton_mining_gate_cutoff: {
        Args: { p_admin_id: number; p_cutoff: string }
        Returns: Json
      }
      admin_ton_mining_gate_grant: {
        Args: { p_admin_id: number; p_note?: string; p_telegram_id: number }
        Returns: Json
      }
      admin_ton_mining_gate_revoke: {
        Args: { p_admin_id: number; p_note?: string; p_telegram_id: number }
        Returns: Json
      }
      admin_ton_mining_gate_set: {
        Args: { p_admin_id: number; p_enabled: boolean }
        Returns: Json
      }
      admin_ton_mining_gate_users: {
        Args: { p_admin_id: number; p_limit?: number; p_type: string }
        Returns: Json
      }
      admin_ton_reward_history: {
        Args: { p_admin_id: number; p_limit?: number; p_user_id?: string }
        Returns: Json
      }
      admin_ton_staking_flag: {
        Args: { p_admin_id: number; p_field: string; p_value: boolean }
        Returns: undefined
      }
      admin_ton_staking_overview: {
        Args: { p_admin_id: number }
        Returns: Json
      }
      admin_ton_staking_plan_set: {
        Args: {
          p_admin_id: number
          p_code: string
          p_field: string
          p_value: string
        }
        Returns: undefined
      }
      admin_ton_staking_set: {
        Args: { p_admin_id: number; p_field: string; p_value: number }
        Returns: undefined
      }
      admin_ton_withdrawals: {
        Args: { p_admin_id: number; p_limit?: number; p_status?: string }
        Returns: Json
      }
      admin_unlink_referral: {
        Args: { p_admin_id: number; p_reason: string; p_ref: string }
        Returns: Json
      }
      admin_update_channel: {
        Args: { p_admin_id: number; p_channel_key: string; p_patch: Json }
        Returns: Json
      }
      admin_update_egg_visual: {
        Args: { p_admin_id: number; p_egg_id: string; p_patch: Json }
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
          veteran_dragon_pet_id: string | null
          veteran_line: boolean
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
      admin_update_pet_visual: {
        Args: {
          p_admin_id: number
          p_patch: Json
          p_pet_id: string
          p_reason?: string
        }
        Returns: Json
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
      admin_vanguard_pack_overview: {
        Args: { p_admin_id: number }
        Returns: Json
      }
      admin_vanguard_pack_retry: {
        Args: { p_admin_id: number; p_purchase_id: string }
        Returns: Json
      }
      admin_vanguard_pack_reveal: {
        Args: {
          p_admin_id: number
          p_daily_myth?: number
          p_daily_ton: number
          p_item_id: string
          p_override?: boolean
          p_reason?: string
        }
        Returns: Json
      }
      admin_vanguard_pack_set: {
        Args: { p_admin_id: number; p_field: string; p_value: string }
        Returns: Json
      }
      admin_veteran_v2_fund: {
        Args: { p_admin_id: number; p_amount: number; p_pool: string }
        Returns: Json
      }
      admin_veteran_v2_overview: { Args: { p_admin_id: number }; Returns: Json }
      admin_veteran_v2_set: {
        Args: { p_admin_id: number; p_field: string; p_value: string }
        Returns: Json
      }
      admin_veteran_vault_fund: {
        Args: { p_admin_id: number; p_amount: number; p_currency: string }
        Returns: Json
      }
      admin_veteran_vault_overview: {
        Args: { p_admin_id: number }
        Returns: Json
      }
      admin_veteran_vault_set: {
        Args: { p_admin_id: number; p_field: string; p_value: string }
        Returns: Json
      }
      admin_wallet_config: {
        Args: { p_action?: string; p_admin_id: number; p_payload?: Json }
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
      adventurer_assert_tier_safe: {
        Args: { p_rarity: string; p_what: string }
        Returns: undefined
      }
      adventurer_hero_pool_size: { Args: never; Returns: number }
      adventurer_pack_confirm_order: {
        Args: { p_amount_nano: string; p_order_id: string; p_tx_hash: string }
        Returns: Json
      }
      adventurer_pack_deliver: {
        Args: { p_purchase_id: string }
        Returns: Json
      }
      adventurer_pack_grant_pass: {
        Args: { p_purchase_id: string }
        Returns: Json
      }
      adventurer_pack_offer_meta: { Args: { p_user_id: string }; Returns: Json }
      adventurer_pack_offer_state: {
        Args: { p_telegram_id: number }
        Returns: Json
      }
      adventurer_pack_settings: {
        Args: never
        Returns: {
          account_ton_bonus_percent: number
          enabled: boolean
          ends_at: string | null
          fc_reward: number
          grant_pass_tier: string
          hero_rarity: string
          id: boolean
          legendary_armors: number
          legendary_chests: number
          lock_mining_after_reveal: boolean
          max_reward_rarity: string
          nft_weapons: number
          package_version: string
          popup_enabled: boolean
          popup_frequency: string
          popup_priority: number
          price_ton: number
          purchase_limit: number
          random_items: number
          random_items_pool: Json
          reward_configuration_version: number
          sales_paused: boolean
          sold_out_visible: boolean
          start_at: string | null
          stock_total: number | null
          universal_fragments: number
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "adventurer_pack_config"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      adventurer_pack_start_purchase: {
        Args: {
          p_idempotency_key: string
          p_telegram_id: number
          p_wallet_address: string
        }
        Returns: Json
      }
      adventurer_pack_state: { Args: { p_telegram_id: number }; Returns: Json }
      anti_fake_log: {
        Args: {
          p_device_hash: string
          p_event: string
          p_metadata?: Json
          p_telegram_id: number
        }
        Returns: undefined
      }
      anti_fake_max_accounts: { Args: never; Returns: number }
      arsenal_json: { Args: { p_telegram_id: number }; Returns: Json }
      attack_boss: { Args: { p_telegram_id: number }; Returns: Json }
      auction_browse: {
        Args: {
          p_item_type?: string
          p_limit?: number
          p_offset?: number
          p_sort?: string
          p_telegram_id: number
        }
        Returns: Json
      }
      auction_can_access: { Args: { p_telegram_id: number }; Returns: boolean }
      auction_cancel: {
        Args: { p_auction_id: string; p_telegram_id: number }
        Returns: Json
      }
      auction_create: {
        Args: {
          p_duration_hours: number
          p_item_instance_id: string
          p_item_type: string
          p_starting_bid_ton: number
          p_telegram_id: number
        }
        Returns: Json
      }
      auction_finalize_due: { Args: never; Returns: number }
      auction_finalize_one: { Args: { p_auction_id: string }; Returns: Json }
      auction_item_lock: {
        Args: { p_instance: string; p_item_type: string; p_locked: boolean }
        Returns: undefined
      }
      auction_item_snapshot: {
        Args: { p_instance: string; p_item_type: string; p_user: string }
        Returns: Json
      }
      auction_item_transfer: {
        Args: { p_buyer: string; p_instance: string; p_item_type: string }
        Returns: undefined
      }
      auction_mine: { Args: { p_telegram_id: number }; Returns: Json }
      auction_only_item: {
        Args: { p_item_type: string; p_rarity: string }
        Returns: boolean
      }
      auction_place_bid: {
        Args: {
          p_amount_ton: number
          p_auction_id: string
          p_idempotency_key: string
          p_telegram_id: number
        }
        Returns: Json
      }
      auction_sellable: { Args: { p_telegram_id: number }; Returns: Json }
      auction_settings_json: { Args: never; Returns: Json }
      auction_ton_move: {
        Args: {
          p_amount: number
          p_auction: string
          p_bid: string
          p_details?: Json
          p_event: string
          p_user: string
        }
        Returns: undefined
      }
      audit_player_deposits: { Args: { p_telegram_id: number }; Returns: Json }
      auto_withdraw_claim_batch: { Args: never; Returns: Json }
      auto_withdraw_complete: {
        Args: {
          p_amount_ton: number
          p_tx_hash: string
          p_withdrawal_id: string
        }
        Returns: Json
      }
      auto_withdraw_config: { Args: never; Returns: Json }
      auto_withdraw_register_worker: {
        Args: { p_key: string }
        Returns: undefined
      }
      auto_withdraw_release: {
        Args: { p_error: string; p_withdrawal_id: string }
        Returns: undefined
      }
      auto_withdraw_tick: { Args: never; Returns: undefined }
      award_pool_points: {
        Args: { p_activity: string; p_source_id: string; p_user_id: string }
        Returns: undefined
      }
      bind_referral: {
        Args: { p_inviter_telegram_id: number; p_telegram_id: number }
        Returns: Json
      }
      boss_auto_next_attack_at: {
        Args: { p_cooldown_end: string; p_user: string }
        Returns: string
      }
      boss_heroes_revive_at: { Args: { p_user: string }; Returns: string }
      boss_team_json: { Args: { p_user: string }; Returns: Json }
      breeding_cost: { Args: { p_breed_number: number }; Returns: number }
      breeding_settings: {
        Args: never
        Returns: {
          adult_hours: number
          baby_hours: number
          cooldown_days: number
          cost_breed_1: number
          cost_breed_2: number
          cost_breed_3: number
          enabled: boolean
          id: boolean
          juvenile_hours: number
          max_breeds: number
          min_claim_ton: number
          request_ttl_minutes: number
          sub_breeding_enabled: boolean
          sub_rate_per_ton: number
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "nft_breeding_settings"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      buy_pass_locked_reward: {
        Args: {
          p_idempotency_key: string
          p_reward_id: string
          p_telegram_id: number
          p_wallet_address: string
        }
        Returns: Json
      }
      buy_pet_egg: {
        Args: {
          p_currency?: string
          p_egg_id: string
          p_idempotency_key?: string
          p_quantity?: number
          p_telegram_id: number
        }
        Returns: Json
      }
      buy_pet_food: {
        Args: {
          p_currency?: string
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
          p_currency?: string
          p_idempotency_key: string
          p_levels: number
          p_telegram_id: number
        }
        Returns: Json
      }
      calculate_pet_combat_stats: {
        Args: { p_player_pet_id: string }
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
      can_access_ton_mining: { Args: { p_user_id: string }; Returns: string }
      celestial_pack_confirm_order: {
        Args: { p_amount_nano: string; p_order_id: string; p_tx_hash: string }
        Returns: Json
      }
      celestial_pack_deliver: { Args: { p_purchase_id: string }; Returns: Json }
      celestial_pack_offer_meta: { Args: { p_user_id: string }; Returns: Json }
      celestial_pack_offer_state: {
        Args: { p_telegram_id: number }
        Returns: Json
      }
      celestial_pack_settings: {
        Args: never
        Returns: {
          account_ton_bonus_percent: number
          armors: number
          enabled: boolean
          ends_at: string | null
          fc_reward: number
          id: boolean
          legendary_chests: number
          nft_weapons: number
          package_version: string
          popup_enabled: boolean
          popup_frequency: string
          popup_priority: number
          price_ton: number
          purchase_limit: number
          random_items: number
          random_items_pool: Json
          reward_configuration_version: number
          sales_paused: boolean
          sold_out_visible: boolean
          start_at: string | null
          stock_total: number | null
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "celestial_pack_config"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      celestial_pack_start_purchase: {
        Args: {
          p_idempotency_key: string
          p_telegram_id: number
          p_wallet_address: string
        }
        Returns: Json
      }
      celestial_pack_state: { Args: { p_telegram_id: number }; Returns: Json }
      check_device_access: {
        Args: {
          p_device_hash: string
          p_metadata?: Json
          p_platform?: string
          p_telegram_id: number
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
      claim_daily_offer_impression: {
        Args: { p_offer_id: string; p_telegram_id: number }
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
      claim_hero_mining: { Args: { p_telegram_id: number }; Returns: Json }
      claim_name_mission: {
        Args: {
          p_auth_date?: number
          p_display_name: string
          p_source?: string
          p_telegram_id: number
        }
        Returns: Json
      }
      claim_partner_reward:
        | {
            Args: { p_partner_id: string; p_telegram_id: number }
            Returns: Json
          }
        | {
            Args: {
              p_membership_verified?: boolean
              p_partner_id: string
              p_telegram_id: number
            }
            Returns: Json
          }
      claim_season_pass_reward: {
        Args: { p_reward_id: string; p_telegram_id: number }
        Returns: Json
      }
      claim_starter_pack: { Args: { p_telegram_id: number }; Returns: Json }
      clan_active_members: { Args: { p_clan: string }; Returns: number }
      clan_anti_abuse_cfg: {
        Args: never
        Returns: {
          boss_lock_enabled: boolean
          boss_lock_min_hours: number
          enabled: boolean
          hopping_threshold_24h: number
          id: number
          kick_cooldown_hours: number
          leave_cooldown_hours: number
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "clan_anti_abuse_settings"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      clan_anti_abuse_state: { Args: { p_telegram_id: number }; Returns: Json }
      clan_assert_can_join: { Args: { p_user_id: string }; Returns: undefined }
      clan_award_contribution: {
        Args: {
          p_amount: number
          p_coins?: number
          p_source_id?: string
          p_source_type: string
          p_user: string
        }
        Returns: Json
      }
      clan_boss_apply_def: {
        Args: { p_def: number; p_power: number; p_raw: number }
        Returns: number
      }
      clan_boss_attack: { Args: { p_telegram_id: number }; Returns: Json }
      clan_boss_auto_attack_one: { Args: { p_user: string }; Returns: Json }
      clan_boss_auto_attack_state_json: {
        Args: { p_user: string }
        Returns: Json
      }
      clan_boss_auto_due_users: {
        Args: { p_limit?: number }
        Returns: string[]
      }
      clan_boss_cfg: {
        Args: never
        Returns: {
          base_hp: number
          boss_key: string
          boss_name: string
          clan_xp_reward: number
          cooldown_seconds: number
          duration_hours: number
          hp_per_clan_level_pct: number
          hp_per_cycle_pct: number
          hp_per_member_pct: number
          id: number
          min_damage_pct: number
          rewards: Json
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "clan_boss_config"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      clan_boss_clan_cfg: { Args: { p_clan_id: string }; Returns: Json }
      clan_boss_compute_scaling: {
        Args: { p_clan_id: string; p_cycle?: number }
        Returns: Json
      }
      clan_boss_cycle_lock: { Args: { p_clan_id: string }; Returns: Json }
      clan_boss_deliver: {
        Args: { p_reward: Json; p_user_id: string }
        Returns: undefined
      }
      clan_boss_effective_dps: { Args: { p_clan_id: string }; Returns: Json }
      clan_boss_ensure: {
        Args: { p_clan_id: string }
        Returns: {
          active_members_snapshot: number | null
          actual_duration_seconds: number | null
          atk_multiplier: number
          attacks: number
          base_hp: number | null
          boss_atk: number
          boss_def: number
          boss_key: string
          boss_name: string
          boss_number_today: number
          boss_power: number
          clan_id: string
          clan_power_snapshot: number | null
          clan_xp_awarded: number
          created_at: string
          current_hp: number
          cycle: number
          cycle_ends_at: string | null
          cycle_started_at: string | null
          def_multiplier: number
          difficulty: string | null
          duration_quality: string | null
          ends_at: string
          finished_at: string | null
          historical_dps_snapshot: number | null
          hp_multiplier: number
          id: string
          is_personal: boolean
          level: number
          max_hp: number
          min_damage_required: number
          participants: number
          performance_snapshot: Json
          player_power_snapshot: number | null
          reset_day: string | null
          rewards_snapshot: Json
          scaling_snapshot: Json
          scaling_version: number
          starts_at: string
          status: string
          target_duration_seconds: number | null
          top_user_id: string | null
          total_damage: number
          user_id: string | null
        }
        SetofOptions: {
          from: "*"
          to: "clan_boss_instances"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      clan_boss_lock_acquire: {
        Args: {
          p_clan_id: string
          p_cycle: number
          p_ends_at: string
          p_instance_id: string
          p_user_id: string
        }
        Returns: undefined
      }
      clan_boss_lock_json: { Args: { p_user_id: string }; Returns: Json }
      clan_boss_metrics: { Args: { p_clan_id: string }; Returns: Json }
      clan_boss_next_reset_at: { Args: { p_at?: string }; Returns: string }
      clan_boss_personal_cfg: {
        Args: never
        Returns: {
          atk_ratio: number
          balanced_pct: number
          boss_duration_hours: number
          capacity_ceiling: number
          capacity_floor: number
          daily_limit: number
          def_mitigation_target: number
          difficulty_bonus_enabled: boolean
          easy_pct: number
          enabled: boolean
          fc_pool_pct: number
          fixed_fc_pool: number
          hard_pct: number
          history_samples: number
          id: number
          max_hp: number
          max_scale_down: number
          max_scale_up: number
          min_hp: number
          outlier_median_factor: number
          reset_hour_utc: number
          scaling_version: number
          target_attacks_per_boss: number
          updated_at: string
          very_easy_pct: number
          very_hard_pct: number
        }
        SetofOptions: {
          from: "*"
          to: "clan_boss_personal_config"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      clan_boss_personal_daily: { Args: { p_user: string }; Returns: Json }
      clan_boss_personal_ensure: {
        Args: { p_clan: string; p_user: string }
        Returns: {
          active_members_snapshot: number | null
          actual_duration_seconds: number | null
          atk_multiplier: number
          attacks: number
          base_hp: number | null
          boss_atk: number
          boss_def: number
          boss_key: string
          boss_name: string
          boss_number_today: number
          boss_power: number
          clan_id: string
          clan_power_snapshot: number | null
          clan_xp_awarded: number
          created_at: string
          current_hp: number
          cycle: number
          cycle_ends_at: string | null
          cycle_started_at: string | null
          def_multiplier: number
          difficulty: string | null
          duration_quality: string | null
          ends_at: string
          finished_at: string | null
          historical_dps_snapshot: number | null
          hp_multiplier: number
          id: string
          is_personal: boolean
          level: number
          max_hp: number
          min_damage_required: number
          participants: number
          performance_snapshot: Json
          player_power_snapshot: number | null
          reset_day: string | null
          rewards_snapshot: Json
          scaling_snapshot: Json
          scaling_version: number
          starts_at: string
          status: string
          target_duration_seconds: number | null
          top_user_id: string | null
          total_damage: number
          user_id: string | null
        }
        SetofOptions: {
          from: "*"
          to: "clan_boss_instances"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      clan_boss_personal_fc_pool: { Args: { p_user: string }; Returns: number }
      clan_boss_personal_scaling: { Args: { p_user: string }; Returns: Json }
      clan_boss_player_metrics: { Args: { p_user: string }; Returns: Json }
      clan_boss_profile_persist: { Args: { p_user: string }; Returns: Json }
      clan_boss_record_performance: {
        Args: { p_instance_id: string; p_status: string }
        Returns: undefined
      }
      clan_boss_reset_day: { Args: { p_at?: string }; Returns: string }
      clan_boss_scaled_hp: {
        Args: { p_clan_id: string; p_cycle: number }
        Returns: number
      }
      clan_boss_scaling_cfg: {
        Args: never
        Returns: {
          atk_ratio: number
          atk_scaling: number
          bosses_per_day: number
          cycle_hours: number
          cycle_lock_enabled: boolean
          cycle_lock_hours: number
          def_mitigation_cap: number
          def_scaling: number
          def_share: number
          enabled: boolean
          engagement_factor: number
          fixed_hp: number
          hp_scaling: number
          hp_share: number
          id: number
          max_hp_cap: number
          max_scale_down_per_cycle: number
          max_scale_up_per_cycle: number
          min_effective_damage_pct: number
          outlier_median_factor: number
          rebase_kills_threshold: number
          rebase_max_scale: number
          scaling_version: number
          survival_factor: number
          target_duration_seconds: number
          too_easy_seconds: number
          too_hard_seconds: number
          updated_at: string
          w_24h: number
          w_3d: number
          w_7d: number
        }
        SetofOptions: {
          from: "*"
          to: "clan_boss_scaling_config"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      clan_boss_scaling_persist: { Args: { p_clan_id: string }; Returns: Json }
      clan_boss_settle: {
        Args: { p_instance_id: string; p_status: string }
        Returns: undefined
      }
      clan_boss_strike: {
        Args: { p_instance_id?: string; p_telegram_id: number }
        Returns: Json
      }
      clan_boss_template_for_cycle: {
        Args: { p_cycle: number }
        Returns: {
          background_url: string | null
          base_damage: number
          boss_key: string
          created_at: string
          cycle_number: number
          enabled: boolean
          id: string
          image_url: string | null
          max_hp: number
          name: string
          reward_clan_xp: number
          reward_fc: number
          sort_order: number
          subtitle: string
          theme: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "clan_boss_templates"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      clan_buff_activate: {
        Args: { p_code: string; p_telegram_id: number }
        Returns: Json
      }
      clan_buff_pct: {
        Args: { p_clan: string; p_code: string }
        Returns: number
      }
      clan_can_manage_upgrades: {
        Args: { p_clan?: string; p_user: string }
        Returns: boolean
      }
      clan_chat: {
        Args: {
          p_action?: string
          p_body?: string
          p_message_id?: string
          p_telegram_id: number
        }
        Returns: Json
      }
      clan_coin_award: {
        Args: {
          p_amount: number
          p_source: string
          p_source_id: string
          p_user: string
        }
        Returns: Json
      }
      clan_coin_cfg: {
        Args: never
        Returns: {
          boss_coins: number[]
          enabled: boolean
          id: boolean
          milestone_coins: Json
          personal_weekly_cap: number
          price_multiplier_max: number
          price_multiplier_min: number
          raid_defeat: number
          raid_participation: number
          raid_top_bonus: number[]
          target_coins_per_active: number
          updated_at: string
          war_participation: number
          war_victory: number
        }
        SetofOptions: {
          from: "*"
          to: "clan_coin_settings"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      clan_collective_cfg: {
        Args: never
        Returns: {
          active_member_days: number
          boss_points: number[]
          clan_xp_per_contribution: number
          coins_per_contribution: number
          donation_default_max_fc: number
          donation_default_max_myth: number
          donation_default_min_fc: number
          donation_default_min_myth: number
          donation_hard_max_fc: number
          donation_hard_max_myth: number
          enabled: boolean
          id: boolean
          milestones: Json
          min_weekly_contribution: number
          myth_milestone_rewards: boolean
          raid_attacks_per_day: number
          raid_boss_name: string
          raid_catchup_enabled: boolean
          raid_catchup_max_pct: number
          raid_deadline_days: number
          raid_dps_weight_24h: number
          raid_dps_weight_3d: number
          raid_dps_weight_7d: number
          raid_duration_days: number
          raid_enabled: boolean
          raid_full_kill_required: boolean
          raid_health_gates_enabled: boolean
          raid_hp_max: number
          raid_hp_min: number
          raid_hp_per_power: number
          raid_max_hp_decrease_pct: number
          raid_max_hp_increase_pct: number
          raid_min_kill_days: number
          raid_rewards: Json
          raid_safety_factor: number
          raid_target_kill_days: number
          treasury_assets: string[]
          treasury_ton_enabled: boolean
          updated_at: string
          weekly_target_max: number
          weekly_target_min: number
          weekly_target_per_active: number
        }
        SetofOptions: {
          from: "*"
          to: "clan_collective_settings"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      clan_contribution_detail: {
        Args: { p_target?: string; p_telegram_id: number }
        Returns: Json
      }
      clan_contribution_from_personal_boss: {
        Args: { p_instance: string; p_user: string }
        Returns: Json
      }
      clan_contribution_history: {
        Args: { p_limit?: number; p_target?: string; p_telegram_id: number }
        Returns: Json
      }
      clan_contribution_limits_set: {
        Args: {
          p_asset: string
          p_max: number
          p_min: number
          p_telegram_id: string
        }
        Returns: Json
      }
      clan_contribution_summary: {
        Args: { p_period?: string; p_telegram_id: number }
        Returns: Json
      }
      clan_donation_limits: {
        Args: { p_asset: string; p_clan: string }
        Returns: Json
      }
      clan_donation_reason_valid: {
        Args: { p_reason: string }
        Returns: boolean
      }
      clan_donation_state: { Args: { p_telegram_id: string }; Returns: Json }
      clan_exploit_dry_run: { Args: { p_user_id: string }; Returns: Json }
      clan_exploit_execute: {
        Args: { p_admin_id: number; p_user_id: string }
        Returns: Json
      }
      clan_exploit_holdings: { Args: { p_user_id: string }; Returns: Json }
      clan_exploit_scan: {
        Args: { p_admin_id?: number; p_user_id?: string }
        Returns: Json
      }
      clan_has_permission: {
        Args: { p_perm: string; p_user: string }
        Returns: boolean
      }
      clan_hub_prepare: { Args: { p_telegram_id: number }; Returns: undefined }
      clan_hub_state: { Args: { p_telegram_id: number }; Returns: Json }
      clan_join_cooldown_json: { Args: { p_user_id: string }; Returns: Json }
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
      clan_membership_close: {
        Args: {
          p_clan_id: string
          p_reason: string
          p_removed_by?: string
          p_user_id: string
        }
        Returns: Json
      }
      clan_membership_open: {
        Args: { p_clan_id: string; p_user_id: string }
        Returns: undefined
      }
      clan_milestone_claim: {
        Args: { p_pct: number; p_telegram_id: number }
        Returns: Json
      }
      clan_online_minutes: { Args: never; Returns: number }
      clan_period_start: { Args: { p_period: string }; Returns: string }
      clan_player_power: { Args: { p_user_id: string }; Returns: number }
      clan_public: {
        Args: { p_clan: Database["public"]["Tables"]["clans"]["Row"] }
        Returns: Json
      }
      clan_raid_attack: {
        Args: { p_key?: string; p_telegram_id: number }
        Returns: Json
      }
      clan_raid_catchup_pct: {
        Args: { r: Database["public"]["Tables"]["clan_raid_cycles"]["Row"] }
        Returns: number
      }
      clan_raid_daily_capacity: {
        Args: { p_clan: string; p_raid?: string }
        Returns: number
      }
      clan_raid_damage_today: { Args: { p_raid: string }; Returns: number }
      clan_raid_day: { Args: { p_started: string }; Returns: number }
      clan_raid_effective_dps: { Args: { p_clan: string }; Returns: number }
      clan_raid_ensure: {
        Args: { p_clan: string }
        Returns: {
          active_members_snapshot: number
          boss_atk: number
          boss_def: number
          boss_name: string
          boss_theme: string
          boss_tier: string
          catchup_pct: number
          clan_id: string
          clan_power_snapshot: number
          cleared_in_hours: number | null
          combat_damage: number
          created_at: string
          current_hp: number
          deadline_days: number
          effective_dps_snapshot: number
          ends_at: string
          gates_enabled: boolean
          id: string
          kill_unlock_at: string | null
          max_hp: number
          min_kill_days: number
          participants: number
          performance_class: string | null
          raid_key: string
          rewards_snapshot: Json
          settled_at: string | null
          started_at: string
          status: string
          target_days: number
          total_damage: number
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "clan_raid_cycles"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      clan_raid_grant_legendary_hero: {
        Args: { p_raid: string; p_user_id: string }
        Returns: Json
      }
      clan_raid_kill_unlock_at: {
        Args: { r: Database["public"]["Tables"]["clan_raid_cycles"]["Row"] }
        Returns: string
      }
      clan_raid_phase_floor: {
        Args: { r: Database["public"]["Tables"]["clan_raid_cycles"]["Row"] }
        Returns: number
      }
      clan_raid_rebase: {
        Args: { p_raid: string; p_reason?: string }
        Returns: Json
      }
      clan_raid_rebase_all: { Args: { p_reason?: string }; Returns: Json }
      clan_raid_record_performance: {
        Args: { p_raid: string }
        Returns: undefined
      }
      clan_raid_settle: { Args: { p_raid: string }; Returns: Json }
      clan_raid_state: { Args: { p_telegram_id: number }; Returns: Json }
      clan_raid_target_hp: {
        Args: { p_clan: string; p_raid?: string }
        Returns: number
      }
      clan_resolve_user:
        | {
            Args: { p_telegram_id: number }
            Returns: {
              error: true
            } & "Could not choose the best candidate function between: public.clan_resolve_user(p_telegram_id => int8), public.clan_resolve_user(p_telegram_id => text). Try renaming the parameters or the function itself in the database so function overloading can be resolved"
          }
        | {
            Args: { p_telegram_id: string }
            Returns: {
              error: true
            } & "Could not choose the best candidate function between: public.clan_resolve_user(p_telegram_id => int8), public.clan_resolve_user(p_telegram_id => text). Try renaming the parameters or the function itself in the database so function overloading can be resolved"
          }
      clan_role_rank: { Args: { p_role: string }; Returns: number }
      clan_shop_buy: {
        Args: { p_item: string; p_quantity?: number; p_telegram_id: number }
        Returns: Json
      }
      clan_shop_cycle_ensure: {
        Args: { p_clan: string }
        Returns: {
          clan_id: string
          created_at: string
          effective_active_members: number
          forecast_emission: number
          id: string
          price_multiplier: number
          reference_emission: number
          total_members: number
          week_key: string
        }
        SetofOptions: {
          from: "*"
          to: "clan_shop_cycles"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      clan_shop_effective_active: { Args: { p_clan: string }; Returns: number }
      clan_shop_purchase: {
        Args: {
          p_code: string
          p_idempotency_key?: string
          p_quantity?: number
          p_telegram_id: number
        }
        Returns: Json
      }
      clan_shop_state: { Args: { p_telegram_id: number }; Returns: Json }
      clan_treasury_donate: {
        Args: { p_amount: number; p_asset: string; p_telegram_id: string }
        Returns: Json
      }
      clan_treasury_move: {
        Args: {
          p_amount: number
          p_asset: string
          p_clan: string
          p_reason: string
          p_user: string
        }
        Returns: number
      }
      clan_upgrade_buy: {
        Args: { p_code: string; p_key?: string; p_telegram_id: number }
        Returns: Json
      }
      clan_upgrade_level: {
        Args: { p_clan: string; p_code: string }
        Returns: number
      }
      clan_war_active: {
        Args: { p_clan: string }
        Returns: {
          attacks_per_player: number
          battle_ends_at: string | null
          battle_starts_at: string | null
          clan_a: string | null
          clan_b: string | null
          created_at: string
          ends_at: string | null
          finished_at: string | null
          id: string
          preparation_starts_at: string | null
          registered_by: string | null
          roster_size: number
          score_a: number
          score_b: number
          season_id: string | null
          settled_at: string | null
          starts_at: string | null
          status: string
          test_war: boolean
          winner_clan_id: string | null
        }
        SetofOptions: {
          from: "*"
          to: "clan_wars"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      clan_war_attack: {
        Args: {
          p_client_key?: string
          p_defender: string
          p_telegram_id: number
        }
        Returns: Json
      }
      clan_war_attack_team: { Args: { p_user: string }; Returns: Json }
      clan_war_cfg: { Args: never; Returns: Json }
      clan_war_current_season: {
        Args: never
        Returns: {
          code: string
          created_at: string
          ends_at: string
          id: string
          name: string
          starts_at: string
          status: string
          ton_prize_enabled: boolean
          ton_prize_ton: number
        }
        SetofOptions: {
          from: "*"
          to: "clan_war_seasons"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      clan_war_dashboard: { Args: { p_telegram_id: number }; Returns: Json }
      clan_war_fill_roster: {
        Args: {
          p_attacks: number
          p_clan: string
          p_size: number
          p_war: string
        }
        Returns: undefined
      }
      clan_war_join: { Args: { p_telegram_id: number }; Returns: Json }
      clan_war_league: { Args: { p_rating: number }; Returns: string }
      clan_war_league_multiplier: {
        Args: { p_league: string }
        Returns: number
      }
      clan_war_leave_queue: { Args: { p_telegram_id: number }; Returns: Json }
      clan_war_member_role: { Args: { p_user: string }; Returns: string }
      clan_war_roster_candidates: {
        Args: { p_telegram_id: number }
        Returns: Json
      }
      clan_war_sector_def: { Args: never; Returns: Json }
      clan_war_set_defense: {
        Args: { p_hero_ids: string[]; p_pet_id?: string; p_telegram_id: number }
        Returns: Json
      }
      clan_war_set_roster: {
        Args: { p_telegram_id: number; p_user_ids: string[] }
        Returns: Json
      }
      clan_war_settle: { Args: { p_war: string }; Returns: undefined }
      clan_war_tick: { Args: never; Returns: Json }
      clan_week_key: { Args: never; Returns: string }
      clan_weekly_cycle_ensure: {
        Args: { p_clan: string }
        Returns: {
          active_members: number
          clan_id: string
          created_at: string
          ends_at: string | null
          id: string
          started_at: string
          status: string
          target: number
          total_contribution: number
          updated_at: string
          week_key: string
        }
        SetofOptions: {
          from: "*"
          to: "clan_weekly_cycles"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      confirm_pass_locked_reward_order: {
        Args: { p_amount_nano: string; p_order_id: string; p_tx_hash: string }
        Returns: Json
      }
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
          p_deposit_type?: string
          p_from_wallet: string
          p_idempotency_key: string
          p_telegram_id: number
        }
        Returns: Json
      }
      credit_ton_reward: {
        Args: {
          p_amount_ton: number
          p_note?: string
          p_source_id?: string
          p_source_type: string
          p_user_id: string
        }
        Returns: Json
      }
      current_ton_fc_rate: { Args: never; Returns: number }
      debit_ton_balance: {
        Args: {
          p_amount_ton: number
          p_note?: string
          p_source_id?: string
          p_source_type: string
          p_user_id: string
        }
        Returns: Json
      }
      deliver_myth_sale_milestone_weapon: {
        Args: { p_code: string; p_user: string }
        Returns: undefined
      }
      deliver_myth_sale_milestones: {
        Args: { p_user: string }
        Returns: number
      }
      deliver_pet_egg_order: { Args: { p_order_id: string }; Returns: Json }
      detach_hero_everywhere: {
        Args: { p_hero: string; p_owner?: string }
        Returns: undefined
      }
      detach_pet_everywhere: {
        Args: { p_owner?: string; p_pet: string }
        Returns: undefined
      }
      device_access_blocked: {
        Args: { p_telegram_id: number }
        Returns: boolean
      }
      device_request_review: {
        Args: {
          p_device_hash: string
          p_message?: string
          p_telegram_id: number
        }
        Returns: Json
      }
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
          atk_multiplier: number
          boss_attack: number
          boss_background: string | null
          boss_defense: number
          boss_image: string | null
          boss_key: string
          boss_level: number
          boss_name: string
          boss_number: number | null
          boss_subtitle: string | null
          boss_theme: string | null
          created_at: string
          current_hp: number
          cycle_number: number
          defeated_at: string | null
          defense_multiplier: number
          distributed_at: string | null
          ended_reason: string | null
          ends_at: string | null
          hp_multiplier: number
          id: string
          max_hp: number
          minimum_damage_fixed: number
          minimum_damage_percent: number
          minimum_reward_fc: number
          participants: number
          rank_bonus: Json
          rank_bonus_enabled: boolean
          reward_pool_fc: number
          rotation_number: number
          starts_at: string
          status: string
          template_id: string | null
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
      equip_hero_equipment: {
        Args: {
          p_hero_id: string
          p_instance_id: string
          p_telegram_id: number
        }
        Returns: Json
      }
      equipment_class_ok: {
        Args: { p_archetype: string; p_hero_class: string }
        Returns: boolean
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
          p_currency?: string
          p_idempotency_key: string
          p_player_pet_id: string
          p_telegram_id: number
        }
        Returns: Json
      }
      expedition_attempt_row: {
        Args: { p_lock?: boolean; p_mission_id: string; p_user_id: string }
        Returns: {
          created_at: string
          extra_available: number
          fc_extra_purchases_used: number
          free_used: number
          mission_id: string
          period: string
          rewarded_ads_used: number
          updated_at: string
          user_id: string
        }
        SetofOptions: {
          from: "*"
          to: "expedition_attempts"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      expedition_boost_ad_begin: {
        Args: { p_expedition_id: string; p_telegram_id: number }
        Returns: Json
      }
      expedition_boost_ad_claim: {
        Args: { p_telegram_id: number; p_view_id: string }
        Returns: Json
      }
      expedition_boost_limit: { Args: never; Returns: number }
      expedition_claim: {
        Args: { p_expedition_id: string; p_telegram_id: number }
        Returns: Json
      }
      expedition_extra_ad_begin: {
        Args: { p_mission_id: string; p_telegram_id: number }
        Returns: Json
      }
      expedition_extra_ad_claim: {
        Args: { p_telegram_id: number; p_view_id: string }
        Returns: Json
      }
      expedition_extra_buy_fc: {
        Args: {
          p_idempotency_key: string
          p_mission_id: string
          p_telegram_id: number
        }
        Returns: Json
      }
      expedition_extra_price_fc: { Args: { p_rarity: string }; Returns: number }
      expedition_limits: { Args: never; Returns: Json }
      expedition_mission_attempts: {
        Args: { p_mission_id: string; p_user_id: string }
        Returns: Json
      }
      expedition_start: {
        Args: {
          p_mission_id: string
          p_pet_ids: string[]
          p_telegram_id: number
        }
        Returns: Json
      }
      expedition_state: { Args: { p_telegram_id: number }; Returns: Json }
      expedition_success_chance: {
        Args: { p_bonus: number; p_power: number; p_required: number }
        Returns: number
      }
      expire_stale_pet_egg_orders: {
        Args: { p_user_id?: string }
        Returns: number
      }
      familiar_hunt_grant: {
        Args: { p_reward: Json; p_user: string }
        Returns: Json
      }
      familiar_hunt_mark_paid: {
        Args: {
          p_amount_nano: number
          p_instance_id: string
          p_tx_hash: string
        }
        Returns: Json
      }
      familiar_hunt_pending_payments: {
        Args: { p_telegram_id: number }
        Returns: Json
      }
      familiar_hunt_resolve: { Args: { p_instance_id: string }; Returns: Json }
      familiar_hunt_roll_loot: {
        Args: { p_is_boss?: boolean; p_pool: string; p_user: string }
        Returns: Json
      }
      familiar_hunt_stage_def: { Args: { p_stage: number }; Returns: Json }
      familiar_hunt_start: {
        Args: {
          p_currency?: string
          p_idempotency_key?: string
          p_pet_ids: string[]
          p_telegram_id: number
        }
        Returns: Json
      }
      familiar_hunt_state: { Args: { p_telegram_id: number }; Returns: Json }
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
      founder_frame_set: {
        Args: { p_equipped: boolean; p_telegram_id: number }
        Returns: Json
      }
      founder_pack_confirm_order: {
        Args: { p_amount_nano: string; p_order_id: string; p_tx_hash: string }
        Returns: Json
      }
      founder_pack_deliver: { Args: { p_purchase_id: string }; Returns: Json }
      founder_pack_pass_season: {
        Args: { p_snapshot: Json; p_user_id: string }
        Returns: string
      }
      founder_pack_pending_orders: {
        Args: { p_telegram_id: number }
        Returns: Json
      }
      founder_pack_settings: {
        Args: never
        Returns: {
          badge_enabled: boolean
          eligibility_days: number
          enabled: boolean
          ends_at: string | null
          equipment_chest_code: string
          fragments: number
          frame_enabled: boolean
          hero_daily_myth: number
          hero_key: string
          id: boolean
          legendary_chests: number
          myth_amount: number
          pack_version: number
          pass_tier: string
          pet_daily_myth: number
          pet_slug: string
          popup_enabled: boolean
          popup_frequency: string
          popup_priority: number
          price_ton: number
          require_new_account: boolean
          resource_chest: Json
          resource_chest_code: string
          signup_from: string
          start_at: string
          updated_at: string
          weapon_code: string | null
        }
        SetofOptions: {
          from: "*"
          to: "founder_pack_config"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      founder_pack_snapshot: { Args: never; Returns: Json }
      founder_pack_start_purchase: {
        Args: {
          p_idempotency_key: string
          p_telegram_id: number
          p_wallet_address: string
        }
        Returns: Json
      }
      founder_pack_state: { Args: { p_telegram_id: number }; Returns: Json }
      fragment_summon_config: { Args: never; Returns: Json }
      fuse_heroes: {
        Args: {
          p_fee_currency?: string
          p_idempotency_key?: string
          p_main_hero_id: string
          p_material_ids?: string[]
          p_telegram_id: number
          p_use_fragments?: boolean
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
      get_activity_progress: { Args: { p_telegram_id: number }; Returns: Json }
      get_ad_rewards: { Args: { p_telegram_id: number }; Returns: Json }
      get_boss_combat: { Args: { p_telegram_id: number }; Returns: Json }
      get_calendar_dashboard: { Args: { p_telegram_id: number }; Returns: Json }
      get_campaign_popup: { Args: { p_telegram_id: number }; Returns: Json }
      get_channel_rewards: { Args: { p_telegram_id: number }; Returns: Json }
      get_clan_boss: { Args: { p_telegram_id: number }; Returns: Json }
      get_clan_dashboard: { Args: { p_telegram_id: number }; Returns: Json }
      get_community_pool_dashboard: {
        Args: { p_telegram_id: number }
        Returns: Json
      }
      get_community_pool_ranking_with_estimates: {
        Args: { p_pool_id?: string }
        Returns: {
          avatar_url: string
          eligible: boolean
          estimated_ranking_reward_ton: number
          points: number
          raffle_weight: number
          rank_position: number
          user_id: string
          username: string
        }[]
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
      get_hero_mining_state: { Args: { p_telegram_id: number }; Returns: Json }
      get_hero_shop_config: { Args: never; Returns: Json }
      get_myth_sale_dashboard: {
        Args: { p_telegram_id: number }
        Returns: Json
      }
      get_myth_staking_dashboard: {
        Args: { p_telegram_id: number }
        Returns: Json
      }
      get_myth_utility_state: { Args: { p_telegram_id: number }; Returns: Json }
      get_myth_wallet: { Args: { p_telegram_id: number }; Returns: Json }
      get_name_mission_state: { Args: { p_telegram_id: number }; Returns: Json }
      get_partner_channels: { Args: { p_telegram_id: number }; Returns: Json }
      get_pet_admin_stats: { Args: never; Returns: Json }
      get_pet_bonuses: { Args: { p_user: string }; Returns: Json }
      get_pet_dashboard: { Args: { p_telegram_id: number }; Returns: Json }
      get_pet_egg_opening: {
        Args: { p_opening_id: string; p_telegram_id: number }
        Returns: Json
      }
      get_pet_egg_store: { Args: { p_telegram_id: number }; Returns: Json }
      get_pet_pvp_snapshot: { Args: { p_user: string }; Returns: Json }
      get_player_entitlements: {
        Args: { p_telegram_id: number }
        Returns: Json
      }
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
      get_spending_event_dashboard: {
        Args: { p_limit?: number; p_telegram_id: number }
        Returns: Json
      }
      get_spending_event_popup: {
        Args: { p_telegram_id: number }
        Returns: Json
      }
      get_spending_event_ranking: {
        Args: { p_event_id: string; p_limit?: number; p_offset?: number }
        Returns: Json
      }
      get_starter_pack_status: {
        Args: { p_telegram_id: number }
        Returns: Json
      }
      get_ton_wallet: { Args: { p_telegram_id: number }; Returns: Json }
      get_tower_dashboard: { Args: { p_telegram_id: number }; Returns: Json }
      get_tower_ranking: {
        Args: { p_limit?: number; p_telegram_id: number }
        Returns: Json
      }
      get_wallet_summary: { Args: { p_telegram_id: number }; Returns: Json }
      global_boss_auto_attack_state_json: {
        Args: { p_user: string }
        Returns: Json
      }
      global_boss_auto_pass_tier: { Args: { p_user: string }; Returns: string }
      global_boss_catchup_seconds: { Args: { p_user: string }; Returns: number }
      global_boss_damage_factor: {
        Args: { p_defense: number }
        Returns: number
      }
      global_boss_difficulty: { Args: never; Returns: Json }
      global_boss_effective_stats: { Args: { p_number: number }; Returns: Json }
      global_boss_overlay: { Args: { p_user: string }; Returns: Json }
      global_boss_reapply_difficulty: { Args: never; Returns: Json }
      global_boss_setting_num: {
        Args: { p_default: number; p_key: string }
        Returns: number
      }
      global_boss_template_for_number: {
        Args: { p_number: number }
        Returns: {
          background_url: string | null
          base_attack: number
          base_defense: number
          boss_level: number
          boss_number: number
          code: string
          created_at: string
          duration_seconds: number
          enabled: boolean
          id: string
          image_url: string | null
          max_hp: number
          name: string
          reward_fc: number
          sort_order: number
          subtitle: string | null
          theme: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "global_boss_templates"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      grant_clan_xp: {
        Args: { p_amount?: number; p_source: string; p_user_id: string }
        Returns: undefined
      }
      grant_hero_xp: {
        Args: {
          p_activity: string
          p_hero_ids?: string[]
          p_reference_id: string
          p_user_id: string
        }
        Returns: Json
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
      hero_activity_team_ids: {
        Args: { p_activity: string; p_user_id: string }
        Returns: string[]
      }
      hero_boss_stats: {
        Args: { p_player_hero_id: string }
        Returns: {
          base_atk: number
          base_hp: number
          final_atk: number
          max_hp: number
        }[]
      }
      hero_effective_real_summon_odds: { Args: never; Returns: Json }
      hero_effective_summon_odds: { Args: never; Returns: Json }
      hero_equipment_json: {
        Args: { p_hero_id: string; p_telegram_id: number }
        Returns: Json
      }
      hero_fusion_config: { Args: never; Returns: Json }
      hero_fusion_material_available: {
        Args: { p_hero_id: string }
        Returns: boolean
      }
      hero_fusion_multiplier: { Args: { p_stars: number }; Returns: number }
      hero_fusion_required_copies: {
        Args: { p_stars: number }
        Returns: number
      }
      hero_max_level: { Args: { p_stars: number }; Returns: number }
      hero_mining_accrue: { Args: { p_user_id: string }; Returns: number }
      hero_mining_currency: { Args: never; Returns: string }
      hero_mining_effective_daily: {
        Args: { p_nft_hero_id: string; p_rarity: string }
        Returns: number
      }
      hero_mining_enabled: { Args: never; Returns: boolean }
      hero_mining_hero_dual: {
        Args: { p_nft_hero_id: string }
        Returns: boolean
      }
      hero_mining_hero_myth_rate: {
        Args: { p_nft_hero_id: string; p_rarity: string }
        Returns: number
      }
      hero_mining_hero_rate: {
        Args: { p_nft_hero_id: string; p_rarity: string }
        Returns: number
      }
      hero_mining_instance_rate: {
        Args: { p_hero_id: string }
        Returns: number
      }
      hero_mining_myth_per_day: { Args: never; Returns: number }
      hero_mining_rarity_eligible: {
        Args: { p_rarity: string }
        Returns: boolean
      }
      hero_mining_rate: { Args: { p_rarity: string }; Returns: number }
      hero_mining_register_investment: {
        Args: {
          p_amount_ton: number
          p_reference: string
          p_source_type: string
          p_user_id: string
        }
        Returns: number
      }
      hero_mining_remaining: { Args: { p_user_id: string }; Returns: number }
      hero_mining_revoke_investment: {
        Args: { p_reference: string }
        Returns: undefined
      }
      hero_mining_row_rate: {
        Args: { p_nft_hero_id: string; p_override: number; p_rarity: string }
        Returns: number
      }
      hero_mining_settle_all: { Args: never; Returns: Json }
      hero_mining_sync_invested: {
        Args: { p_user_id: string }
        Returns: number
      }
      hero_nft_class_mult: {
        Args: { p_archetype: string }
        Returns: {
          atk_mult: number
          crit_bonus: number
          def_mult: number
          hp_mult: number
          skill_mult: number
          speed_bonus: number
        }[]
      }
      hero_power_value: {
        Args: { p_atk: number; p_def: number; p_hp: number; p_level: number }
        Returns: number
      }
      hero_progression_config: { Args: never; Returns: Json }
      hero_progression_json: { Args: { p_user_id: string }; Returns: Json }
      hero_rarity_fusion_config: { Args: never; Returns: Json }
      hero_rarity_mid_atk: { Args: { r: string }; Returns: number }
      hero_rarity_mid_hp: { Args: { r: string }; Returns: number }
      hero_rarity_recruitable: { Args: { p_rarity: string }; Returns: boolean }
      hero_real_summon_rates: { Args: never; Returns: Json }
      hero_recalc_equipment: { Args: { p_hero: string }; Returns: undefined }
      hero_recruit_price: { Args: { p_count: number }; Returns: number }
      hero_recruit_rarity_flags: { Args: never; Returns: Json }
      hero_stat_ranges: {
        Args: { p_rarity: string }
        Returns: {
          max_ag: number
          max_atk: number
          max_hg: number
          max_hp: number
          min_ag: number
          min_atk: number
          min_hg: number
          min_hp: number
        }[]
      }
      hero_summon_rates: { Args: never; Returns: Json }
      hero_usage_status: { Args: { p_hero_id: string }; Returns: Json }
      hero_xp_last_award: {
        Args: { p_activity?: string; p_user_id: string }
        Returns: Json
      }
      hero_xp_to_next: { Args: { p_level: number }; Returns: number }
      is_valid_ton_address: { Args: { p_address: string }; Returns: boolean }
      join_clan: {
        Args: { p_clan_id: string; p_telegram_id: number }
        Returns: Json
      }
      key_chest_grant_hero_xp: {
        Args: { p_amount: number; p_user: string }
        Returns: Json
      }
      key_chest_grant_reward: {
        Args: {
          p_amount: number
          p_code: string
          p_type: string
          p_user: string
        }
        Returns: Json
      }
      leave_clan: { Args: { p_telegram_id: number }; Returns: Json }
      list_premium_titles: { Args: never; Returns: Json }
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
      mark_campaign_popup: {
        Args: { p_action: string; p_campaign_id: string; p_telegram_id: number }
        Returns: Json
      }
      mark_notifications_read: {
        Args: { p_ids?: string[]; p_telegram_id: number }
        Returns: Json
      }
      mark_spending_event_popup_seen: {
        Args: { p_telegram_id: number }
        Returns: Json
      }
      market_account_days: { Args: { p_user: string }; Returns: number }
      market_active_days: { Args: { p_user: string }; Returns: number }
      market_assert_hero_sellable: {
        Args: { p_hero_id: string }
        Returns: undefined
      }
      market_auction_exclusive_item: {
        Args: { p_item_type: string; p_rarity: string }
        Returns: boolean
      }
      market_audit_unpaid_fc_sales: { Args: never; Returns: Json }
      market_browse: {
        Args: {
          p_currency?: string
          p_item_type?: string
          p_limit?: number
          p_offset?: number
          p_rarity?: string
          p_sort?: string
          p_telegram_id: number
        }
        Returns: Json
      }
      market_buy_listing: {
        Args: { p_listing_id: string; p_telegram_id: number }
        Returns: Json
      }
      market_can_access: { Args: { p_telegram_id: number }; Returns: boolean }
      market_cancel_listing: {
        Args: { p_listing_id: string; p_telegram_id: number }
        Returns: Json
      }
      market_cancel_payment_intent: {
        Args: { p_payment_id: string; p_telegram_id: number }
        Returns: Json
      }
      market_confirm_payment_intent: {
        Args: { p_amount_nano: number; p_payment_id: string; p_tx_hash: string }
        Returns: Json
      }
      market_create_listing: {
        Args: {
          p_currency?: string
          p_item_code: string
          p_item_instance_id: string
          p_item_type: string
          p_price_fc?: number
          p_price_ton?: number
          p_quantity?: number
          p_telegram_id: number
        }
        Returns: Json
      }
      market_create_payment_intent: {
        Args: {
          p_listing_id: string
          p_telegram_id: number
          p_wallet_address: string
        }
        Returns: Json
      }
      market_equipment_details_json: {
        Args: { p_equipment_id: string }
        Returns: Json
      }
      market_expire_payment_intents: { Args: never; Returns: number }
      market_finalize_purchase: {
        Args: {
          p_buyer: string
          p_external?: boolean
          p_listing_id: string
          p_tx_hash?: string
        }
        Returns: Json
      }
      market_get_sellable: { Args: { p_telegram_id: number }; Returns: Json }
      market_hero_details_json: { Args: { p_hero_id: string }; Returns: Json }
      market_hero_locks: {
        Args: { p_hero: Database["public"]["Tables"]["player_heroes"]["Row"] }
        Returns: Json
      }
      market_is_bypass_admin: {
        Args: { p_telegram_id: number }
        Returns: boolean
      }
      market_item_details: {
        Args: { p_id: string; p_source: string; p_telegram_id: number }
        Returns: Json
      }
      market_item_give: {
        Args: { p_code: string; p_qty: number; p_snap: Json; p_user: string }
        Returns: undefined
      }
      market_item_take: {
        Args: { p_code: string; p_qty: number; p_user: string }
        Returns: Json
      }
      market_min_price_ton: {
        Args: { p_item_type: string; p_rarity: string }
        Returns: number
      }
      market_my_listings: { Args: { p_telegram_id: number }; Returns: Json }
      market_payment_status: {
        Args: { p_payment_id: string; p_telegram_id: number }
        Returns: Json
      }
      market_pending_payment_intents: {
        Args: { p_max_age_minutes?: number }
        Returns: {
          amount_nano: number
          buyer_user_id: string
          created_at: string
          listing_id: string
          payment_address: string
          payment_comment: string
          payment_id: string
        }[]
      }
      market_pet_details_json: {
        Args: { p_player_pet_id: string }
        Returns: Json
      }
      market_price_quote: {
        Args: {
          p_item_code?: string
          p_item_instance_id?: string
          p_item_type: string
          p_telegram_id: number
        }
        Returns: Json
      }
      market_price_range: {
        Args: {
          p_currency?: string
          p_item_type: string
          p_level?: number
          p_rarity: string
        }
        Returns: Json
      }
      market_repair_unpaid_fc_sales: { Args: never; Returns: Json }
      market_reverse_transaction: {
        Args: {
          p_admin_id?: number
          p_reason?: string
          p_transaction_id: string
        }
        Returns: Json
      }
      market_risk_assess: {
        Args: {
          p_buyer: string
          p_listing: Database["public"]["Tables"]["market_listings"]["Row"]
          p_seller: string
        }
        Returns: Json
      }
      market_run_settlements: { Args: never; Returns: number }
      market_sell_eligibility: { Args: { p_user: string }; Returns: Json }
      market_seller_label: { Args: { p_user: string }; Returns: string }
      market_settings_json: { Args: never; Returns: Json }
      market_settle_transaction: {
        Args: { p_admin_id?: number; p_transaction_id: string }
        Returns: Json
      }
      market_shares_wallet: {
        Args: { p_a: string; p_b: string }
        Returns: boolean
      }
      market_stack_details_json: {
        Args: { p_item_code: string; p_snapshot: Json }
        Returns: Json
      }
      market_status: { Args: { p_telegram_id: number }; Returns: Json }
      market_status_json: { Args: never; Returns: Json }
      market_user_wallets: {
        Args: { p_user: string }
        Returns: {
          address: string
        }[]
      }
      marketing_pool_categories: { Args: never; Returns: string[] }
      marketing_pool_dashboard: { Args: { p_limit?: number }; Returns: Json }
      min_withdraw_ton: { Args: never; Returns: number }
      myth_confirm_payment_intent: {
        Args: { p_amount_nano: number; p_payment_id: string; p_tx_hash: string }
        Returns: Json
      }
      myth_expire_payment_intents: { Args: never; Returns: number }
      myth_mining_pool_available: { Args: never; Returns: number }
      myth_pending_payment_intents: {
        Args: { p_max_age_minutes?: number }
        Returns: {
          amount_nano: number
          created_at: string
          id: string
          myth_amount: number
          payment_comment: string
          user_id: string
        }[]
      }
      myth_purchase_total: { Args: { p_user: string }; Returns: number }
      myth_sale_stats: { Args: never; Returns: Json }
      myth_stake: {
        Args: {
          p_amount: number
          p_idempotency_key: string
          p_plan: string
          p_telegram_id: number
        }
        Returns: Json
      }
      myth_staked_amount: { Args: { p_user: string }; Returns: number }
      myth_staking_accrue: {
        Args: { p_position_id: string }
        Returns: undefined
      }
      myth_staking_accrue_user: {
        Args: { p_user_id: string }
        Returns: undefined
      }
      myth_staking_claim: {
        Args: {
          p_idempotency_key: string
          p_position_id: string
          p_telegram_id: number
        }
        Returns: Json
      }
      myth_staking_fee_percent: { Args: never; Returns: number }
      myth_staking_fee_threshold: { Args: never; Returns: number }
      myth_start_purchase: {
        Args: {
          p_idempotency_key?: string
          p_myth_amount: number
          p_telegram_id: number
          p_wallet_address?: string
        }
        Returns: Json
      }
      myth_unstake: {
        Args: {
          p_idempotency_key: string
          p_position_id: string
          p_telegram_id: number
        }
        Returns: Json
      }
      myth_utility_charge: {
        Args: {
          p_amount: number
          p_feature: string
          p_idempotency_key?: string
          p_meta?: Json
          p_source_id?: string
          p_user: string
        }
        Returns: Json
      }
      myth_utility_config: { Args: never; Returns: Json }
      myth_utility_price: {
        Args: { p_fc?: number; p_feature: string; p_ton?: number }
        Returns: number
      }
      mythic_power_pack_confirm_order: {
        Args: { p_amount_nano: string; p_order_id: string; p_tx_hash: string }
        Returns: Json
      }
      mythic_power_pack_deliver: {
        Args: { p_purchase_id: string }
        Returns: Json
      }
      mythic_power_pack_settings: {
        Args: never
        Returns: {
          enabled: boolean
          ends_at: string | null
          equipment_chest_code: string
          equipment_chests: number
          eternity_keys: number
          first_bonus_key_code: string
          first_bonus_myth: number
          hero_xp: number
          id: boolean
          myth_reward: number
          mythic_egg_slug: string
          mythic_eggs: number
          package_version: string
          pet_food_code: string
          pet_food_quantity: number
          popup_enabled: boolean
          popup_frequency: string
          popup_priority: number
          price_ton: number
          pvp_tickets: number
          reward_configuration_version: number
          sales_paused: boolean
          start_at: string | null
          universal_fragments: number
          updated_at: string
          void_chests: number
          void_keys: number
        }
        SetofOptions: {
          from: "*"
          to: "mythic_power_pack_config"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      mythic_power_pack_start_purchase: {
        Args: {
          p_idempotency_key: string
          p_telegram_id: number
          p_wallet_address: string
        }
        Returns: Json
      }
      mythic_power_pack_state: {
        Args: { p_telegram_id: number }
        Returns: Json
      }
      name_mission_config: { Args: never; Returns: Json }
      name_mission_matches: {
        Args: { p_display_name: string; p_hashtag: string }
        Returns: boolean
      }
      nft_assign_unit: {
        Args: { p_nft_id: string; p_source?: string; p_user_id: string }
        Returns: Json
      }
      nft_breeding_block_reason: { Args: { p_nft_id: string }; Returns: string }
      nft_breeding_expire_stale: { Args: never; Returns: number }
      nft_breeding_pay: {
        Args: {
          p_idempotency_key: string
          p_request_id: string
          p_telegram_id: number
        }
        Returns: Json
      }
      nft_breeding_request_create: {
        Args: {
          p_my_nft_id: string
          p_partner_nft_id: string
          p_telegram_id: number
        }
        Returns: Json
      }
      nft_breeding_respond: {
        Args: { p_accept: boolean; p_request_id: string; p_telegram_id: number }
        Returns: Json
      }
      nft_breeding_search_partner: {
        Args: { p_query: string; p_telegram_id: number }
        Returns: Json
      }
      nft_breeding_state: { Args: { p_telegram_id: number }; Returns: Json }
      nft_buy_with_balance: {
        Args: {
          p_idempotency_key: string
          p_nft_id: string
          p_telegram_id: number
        }
        Returns: Json
      }
      nft_claim_position: {
        Args: { p_position_id: string; p_telegram_id: number }
        Returns: Json
      }
      nft_claim_reward: { Args: { p_telegram_id: number }; Returns: Json }
      nft_confirm_purchase: {
        Args: { p_amount_nano: string; p_order_id: string; p_tx_hash: string }
        Returns: Json
      }
      nft_create_order: {
        Args: {
          p_idempotency_key: string
          p_nft_id: string
          p_telegram_id: number
        }
        Returns: Json
      }
      nft_deliver_order: { Args: { p_order_id: string }; Returns: Json }
      nft_effective_daily: {
        Args: {
          p_position: Database["public"]["Tables"]["nft_yield_positions"]["Row"]
        }
        Returns: number
      }
      nft_effective_daily_myth: {
        Args: {
          p_position: Database["public"]["Tables"]["nft_yield_positions"]["Row"]
        }
        Returns: number
      }
      nft_equipment_assign_unit: {
        Args: { p_nft_id: string; p_source?: string; p_user_id: string }
        Returns: Json
      }
      nft_equipment_buy_with_balance: {
        Args: {
          p_idempotency_key: string
          p_nft_id: string
          p_telegram_id: number
        }
        Returns: Json
      }
      nft_equipment_confirm_purchase: {
        Args: { p_amount_nano: string; p_order_id: string; p_tx_hash: string }
        Returns: Json
      }
      nft_equipment_create_order: {
        Args: {
          p_idempotency_key: string
          p_nft_id: string
          p_telegram_id: number
        }
        Returns: Json
      }
      nft_equipment_deliver_order: {
        Args: { p_order_id: string }
        Returns: Json
      }
      nft_equipment_reconcile_orders: {
        Args: { p_telegram_id: number }
        Returns: Json
      }
      nft_equipment_shop_json: {
        Args: { p_telegram_id: number }
        Returns: Json
      }
      nft_hero_assign_unit: {
        Args: { p_nft_id: string; p_source?: string; p_user_id: string }
        Returns: Json
      }
      nft_hero_buy_with_balance: {
        Args: {
          p_idempotency_key: string
          p_nft_id: string
          p_telegram_id: number
        }
        Returns: Json
      }
      nft_hero_confirm_purchase: {
        Args: { p_amount_nano: string; p_order_id: string; p_tx_hash: string }
        Returns: Json
      }
      nft_hero_create_order: {
        Args: {
          p_idempotency_key: string
          p_nft_id: string
          p_telegram_id: number
        }
        Returns: Json
      }
      nft_hero_deliver_order: { Args: { p_order_id: string }; Returns: Json }
      nft_hero_my_json: { Args: { p_telegram_id: number }; Returns: Json }
      nft_hero_reconcile_orders: {
        Args: { p_telegram_id: number }
        Returns: Json
      }
      nft_hero_shop_json: { Args: { p_telegram_id: number }; Returns: Json }
      nft_my_reward: { Args: { p_telegram_id: number }; Returns: Json }
      nft_my_rewards_json: { Args: { p_telegram_id: number }; Returns: Json }
      nft_pool_accrue: { Args: never; Returns: Json }
      nft_pool_health: { Args: never; Returns: string }
      nft_pool_settings_row: {
        Args: never
        Returns: {
          accrual_enabled: boolean
          health_days: Json
          health_factors: Json
          id: boolean
          min_claim_ton: number
          roi_multiplier: number
          tier20_daily_ton: number
          tier30_daily_ton: number
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "nft_pool_settings"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      nft_pool_settle_payment: { Args: { p_amount: number }; Returns: number }
      nft_pool_sync_positions: { Args: never; Returns: number }
      nft_reconcile_orders: { Args: { p_telegram_id: number }; Returns: Json }
      nft_refill_stock: {
        Args: { p_admin_id?: number; p_kind: string }
        Returns: Json
      }
      nft_reserve_publish: {
        Args: { p_admin_id?: number; p_kind: string; p_limit?: number }
        Returns: Json
      }
      nft_reserve_stock_json: { Args: never; Returns: Json }
      nft_rotation_after_sale: { Args: { p_kind: string }; Returns: undefined }
      nft_shop_json: { Args: { p_telegram_id: number }; Returns: Json }
      nft_stock_json: { Args: { p_kind?: string }; Returns: Json }
      nft_yield_override_allowed: { Args: never; Returns: boolean }
      normalize_hero_rarity: { Args: { value: string }; Returns: string }
      normalize_language_code: { Args: { p_code: string }; Returns: string }
      normalize_pet_rarity: { Args: { v: string }; Returns: string }
      open_calendar_hero_chest: {
        Args: { p_inventory_item_id: string; p_telegram_id: number }
        Returns: Json
      }
      open_exclusive_chest: {
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
      open_key_chest: {
        Args: { p_inventory_item_id: string; p_telegram_id: number }
        Returns: Json
      }
      open_legend_chest: {
        Args: { p_inventory_item_id: string; p_telegram_id: number }
        Returns: Json
      }
      open_resource_chest: {
        Args: { p_inventory_item_id: string; p_telegram_id: number }
        Returns: Json
      }
      open_season_mythic_egg: {
        Args: { p_item_id: string; p_telegram_id: number }
        Returns: Json
      }
      partner_channel_visit: {
        Args: { p_partner_id: string; p_telegram_id: number }
        Returns: Json
      }
      partner_validation_target: {
        Args: { p_partner_id: string }
        Returns: Json
      }
      pass_audience_allows: {
        Args: { p_user_id: string; p_version_id: string }
        Returns: boolean
      }
      pass_exclusive_myth_rate: { Args: never; Returns: number }
      pass_has_incomplete_paid: {
        Args: { p_exclude_season: string; p_user_id: string }
        Returns: boolean
      }
      pass_locked_reward_config: { Args: never; Returns: Json }
      pass_locked_reward_deliver: {
        Args: { p_order_id: string }
        Returns: Json
      }
      pass_reward_asset_ok: {
        Args: {
          p_reward: Database["public"]["Tables"]["season_pass_rewards"]["Row"]
        }
        Returns: boolean
      }
      pass_type_completed: {
        Args: { p_pass_type: string; p_user_id: string }
        Returns: boolean
      }
      pass_user_is_admin: { Args: { p_user_id: string }; Returns: boolean }
      pass_user_season_id: { Args: { p_user_id: string }; Returns: string }
      pass_version_activate_season: {
        Args: { p_admin_id?: number; p_season_id: string }
        Returns: Json
      }
      pass_version_info: {
        Args: { p_season_id: string; p_user_id: string }
        Returns: Json
      }
      pass_version_rewards_status: {
        Args: { p_season_id: string }
        Returns: Json
      }
      pass_versions_apply_due: { Args: never; Returns: undefined }
      pass_versions_run_scheduled: { Args: never; Returns: Json }
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
      pending_pass_locked_reward_orders: {
        Args: { p_telegram_id: number }
        Returns: Json[]
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
      pet_buff_cap: { Args: { p_key: string }; Returns: number }
      pet_effective_buff: {
        Args: {
          p_base: number
          p_key: string
          p_level: number
          p_rarity: string
          p_stage: number
        }
        Returns: number
      }
      pet_egg_buy_with_balance: {
        Args: {
          p_egg_id: string
          p_idempotency_key: string
          p_telegram_id: number
        }
        Returns: Json
      }
      pet_egg_move_from_inventory: {
        Args: { p_egg_id: string; p_user_id: string }
        Returns: boolean
      }
      pet_evolution_cost: { Args: { r: string; v: number }; Returns: number }
      pet_evolution_stage: { Args: { v: number }; Returns: string }
      pet_hatch_result_json: {
        Args: {
          p_history: Database["public"]["Tables"]["pet_hatch_history"]["Row"]
        }
        Returns: Json
      }
      pet_hp_bonus_percent: { Args: { p_buffs: Json }; Returns: number }
      pet_instance_power: { Args: { p_player_pet_id: string }; Returns: number }
      pet_level_xp_required: { Args: { p_level: number }; Returns: number }
      pet_max_level: { Args: never; Returns: number }
      pet_premium_effective_buff: {
        Args: {
          p_base: number
          p_evolution_tier: number
          p_level: number
          p_rarity: string
        }
        Returns: number
      }
      pet_rarity_base_power: {
        Args: { p_is_nft?: boolean; p_rarity: string }
        Returns: number
      }
      pet_rarity_multiplier: { Args: { v: string }; Returns: number }
      pet_rarity_order: { Args: { v: string }; Returns: number }
      pet_reset_transfer_xp: {
        Args: {
          p_idempotency_key: string
          p_source_player_pet_id: string
          p_target_player_pet_id: string
          p_telegram_id: number
        }
        Returns: Json
      }
      pet_stage_buff_multiplier: { Args: { p_stage: number }; Returns: number }
      pet_stage_index: {
        Args: { p_level: number; p_tier?: number }
        Returns: number
      }
      pet_stage_power_multiplier: { Args: { p_stage: number }; Returns: number }
      pet_tier_multiplier: { Args: { p_tier: number }; Returns: number }
      pet_total_xp: { Args: { p_level: number; p_xp: number }; Returns: number }
      pet_visual_image: {
        Args: { p_level: number; p_pet_id: string }
        Returns: string
      }
      pet_visual_index: { Args: { p_level: number }; Returns: number }
      pet_xp_capacity: {
        Args: { p_level: number; p_xp: number }
        Returns: number
      }
      pet_xp_required: { Args: { v: number }; Returns: number }
      pet_xp_transfer_cost: { Args: { p_level: number }; Returns: number }
      pet_xp_transfer_preview: {
        Args: { p_player_pet_id: string; p_telegram_id: number }
        Returns: Json
      }
      pick_pet_for_source: {
        Args: {
          p_rarity: string
          p_seed: string
          p_source_key: string
          p_source_type: string
        }
        Returns: string
      }
      player_owns_any_nft: { Args: { p_user_id: string }; Returns: boolean }
      player_pet_buffs: { Args: { p_player_pet_id: string }; Returns: Json }
      player_pet_json: { Args: { p_player_pet_id: string }; Returns: Json }
      player_ton_deposit_total: { Args: { p_user_id: string }; Returns: number }
      player_ton_withdraw_locked: {
        Args: { p_user_id: string }
        Returns: number
      }
      pool_credit_pending_rewards: {
        Args: { p_history_id: string }
        Returns: Json
      }
      pool_eligibility: { Args: { p_user_id: string }; Returns: Json }
      pool_ranking_allocation: {
        Args: { p_participants: number; p_ranking_total: number }
        Returns: {
          amount_nanoton: number
          amount_ton: number
          rank_position: number
        }[]
      }
      pool_ranking_distribution_status: {
        Args: { p_participants?: number; p_ranking_total?: number }
        Returns: Json
      }
      pool_ranking_share: { Args: { p_pos: number }; Returns: number }
      pool_record_revenue: {
        Args: {
          p_amount_ton: number
          p_source_id: string
          p_source_type: string
          p_user_id: string
        }
        Returns: undefined
      }
      premium_offer_day_key: { Args: never; Returns: string }
      premium_offer_frequency_days: {
        Args: { p_frequency: string }
        Returns: number
      }
      premium_offer_impression_event: {
        Args: { p_event: string; p_offer_id: string; p_telegram_id: number }
        Returns: Json
      }
      premium_offer_popup_confirm_shown: {
        Args: { p_offer_id: string; p_telegram_id: number }
        Returns: Json
      }
      premium_offer_popup_mark: {
        Args: {
          p_dismissed?: boolean
          p_offer_type: string
          p_telegram_id: number
        }
        Returns: Json
      }
      premium_offer_popup_reserve: {
        Args: { p_telegram_id: number }
        Returns: Json
      }
      premium_offer_timezone: { Args: never; Returns: string }
      premium_offers_state: { Args: { p_telegram_id: number }; Returns: Json }
      private_trade_add_item: {
        Args: {
          p_instance_id: string
          p_item_code: string
          p_item_type: string
          p_quantity?: number
          p_telegram_id: number
          p_trade: string
        }
        Returns: Json
      }
      private_trade_assets: { Args: { p_telegram_id: number }; Returns: Json }
      private_trade_cancel: {
        Args: { p_reason?: string; p_telegram_id: number; p_trade: string }
        Returns: Json
      }
      private_trade_confirm: {
        Args: { p_request_id?: string; p_telegram_id: number; p_trade: string }
        Returns: Json
      }
      private_trade_create: {
        Args: { p_query: string; p_request_id?: string; p_telegram_id: number }
        Returns: Json
      }
      private_trade_escrow_deliver: {
        Args: {
          p_fc: number
          p_from: string
          p_myth: number
          p_to: string
          p_ton: number
          p_trade: string
        }
        Returns: undefined
      }
      private_trade_escrow_lock: {
        Args: {
          p_fc: number
          p_myth: number
          p_ton: number
          p_trade: string
          p_user: string
        }
        Returns: undefined
      }
      private_trade_escrow_release: {
        Args: {
          p_fc: number
          p_myth: number
          p_ton: number
          p_trade: string
          p_user: string
        }
        Returns: undefined
      }
      private_trade_expire_sweep: { Args: never; Returns: number }
      private_trade_guard: { Args: { p_telegram_id: number }; Returns: string }
      private_trade_high_rarity: {
        Args: { p_rarity: string }
        Returns: boolean
      }
      private_trade_item_value: {
        Args: {
          p_nft?: boolean
          p_qty: number
          p_rarity: string
          p_type: string
        }
        Returns: number
      }
      private_trade_ledger_ref: {
        Args: { p_trade: string; p_user: string }
        Returns: string
      }
      private_trade_list: { Args: { p_telegram_id: number }; Returns: Json }
      private_trade_lock: {
        Args: {
          p_locked?: boolean
          p_request_id?: string
          p_telegram_id: number
          p_trade: string
        }
        Returns: Json
      }
      private_trade_player_card: { Args: { p_user: string }; Returns: Json }
      private_trade_release_all: {
        Args: { p_trade: string }
        Returns: undefined
      }
      private_trade_remove_item: {
        Args: { p_item_id: string; p_telegram_id: number; p_trade: string }
        Returns: Json
      }
      private_trade_risk_assess: { Args: { p_trade: string }; Returns: Json }
      private_trade_search_player: {
        Args: { p_query: string; p_telegram_id: number }
        Returns: Json
      }
      private_trade_set_currency: {
        Args: {
          p_fc: number
          p_myth: number
          p_telegram_id: number
          p_ton: number
          p_trade: string
        }
        Returns: Json
      }
      private_trade_settings_json: { Args: never; Returns: Json }
      private_trade_settle: { Args: { p_trade: string }; Returns: Json }
      private_trade_state: {
        Args: { p_trade: string; p_user: string }
        Returns: Json
      }
      private_trade_touch: { Args: { p_trade: string }; Returns: undefined }
      private_trade_view: {
        Args: { p_telegram_id: number; p_trade: string }
        Returns: Json
      }
      process_boss_combat: {
        Args: { p_now?: string; p_telegram_id: number }
        Returns: Json
      }
      process_clan_boss_auto_attacks: {
        Args: { p_limit?: number }
        Returns: Json
      }
      process_global_boss_auto_attacks: {
        Args: { p_limit?: number }
        Returns: Json
      }
      prune_ton_payment_logs: { Args: never; Returns: number }
      pvp_ad_view_begin: { Args: { p_telegram_id: number }; Returns: Json }
      pvp_ad_view_reward: {
        Args: { p_source?: string; p_telegram_id: number; p_view_id?: string }
        Returns: Json
      }
      pvp_ads_state: { Args: { p_user_id: string }; Returns: Json }
      pvp_apply_daily_tickets: {
        Args: { p_telegram_id: number }
        Returns: Json
      }
      pvp_apply_pet_modifiers: {
        Args: { p_buffs: Json; p_team: Json }
        Returns: Json
      }
      pvp_audit_unpaid_rewards: { Args: { p_hours?: number }; Returns: Json }
      pvp_bot_band: {
        Args: { p_league: string; p_streak: number }
        Returns: Json
      }
      pvp_dedupe_team: { Args: { p_team: Json }; Returns: Json }
      pvp_generate_bot: { Args: { p_user: string }; Returns: Json }
      pvp_hero_block_reason: {
        Args: { h: Database["public"]["Tables"]["player_heroes"]["Row"] }
        Returns: string
      }
      pvp_hero_json: {
        Args: { h: Database["public"]["Tables"]["player_heroes"]["Row"] }
        Returns: Json
      }
      pvp_hero_template_key: {
        Args: { h: Database["public"]["Tables"]["player_heroes"]["Row"] }
        Returns: string
      }
      pvp_league: { Args: { t: number }; Returns: string }
      pvp_league_apply_delta: {
        Args: {
          p_delta: number
          p_event: string
          p_match: string
          p_role: string
          p_user: string
          p_win: boolean
        }
        Returns: undefined
      }
      pvp_league_build_rewards: {
        Args: { p_event_id: string }
        Returns: number
      }
      pvp_league_dashboard: { Args: { p_telegram_id: number }; Returns: Json }
      pvp_league_finalize: { Args: { p_event_id: string }; Returns: Json }
      pvp_league_maybe_finalize: { Args: never; Returns: undefined }
      pvp_repair_unpaid_rewards: { Args: { p_hours?: number }; Returns: Json }
      pvp_reset_daily_tickets_all: { Args: never; Returns: number }
      pvp_stat_unit: { Args: { v: string }; Returns: number }
      pvp_team_has_duplicates: {
        Args: { p_type: string; p_user: string }
        Returns: boolean
      }
      pvp_team_json: { Args: { p_type: string; p_user: string }; Returns: Json }
      pvp_team_power: {
        Args: { p_type: string; p_user: string }
        Returns: number
      }
      pvp_ticket_packs: { Args: never; Returns: Json }
      pvp_ticket_shop_state: { Args: { p_user_id: string }; Returns: Json }
      quest_timezone: { Args: never; Returns: string }
      quest_today: { Args: never; Returns: string }
      rare_myth_effective_units: { Args: { p_count: number }; Returns: number }
      rare_myth_mining_accrue: { Args: { p_user_id: string }; Returns: Json }
      rare_myth_mining_claim: { Args: { p_telegram_id: number }; Returns: Json }
      rare_myth_mining_state: { Args: { p_telegram_id: number }; Returns: Json }
      rare_myth_rare_count: { Args: { p_user_id: string }; Returns: number }
      rare_myth_reserved: { Args: never; Returns: number }
      rare_myth_snapshot_ensure: {
        Args: never
        Returns: {
          created_at: string
          daily_budget_myth: number
          day_key: string
          emitted_myth: number
          global_units: number
          players: number
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "rare_myth_mining_snapshots"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      rarity_base_atk: { Args: { r: string }; Returns: number }
      rarity_base_hp: { Args: { r: string }; Returns: number }
      rarity_resistance: { Args: { r: string }; Returns: number }
      rates_allowed_rarities: { Args: { p_rates: Json }; Returns: string[] }
      realm_access_allowed: {
        Args: { p_telegram_id: number }
        Returns: boolean
      }
      realm_bounties_ensure: { Args: { p_user: string }; Returns: Json }
      realm_bounty_claim: {
        Args: { p_id: string; p_user: string }
        Returns: Json
      }
      realm_building_claim: {
        Args: { p_type: string; p_user: string }
        Returns: Json
      }
      realm_building_level: {
        Args: { p_type: string; p_user: string }
        Returns: number
      }
      realm_building_upgrade: {
        Args: { p_type: string; p_user: string }
        Returns: Json
      }
      realm_craft_claim: {
        Args: { p_id: string; p_user: string }
        Returns: Json
      }
      realm_craft_start: {
        Args: {
          p_idem: string
          p_qty: number
          p_recipe: string
          p_user: string
        }
        Returns: Json
      }
      realm_depth_stats: {
        Args: { p_depth: number; p_region: string }
        Returns: Json
      }
      realm_depth_tier: { Args: { p_depth: number }; Returns: string }
      realm_ensure_profile: { Args: { p_user: string }; Returns: undefined }
      realm_entry_cost: {
        Args: { p_depth: number; p_region: string }
        Returns: number
      }
      realm_expedition_claim: {
        Args: { p_id: string; p_user: string }
        Returns: Json
      }
      realm_expedition_start: {
        Args: {
          p_idem: string
          p_region: string
          p_type: string
          p_user: string
        }
        Returns: Json
      }
      realm_explore_abandon: {
        Args: { p_run: string; p_user: string }
        Returns: Json
      }
      realm_explore_apply: {
        Args: {
          p_node: string
          p_option: string
          p_run: string
          p_user: string
        }
        Returns: Json
      }
      realm_explore_auto: {
        Args: { p_run: string; p_user: string }
        Returns: Json
      }
      realm_explore_build: {
        Args: { p_depth: number; p_run: string }
        Returns: undefined
      }
      realm_explore_choose: {
        Args: { p_option: string; p_run: string; p_user: string }
        Returns: Json
      }
      realm_explore_enter: {
        Args: { p_node: string; p_run: string; p_user: string }
        Returns: Json
      }
      realm_explore_extract: {
        Args: { p_run: string; p_user: string }
        Returns: Json
      }
      realm_explore_finish: {
        Args: { p_outcome: string; p_run: string; p_user: string }
        Returns: Json
      }
      realm_explore_start: {
        Args: { p_region: string; p_user: string }
        Returns: Json
      }
      realm_grant_item: {
        Args: { p_code: string; p_qty: number; p_user: string }
        Returns: undefined
      }
      realm_material_add: {
        Args: {
          p_amount: number
          p_material: string
          p_reason: string
          p_source?: string
          p_user: string
        }
        Returns: number
      }
      realm_progress_row: {
        Args: { p_region: string; p_user: string }
        Returns: {
          current_depth: number
          failed_runs: number
          highest_completed_depth: number
          id: string
          region_id: string
          successful_runs: number
          total_runs: number
          updated_at: string
          user_id: string
        }
        SetofOptions: {
          from: "*"
          to: "realm_region_progress"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      realm_region_meta: { Args: { p_user: string }; Returns: Json }
      realm_ruin_build_rooms: {
        Args: { p_room: number; p_run: string }
        Returns: undefined
      }
      realm_ruin_choose: {
        Args: { p_branch: number; p_run: string; p_user: string }
        Returns: Json
      }
      realm_ruin_extract: {
        Args: { p_run: string; p_user: string }
        Returns: Json
      }
      realm_ruin_finish: {
        Args: { p_cleared: boolean; p_run: string; p_user: string }
        Returns: Json
      }
      realm_ruin_start: {
        Args: { p_region: string; p_tier?: string; p_user: string }
        Returns: Json
      }
      realm_ruin_stats: { Args: { p_user: string }; Returns: Json }
      realm_shrine_xp_mult: { Args: { p_user: string }; Returns: number }
      realm_state: { Args: { p_user: string }; Returns: Json }
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
      record_game_activity: {
        Args: { p_activity: string; p_reference_id?: string; p_user_id: string }
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
      record_spending_points: {
        Args: {
          p_amount: number
          p_currency: string
          p_source_transaction_id: string
          p_source_type: string
          p_user_id: string
        }
        Returns: undefined
      }
      record_spending_reversal: {
        Args: { p_source_transaction_id: string }
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
      recruit_heroes:
        | { Args: { p_count: number; p_telegram_id: number }; Returns: Json }
        | {
            Args: {
              p_count: number
              p_pay_currency: string
              p_telegram_id: number
            }
            Returns: Json
          }
      referral_pay_ton_commission: {
        Args: {
          p_amount_ton: number
          p_buyer_id: string
          p_source_id: string
          p_source_type: string
        }
        Returns: Json
      }
      register_spending_event_purchase: {
        Args: {
          p_amount: number
          p_currency: string
          p_source_transaction_id: string
          p_source_type: string
          p_user_id: string
        }
        Returns: undefined
      }
      remove_pvp_team_slot: {
        Args: { p_slot: number; p_team_type: string; p_telegram_id: number }
        Returns: Json
      }
      remove_tower_team_slot: {
        Args: { p_slot: number; p_telegram_id: number }
        Returns: Json
      }
      request_ton_withdrawal: {
        Args: {
          p_amount_ton: number
          p_idempotency_key: string
          p_telegram_id: number
          p_wallet_address: string
        }
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
      roll_chest_rarity:
        | {
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
        | {
            Args: {
              p_ancestral?: number
              p_celestial?: number
              p_common?: number
              p_epic?: number
              p_legendary?: number
              p_mythic?: number
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
      roulette_grant_premium: {
        Args: { p_cycle: string; p_spin: string; p_user: string }
        Returns: Json
      }
      roulette_lock_open_cycle: {
        Args: never
        Returns: {
          completed_at: string | null
          config_snapshot: Json
          created_at: string
          cycle_number: number
          global_spend_nanoton: number
          id: string
          reward_attempts: number
          reward_delivered_at: string | null
          reward_delivery_key: string | null
          reward_last_error: string | null
          reward_status: string
          started_at: string
          status: string
          target_reference_cost_nanoton: number
          target_reward_id: string
          target_reward_type: string
          threshold_reached_at: string | null
          updated_at: string
          winner_user_id: string | null
          winning_spin_id: string | null
        }
        SetofOptions: {
          from: "*"
          to: "global_roulette_cycles"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      roulette_mark_paid: {
        Args: { p_amount_nano: string; p_spin_id: string; p_tx_hash: string }
        Returns: Json
      }
      roulette_mint_nft_unit: {
        Args: { p_reason: string; p_template: string }
        Returns: string
      }
      roulette_open_cycle: { Args: never; Returns: string }
      roulette_pay_myth: {
        Args: { p_amount: number; p_user: string }
        Returns: boolean
      }
      roulette_pending_payments: {
        Args: { p_telegram_id: number }
        Returns: Json
      }
      roulette_reconcile: {
        Args: { p_max_age_minutes?: number }
        Returns: Json
      }
      roulette_resolve: { Args: { p_spin_id: string }; Returns: Json }
      roulette_reward_recovery_audit: { Args: never; Returns: Json }
      roulette_roll_normal: {
        Args: { p_cycle: string; p_spin: string; p_user: string }
        Returns: Json
      }
      roulette_settle_cycle_reward: {
        Args: { p_cycle: string; p_spin?: string; p_user?: string }
        Returns: Json
      }
      roulette_spin: {
        Args: { p_idempotency_key?: string; p_telegram_id: number }
        Returns: Json
      }
      roulette_state: { Args: { p_telegram_id: number }; Returns: Json }
      roulette_user_has_celestial: {
        Args: { p_user: string }
        Returns: boolean
      }
      row_count_of_last: { Args: never; Returns: number }
      save_pvp_team_slot: {
        Args: {
          p_hero_id: string
          p_slot: number
          p_team_type: string
          p_telegram_id: number
        }
        Returns: Json
      }
      save_tower_team_slot: {
        Args: { p_hero_id: string; p_slot: number; p_telegram_id: number }
        Returns: Json
      }
      search_clans: {
        Args: { p_query?: string; p_telegram_id: number }
        Returns: Json
      }
      search_pvp_opponents: { Args: { p_telegram_id: number }; Returns: Json }
      season_pass_apply_entitlement: {
        Args: { p_season_id: string; p_tier: string; p_user_id: string }
        Returns: {
          adventurer_owned: boolean
          expires_at: string | null
          legendary_owned: boolean
          pass_version: number
          purchased_at: string | null
          season_id: string
          tier: string
          updated_at: string
          upgraded_at: string | null
          user_id: string
          xp: number
        }
        SetofOptions: {
          from: "*"
          to: "player_season_pass"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      season_pass_buy_with_internal_ton: {
        Args: {
          p_idempotency_key: string
          p_telegram_id: number
          p_tier: string
        }
        Returns: Json
      }
      season_pass_buy_with_myth: {
        Args: {
          p_idempotency_key: string
          p_telegram_id: number
          p_tier: string
        }
        Returns: Json
      }
      season_pass_level_purchase_config: { Args: never; Returns: Json }
      season_pass_levels_for: {
        Args: { p_pass_version: number; p_season_levels: number }
        Returns: number
      }
      season_pass_perk_percent: {
        Args: { p_perk: string; p_user_id: string }
        Returns: number
      }
      season_pass_tier_multiplier: { Args: { p_tier: string }; Returns: number }
      season_pass_xp_caps: { Args: never; Returns: Json }
      season_pass_xp_config: { Args: never; Returns: Json }
      season_pass_xp_multipliers: { Args: never; Returns: Json }
      set_boss_team: {
        Args: { p_hero_ids: string[]; p_telegram_id: number }
        Returns: Json
      }
      set_clan_boss_auto_attack: {
        Args: { p_enabled: boolean; p_telegram_id: number }
        Returns: Json
      }
      set_global_boss_auto_attack: {
        Args: { p_enabled: boolean; p_telegram_id: number }
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
      should_show_premium_offer_popup: {
        Args: { p_offer_id: string; p_user_id: string }
        Returns: string
      }
      simulate_pvp_battle: {
        Args: { a: Json; d: Json; seed: string }
        Returns: Json
      }
      simulate_tower_battle: {
        Args: { a: Json; b: Json; seed: string }
        Returns: Json
      }
      sovereign_pack_confirm_order: {
        Args: { p_amount_nano: string; p_order_id: string; p_tx_hash: string }
        Returns: Json
      }
      sovereign_pack_deliver: { Args: { p_purchase_id: string }; Returns: Json }
      sovereign_pack_offer_meta: { Args: { p_user_id: string }; Returns: Json }
      sovereign_pack_offer_state: {
        Args: { p_telegram_id: number }
        Returns: Json
      }
      sovereign_pack_settings: {
        Args: never
        Returns: {
          account_ton_bonus_percent: number
          celestial_armors: number
          enabled: boolean
          ends_at: string | null
          fc_reward: number
          id: boolean
          legendary_chests: number
          mythic_armors: number
          mythic_chests: number
          nft_weapons: number
          package_version: string
          popup_enabled: boolean
          popup_frequency: string
          popup_priority: number
          price_ton: number
          purchase_limit: number
          random_items: number
          random_items_pool: Json
          reward_configuration_version: number
          sales_paused: boolean
          sold_out_visible: boolean
          start_at: string | null
          stock_total: number | null
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "sovereign_pack_config"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      sovereign_pack_start_purchase: {
        Args: {
          p_idempotency_key: string
          p_telegram_id: number
          p_wallet_address: string
        }
        Returns: Json
      }
      sovereign_pack_state: { Args: { p_telegram_id: number }; Returns: Json }
      spending_currency_rate: { Args: { p_currency: string }; Returns: number }
      spending_event_backfill_nft_purchases: { Args: never; Returns: Json }
      spending_event_pay_rewards: {
        Args: { p_event_id: string }
        Returns: Json
      }
      spending_event_recount_user: {
        Args: { p_event_id: string; p_user_id: string }
        Returns: undefined
      }
      spending_event_refresh_ticker: {
        Args: { p_event_id: string }
        Returns: undefined
      }
      spending_event_reward_label: {
        Args: { p_event_id: string; p_position: number }
        Returns: string
      }
      spending_event_rules: { Args: never; Returns: Json }
      spending_source_enabled: {
        Args: { p_source_type: string }
        Returns: boolean
      }
      spending_source_group: {
        Args: { p_source_type: string }
        Returns: string
      }
      spending_ton_rate_fc: { Args: never; Returns: number }
      start_pvp_battle: {
        Args: { p_opponent_id: string; p_telegram_id: number }
        Returns: Json
      }
      starter_pack_cutoff: { Args: never; Returns: string }
      sub_nft_claim: { Args: { p_telegram_id: number }; Returns: Json }
      sub_nft_mint: {
        Args: {
          p_cost: number
          p_owner: string
          p_req: Database["public"]["Tables"]["nft_breeding_requests"]["Row"]
          p_side: string
        }
        Returns: string
      }
      sub_nft_passives: { Args: { p_sub_nft_id: string }; Returns: Json }
      sub_nft_sync: { Args: { p_user_id: string }; Returns: undefined }
      summon_hero_with_fragments: {
        Args: { p_idempotency_key?: string; p_telegram_id: number }
        Returns: Json
      }
      sync_boss_team_state: { Args: { p_user: string }; Returns: undefined }
      tactical_build_units: {
        Args: { p_side: string; p_user: string }
        Returns: Json
      }
      tactical_config: { Args: never; Returns: Json }
      tactical_dashboard: { Args: { p_telegram_id: number }; Returns: Json }
      tactical_deck_json: { Args: { p_user: string }; Returns: Json }
      tactical_eff_atk: { Args: { u: Json }; Returns: number }
      tactical_eff_def: { Args: { u: Json }; Returns: number }
      tactical_finish: {
        Args: { p_match: string; p_winner_side: string }
        Returns: undefined
      }
      tactical_has_status: {
        Args: { p_type: string; u: Json }
        Returns: boolean
      }
      tactical_history: {
        Args: { p_limit?: number; p_telegram_id: number }
        Returns: Json
      }
      tactical_hit: {
        Args: { p_dmg: number; p_uid: string; p_units: Json }
        Returns: Json
      }
      tactical_is_admin: { Args: { p_telegram_id: number }; Returns: boolean }
      tactical_league: { Args: { p_rating: number }; Returns: string }
      tactical_match_json: {
        Args: { p_match: string; p_user: string }
        Returns: Json
      }
      tactical_match_tick: {
        Args: { p_match_id: string; p_telegram_id: number }
        Returns: Json
      }
      tactical_queue_cancel: { Args: { p_telegram_id: number }; Returns: Json }
      tactical_queue_join: {
        Args: { p_practice?: boolean; p_telegram_id: number }
        Returns: Json
      }
      tactical_queue_status: { Args: { p_telegram_id: number }; Returns: Json }
      tactical_rand: { Args: { p_seed: string }; Returns: number }
      tactical_ranking: {
        Args: { p_limit?: number; p_telegram_id: number }
        Returns: Json
      }
      tactical_remove_team: {
        Args: { p_slot: number; p_telegram_id: number }
        Returns: Json
      }
      tactical_resolve_turn: { Args: { p_match: string }; Returns: boolean }
      tactical_save_deck: {
        Args: { p_skill_keys: string[]; p_telegram_id: number }
        Returns: Json
      }
      tactical_save_team: {
        Args: { p_hero_id: string; p_slot: number; p_telegram_id: number }
        Returns: Json
      }
      tactical_start_match: {
        Args: { p_a: string; p_b: string; p_practice?: boolean }
        Returns: string
      }
      tactical_status_sum: {
        Args: { p_types: string[]; u: Json }
        Returns: number
      }
      tactical_submit_action: {
        Args: {
          p_client_key?: string
          p_match_id: string
          p_skill_key: string
          p_target_uid: string
          p_telegram_id: number
        }
        Returns: Json
      }
      tactical_team_json: { Args: { p_user: string }; Returns: Json }
      tactical_user_id: { Args: { p_telegram_id: number }; Returns: string }
      tactical_validate_entry: {
        Args: { p_require_ticket: boolean; p_user: string }
        Returns: undefined
      }
      ton_absorb_duplicate_payment: {
        Args: { p_amount_nano: string; p_comment: string; p_tx_hash: string }
        Returns: Json
      }
      ton_mine_accrue: {
        Args: { p_holding_id: string }
        Returns: {
          active: boolean
          created_at: string
          id: string
          last_accrual_at: string
          paid_ton: number
          purchased_at: string
          stored_ton: number
          template_id: string
          total_claimed_ton: number
          updated_at: string
          user_id: string
        }
        SetofOptions: {
          from: "*"
          to: "ton_mine_holdings"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      ton_mine_assert_can_buy: {
        Args: {
          p_telegram_id: number
          p_template_id: string
          p_user_id: string
        }
        Returns: {
          created_at: string
          daily_ton: number
          description: string
          enabled: boolean
          id: string
          image_url: string | null
          max_per_player: number
          mine_key: string
          name: string
          paused: boolean
          price_ton: number
          sort_order: number
          storage_days: number
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "ton_mine_templates"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      ton_mine_buy_with_balance: {
        Args: {
          p_idempotency_key: string
          p_telegram_id: number
          p_template_id: string
        }
        Returns: Json
      }
      ton_mine_claim: {
        Args: { p_holding_id?: string; p_telegram_id: number }
        Returns: Json
      }
      ton_mine_confirm_purchase: {
        Args: { p_amount_nano: string; p_order_id: string; p_tx_hash: string }
        Returns: Json
      }
      ton_mine_create_order: {
        Args: {
          p_idempotency_key: string
          p_telegram_id: number
          p_template_id: string
        }
        Returns: Json
      }
      ton_mine_deliver_order: { Args: { p_order_id: string }; Returns: Json }
      ton_mine_multiplier: { Args: { p_purchased_at: string }; Returns: number }
      ton_mine_reconcile_orders: {
        Args: { p_telegram_id: number }
        Returns: Json
      }
      ton_mine_visible: { Args: { p_telegram_id: number }; Returns: boolean }
      ton_mines_state: { Args: { p_telegram_id: number }; Returns: Json }
      ton_mining_access_allowed: {
        Args: { p_user_id: string }
        Returns: boolean
      }
      ton_mining_access_sync: { Args: { p_user_id: string }; Returns: string }
      ton_mining_bonus_grant: {
        Args: {
          p_note?: string
          p_percent: number
          p_source: string
          p_user_id: string
        }
        Returns: number
      }
      ton_mining_bonus_policy: { Args: never; Returns: string }
      ton_mining_bonus_recalc: { Args: { p_user_id: string }; Returns: number }
      ton_mining_deposited_ton: { Args: { p_user_id: string }; Returns: number }
      ton_mining_gate_cutoff: { Args: never; Returns: string }
      ton_mining_gate_enabled: { Args: never; Returns: boolean }
      ton_mining_has_paid_v2_pass: {
        Args: { p_user_id: string }
        Returns: boolean
      }
      ton_mining_has_v2_pass: { Args: { p_user_id: string }; Returns: boolean }
      ton_mining_in_v2_cohort: { Args: { p_user_id: string }; Returns: boolean }
      ton_mining_owns_nft_hero: {
        Args: { p_user_id: string }
        Returns: boolean
      }
      ton_mining_owns_nft_pet: { Args: { p_user_id: string }; Returns: boolean }
      ton_mining_pass_confirmed_at: {
        Args: { p_user_id: string }
        Returns: string
      }
      ton_mining_pass_tier_at: {
        Args: { p_tier: string; p_user_id: string }
        Returns: string
      }
      ton_mining_qualified: { Args: { p_user_id: string }; Returns: boolean }
      ton_mining_suspension_price: {
        Args: { p_user_id: string }
        Returns: number
      }
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
      ton_staking_accrue: {
        Args: { p_position_id: string }
        Returns: undefined
      }
      ton_staking_accrue_user: {
        Args: { p_user_id: string }
        Returns: undefined
      }
      ton_staking_claim: {
        Args: {
          p_position_id?: string
          p_request_id?: string
          p_telegram_id: number
        }
        Returns: Json
      }
      ton_staking_flush_pending: {
        Args: { p_user_id: string }
        Returns: number
      }
      ton_staking_liability: { Args: never; Returns: number }
      ton_staking_outstanding: { Args: never; Returns: number }
      ton_staking_pool_available: { Args: never; Returns: number }
      ton_staking_route_mine: {
        Args: { p_amount: number; p_source_id: string; p_user_id: string }
        Returns: number
      }
      ton_staking_set_position_compound: {
        Args: {
          p_auto_compound: boolean
          p_position_id: string
          p_telegram_id: number
        }
        Returns: Json
      }
      ton_staking_set_preferences: {
        Args: {
          p_auto_compound: boolean
          p_enabled: boolean
          p_percent: number
          p_plan_id: string
          p_telegram_id: number
        }
        Returns: Json
      }
      ton_staking_stake: {
        Args: {
          p_amount: number
          p_auto_compound?: boolean
          p_plan_id: string
          p_request_id?: string
          p_telegram_id: number
        }
        Returns: Json
      }
      ton_staking_state: { Args: { p_telegram_id: number }; Returns: Json }
      ton_staking_unstake: {
        Args: {
          p_position_id: string
          p_request_id?: string
          p_telegram_id: number
        }
        Returns: Json
      }
      touch_player_activity: {
        Args: { p_telegram_id: number }
        Returns: undefined
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
      tower_boss_for_floor: { Args: { p_floor: number }; Returns: Json }
      tower_ensure_progress: {
        Args: { p_user: string }
        Returns: {
          attempts_date: string
          attempts_used: number
          created_at: string
          current_floor: number
          highest_floor: number
          updated_at: string
          user_id: string
        }
        SetofOptions: {
          from: "*"
          to: "tower_progress"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      tower_enter_floor: {
        Args: { p_pay_currency?: string; p_telegram_id: number }
        Returns: Json
      }
      tower_entry_cost: { Args: { p_floor: number }; Returns: number }
      tower_entry_cost_ton: { Args: never; Returns: number }
      tower_equipment_drop_audit: { Args: never; Returns: Json }
      tower_equipment_drop_rule: {
        Args: { p_first: boolean; p_floor: number }
        Returns: Json
      }
      tower_floor_rewards: {
        Args: { p_first: boolean; p_floor: number }
        Returns: Json
      }
      tower_grant_rewards: {
        Args: { p_first: boolean; p_floor: number; p_user: string }
        Returns: Json
      }
      tower_key_chances: {
        Args: { p_first: boolean; p_floor: number }
        Returns: Json
      }
      tower_key_confirm_order: {
        Args: { p_amount_nano: string; p_order_id: string; p_tx_hash: string }
        Returns: Json
      }
      tower_key_deliver: { Args: { p_order_id: string }; Returns: Json }
      tower_key_purchase_limit: { Args: { p_user_id: string }; Returns: number }
      tower_key_purchases_used: { Args: { p_user_id: string }; Returns: number }
      tower_key_shop_state: { Args: { p_telegram_id: number }; Returns: Json }
      tower_key_start_purchase: {
        Args: {
          p_idempotency_key: string
          p_key_code: string
          p_telegram_id: number
          p_wallet_address: string
        }
        Returns: Json
      }
      tower_milestone_rewards: { Args: { p_floor: number }; Returns: Json }
      tower_premium_chest_chances: { Args: { p_floor: number }; Returns: Json }
      tower_roll_equipment_drop: {
        Args: { p_first: boolean; p_floor: number; p_user: string }
        Returns: Json
      }
      tower_team_json: { Args: { p_user: string }; Returns: Json }
      unaccent_fallback: { Args: { v: string }; Returns: string }
      unequip_combat_hero: {
        Args: { p_slot: number; p_telegram_id: number }
        Returns: Json
      }
      unequip_hero_equipment: {
        Args: {
          p_hero_id: string
          p_instance_id?: string
          p_slot?: string
          p_telegram_id: number
        }
        Returns: Json
      }
      universal_fragment_balance: {
        Args: { p_user_id: string }
        Returns: number
      }
      universal_fusion_fragment_cost: { Args: never; Returns: number }
      upgrade_pet: {
        Args: { p_player_pet_id: string; p_telegram_id: number }
        Returns: Json
      }
      upgrade_pet_v2: {
        Args: {
          p_currency?: string
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
      vanguard_assert_non_celestial: {
        Args: { p_rarity: string; p_what: string }
        Returns: undefined
      }
      vanguard_hero_pool_size: { Args: never; Returns: number }
      vanguard_pack_confirm_order: {
        Args: { p_amount_nano: string; p_order_id: string; p_tx_hash: string }
        Returns: Json
      }
      vanguard_pack_deliver: { Args: { p_purchase_id: string }; Returns: Json }
      vanguard_pack_grant_pass: {
        Args: { p_purchase_id: string }
        Returns: Json
      }
      vanguard_pack_offer_meta: { Args: { p_user_id: string }; Returns: Json }
      vanguard_pack_offer_state: {
        Args: { p_telegram_id: number }
        Returns: Json
      }
      vanguard_pack_settings: {
        Args: never
        Returns: {
          account_ton_bonus_percent: number
          enabled: boolean
          ends_at: string | null
          fc_reward: number
          grant_pass_tier: string
          hero_rarity: string
          id: boolean
          legendary_armors: number
          legendary_chests: number
          lock_mining_after_reveal: boolean
          max_reward_rarity: string
          mythic_chests: number
          nft_weapons: number
          package_version: string
          popup_enabled: boolean
          popup_frequency: string
          popup_priority: number
          price_ton: number
          purchase_limit: number
          random_items: number
          random_items_pool: Json
          reward_configuration_version: number
          sales_paused: boolean
          sold_out_visible: boolean
          start_at: string | null
          stock_total: number | null
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "vanguard_pack_config"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      vanguard_pack_start_purchase: {
        Args: {
          p_idempotency_key: string
          p_telegram_id: number
          p_wallet_address: string
        }
        Returns: Json
      }
      vanguard_pack_state: { Args: { p_telegram_id: number }; Returns: Json }
      vanguard_pet_pool_size: { Args: never; Returns: number }
      veteran_v2_boost_percent: { Args: { p_user_id: string }; Returns: number }
      veteran_v2_confirm_order: {
        Args: { p_amount_nano: string; p_order_id: string; p_tx_hash: string }
        Returns: Json
      }
      veteran_v2_deliver: { Args: { p_purchase_id: string }; Returns: Json }
      veteran_v2_settings: {
        Args: never
        Returns: {
          boost_percent: number
          dragon_daily_myth: number
          enabled: boolean
          ends_at: string | null
          fragments: number
          hero_daily_myth: number
          id: boolean
          legendary_chests: number
          myth_reference_rate: number
          myth_reward: number
          package_version: string
          pet_daily_myth: number
          popup_enabled: boolean
          popup_frequency: string
          popup_priority: number
          price_ton: number
          reward_configuration_version: number
          sales_paused: boolean
          start_at: string
          updated_at: string
          weapons_per_purchase: number
        }
        SetofOptions: {
          from: "*"
          to: "veteran_vault_v2_config"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      veteran_v2_start_purchase: {
        Args: {
          p_idempotency_key: string
          p_telegram_id: number
          p_wallet_address: string
        }
        Returns: Json
      }
      veteran_v2_state: { Args: { p_telegram_id: number }; Returns: Json }
      veteran_vault_claim: {
        Args: { p_idempotency_key: string; p_telegram_id: number }
        Returns: Json
      }
      veteran_vault_confirm_order: {
        Args: { p_amount_nano: string; p_order_id: string; p_tx_hash: string }
        Returns: Json
      }
      veteran_vault_deliver: { Args: { p_purchase_id: string }; Returns: Json }
      veteran_vault_myth_budget: { Args: never; Returns: number }
      veteran_vault_pending_orders: {
        Args: { p_telegram_id: number }
        Returns: Json
      }
      veteran_vault_pending_rewards: {
        Args: { p_purchase_id: string }
        Returns: Json
      }
      veteran_vault_settings: {
        Args: never
        Returns: {
          badge_enabled: boolean
          cycle_days: number
          daily_myth: number
          enabled: boolean
          equipment_chest_code: string
          final_reward: Json
          fragments: number
          frame_enabled: boolean
          hero_key: string | null
          id: boolean
          initial_myth: number
          launch_at: string
          max_ton_reward: number
          min_account_age_days: number
          pass_tier: string
          pet_slug: string | null
          price_ton: number
          reference_values: Json
          resource_chest_code: string
          resource_chest_qty: number
          reward_schedule: Json
          sales_paused: boolean
          target_reference_ton: number
          updated_at: string
          vault_version: string
        }
        SetofOptions: {
          from: "*"
          to: "veteran_vault_config"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      veteran_vault_snapshot: { Args: never; Returns: Json }
      veteran_vault_start_purchase: {
        Args: {
          p_idempotency_key: string
          p_telegram_id: number
          p_wallet_address: string
        }
        Returns: Json
      }
      veteran_vault_state: { Args: { p_telegram_id: number }; Returns: Json }
      veteran_vault_ton_budget: { Args: never; Returns: number }
      wallet_deposit_config: { Args: never; Returns: Json }
      wallet_hot_address: { Args: never; Returns: string }
      weighted_pick: { Args: { p_weights: Json }; Returns: string }
      withdraw_fee_percent: { Args: never; Returns: number }
      withdraw_fee_percent_for_user: {
        Args: { p_user: string }
        Returns: number
      }
      withdraw_has_legendary_v2_pass: {
        Args: { p_user_id: string }
        Returns: boolean
      }
      withdraw_min_deposit_ton: { Args: never; Returns: number }
      withdraw_requires_v2_pass: {
        Args: { p_user_id: string }
        Returns: boolean
      }
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
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
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
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
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
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
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
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
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
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
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
