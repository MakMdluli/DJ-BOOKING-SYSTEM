document.addEventListener("DOMContentLoaded", () => {
    const year = document.querySelectorAll("[data-year]");
    year.forEach(el => el.textContent = new Date().getFullYear());

    const menuButton = document.querySelector("[data-menu]");
    const nav = document.querySelector("[data-nav]");
    if (menuButton && nav) {
        menuButton.addEventListener("click", () => nav.classList.toggle("open"));
    }

    loadPublicPackages();
    loadPublicReviews();
});

async function loadPublicPackages() {
    if (!window.supabaseClient) return;
    const container = document.querySelector("[data-packages]");
    if (!container) return;

    const { data, error } = await supabaseClient
        .from("packages")
        .select("id,name,description,price,duration_hours")
        .eq("active", true)
        .order("price", { ascending: true });

    if (error) {
        console.error(error);
        return;
    }

    container.innerHTML = data.map(pkg => `
        <article class="card">
            <span class="eyebrow">${escapeHtml(pkg.duration_hours ?? "")} HRS</span>
            <h3>${escapeHtml(pkg.name)}</h3>
            <p>${escapeHtml(pkg.description ?? "")}</p>
            <strong>${Number(pkg.price || 0) > 0 ? "E" + Number(pkg.price).toFixed(2) : "Quote on request"}</strong>
        </article>
    `).join("");
}

async function loadPublicReviews() {
    if (!window.supabaseClient) return;
    const container = document.querySelector("[data-reviews]");
    if (!container) return;

    const { data, error } = await supabaseClient
        .from("reviews")
        .select("client_name,rating,review_text")
        .eq("published", true)
        .order("created_at", { ascending: false })
        .limit(6);

    if (error) return;

    container.innerHTML = data.map(r => `
        <article class="card">
            <div class="stars">${"★".repeat(r.rating)}${"☆".repeat(5-r.rating)}</div>
            <p>“${escapeHtml(r.review_text)}”</p>
            <small>${escapeHtml(r.client_name)}</small>
        </article>
    `).join("");
}

function escapeHtml(value) {
    return String(value ?? "").replace(/[&<>"']/g, char => ({
        "&":"&amp;", "<":"&lt;", ">":"&gt;", '"':"&quot;", "'":"&#039;"
    }[char]));
}
