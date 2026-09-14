document.addEventListener("DOMContentLoaded", () => {
    const loginForm = document.getElementById("loginForm");
    if (loginForm) {
        loginForm.addEventListener("submit", async e => {
            e.preventDefault();
            const email = document.getElementById("email").value;
            const password = document.getElementById("password").value;
            const message = document.getElementById("loginMessage");

            const { error } = await supabaseClient.auth.signInWithPassword({
                email, password
            });

            if (error) {
                message.textContent = error.message;
                return;
            }

            window.location.href = "dashboard.html";
        });
    }
});

async function requireAdmin() {
    const { data: { user } } = await supabaseClient.auth.getUser();
    if (!user) {
        window.location.href = "login.html";
        return null;
    }

    const { data: profile, error } = await supabaseClient
        .from("profiles")
        .select("role,full_name")
        .eq("id", user.id)
        .single();

    if (error || profile?.role !== "admin") {
        await supabaseClient.auth.signOut();
        window.location.href = "login.html";
        return null;
    }

    return { user, profile };
}

async function adminSignOut() {
    await supabaseClient.auth.signOut();
    window.location.href = "login.html";
}
