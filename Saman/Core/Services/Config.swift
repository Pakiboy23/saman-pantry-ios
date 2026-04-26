import Foundation

enum Config {
    static let supabaseURL = "https://mcknboqvblbonmaebmjg.supabase.co"

    // Supabase anon key — safe to embed in client apps.
    // Security is enforced by Row Level Security (RLS) policies in Supabase.
    // Get this from: Supabase dashboard → Project Settings → API → anon public
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1ja25ib3F2Ymxib25tYWVibWpnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzU0ODc5NjYsImV4cCI6MjA5MTA2Mzk2Nn0.3heE1l0e4ALo9lZCWbFeLktfVRoARQH1UO9Z4UExdKI"

    // RevenueCat iOS public SDK key — safe to embed.
    // Get this from: RevenueCat dashboard → Project → Apps → iOS → Public SDK key
    static let revenueCatAPIKey = "REVENUECAT_IOS_API_KEY"
}
