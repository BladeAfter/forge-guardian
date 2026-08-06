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
          forge_coins: number
          id: string
          last_seen_at: string
          telegram_id: number
          updated_at: string
          username: string | null
        }
        Insert: {
          avatar_url?: string | null
          boss_defeats?: number
          created_at?: string
          display_name?: string | null
          forge_coins?: number
          id?: string
          last_seen_at?: string
          telegram_id: number
          updated_at?: string
          username?: string | null
        }
        Update: {
          avatar_url?: string | null
          boss_defeats?: number
          created_at?: string
          display_name?: string | null
          forge_coins?: number
          id?: string
          last_seen_at?: string
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
      player_heroes: {
        Row: {
          created_at: string
          hero_key: string
          id: string
          image: string | null
          level: number
          name: string
          rarity: string
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          hero_key: string
          id?: string
          image?: string | null
          level?: number
          name: string
          rarity: string
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          hero_key?: string
          id?: string
          image?: string | null
          level?: number
          name?: string
          rarity?: string
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
      referral_commissions: {
        Row: {
          amount_fc: number
          created_at: string
          from_user: string
          id: string
          level: number
          purchase_id: string
          user_id: string
        }
        Insert: {
          amount_fc: number
          created_at?: string
          from_user: string
          id?: string
          level: number
          purchase_id: string
          user_id: string
        }
        Update: {
          amount_fc?: number
          created_at?: string
          from_user?: string
          id?: string
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
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      bind_referral: {
        Args: { p_inviter_telegram_id: number; p_telegram_id: number }
        Returns: Json
      }
      claim_boss_reward: { Args: { p_telegram_id: number }; Returns: Json }
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
      get_boss_combat: { Args: { p_telegram_id: number }; Returns: Json }
      get_referral_admin_stats: { Args: never; Returns: Json }
      get_referral_dashboard: { Args: { p_telegram_id: number }; Returns: Json }
      grant_referral_milestones: {
        Args: { p_user_id: string }
        Returns: undefined
      }
      normalize_hero_rarity: { Args: { value: string }; Returns: string }
      process_boss_combat: {
        Args: { p_now?: string; p_telegram_id: number }
        Returns: Json
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
      set_boss_team: {
        Args: { p_hero_ids: string[]; p_telegram_id: number }
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
