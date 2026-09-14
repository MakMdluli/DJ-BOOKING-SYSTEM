// Supabase browser client configuration.
// Use the Project URL and Publishable key (or legacy anon key).
// NEVER put a Supabase secret/service-role key in browser code.

const SUPABASE_URL = "YOUR_SUPABASE_PROJECT_URL";
const SUPABASE_ANON_KEY = "YOUR_SUPABASE_PUBLISHABLE_KEY";

if (!window.supabase) {
    console.error("Supabase JavaScript library was not loaded.");
} else {
    const supabaseClient = window.supabase.createClient(
        SUPABASE_URL,
        SUPABASE_ANON_KEY
    );

    window.supabaseClient = supabaseClient;
    console.log("Scorpion_Jr Supabase client loaded.");
}
