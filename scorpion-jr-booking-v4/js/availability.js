document.addEventListener("DOMContentLoaded", () => {
    const form = document.getElementById("availabilityForm");
    const result = document.getElementById("availabilityResult");
    if (!form) return;

    form.addEventListener("submit", async e => {
        e.preventDefault();
        const date = document.getElementById("availability_date").value;
        const start = document.getElementById("availability_start").value;
        const end = document.getElementById("availability_end").value;

        if (end <= start) {
            result.textContent = "End time must be later than start time.";
            return;
        }

        const { data, error } = await supabaseClient.rpc("check_dj_availability", {
            p_event_date: date,
            p_start_time: start,
            p_end_time: end
        });

        if (error) {
            console.error(error);
            result.textContent = "Unable to check availability.";
            return;
        }

        result.textContent = data
            ? "Available — you can submit a booking request."
            : "Unavailable — please choose another date or time.";
    });
});
