// Supabase browser client configuration.
// Use the Project URL and Publishable key (or legacy anon key).
// NEVER put a Supabase secret/service-role key in browser code.

const SUPABASE_URL="https://kksugasattnkxfeqmggd.supabase.co";
const SUPABASE_ANON_KEY="sb_publishable_pDWeVYCDFRdvXDRp3g5SRQ_YiXLpzCJ";

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
