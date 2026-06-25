import Foundation

enum Config {
    static let supabaseURL = "https://mcknboqvblbonmaebmjg.supabase.co"

    // Supabase anon key — safe to embed in client apps.
    // Security is enforced by Row Level Security (RLS) policies in Supabase.
    // Get this from: Supabase dashboard → Project Settings → API → anon public
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1ja25ib3F2Ymxib25tYWVibWpnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzU0ODc5NjYsImV4cCI6MjA5MTA2Mzk2Nn0.3heE1l0e4ALo9lZCWbFeLktfVRoARQH1UO9Z4UExdKI"

    // RevenueCat iOS public SDK key — safe to embed.
    // Get this from: RevenueCat dashboard → Project → Apps → iOS → Public SDK key
    static let revenueCatAPIKey = "appl_tlykRhNVPkioVexPGIFSyJyzRMD"

    // Recipe extraction is proxied through a Supabase Edge Function so private AI
    // provider keys never ship in the iOS app binary.
    static let recipeExtractionEndpoint = "\(supabaseURL)/functions/v1/extract-recipe"

    // Account deletion (App Store 5.1.1(v)) is performed server-side with the
    // service-role key; the client only calls this endpoint with the user's JWT.
    static let deleteAccountEndpoint = "\(supabaseURL)/functions/v1/delete-account"

    // Legal / support URLs. REQUIRED for submission and shown in Settings (and on
    // the paywall). TODO(owner): replace the privacy and support URLs with live
    // pages before submitting. The Terms URL is Apple's standard EULA, valid as-is.
    static let privacyPolicyURL = "https://samanpantry.com/privacy"
    static let termsOfUseURL = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
    static let supportURL = "https://samanpantry.com/support"
}
