document.addEventListener("DOMContentLoaded", async () => {
    const form = document.getElementById("bookingForm");
    const packageSelect = document.getElementById("package_id");
    const message = document.getElementById("bookingMessage");

    if (!form) return;

    if (packageSelect && window.supabaseClient) {
        const { data, error } = await supabaseClient
            .from("packages")
            .select("id,name,price,duration_hours")
            .eq("active", true)
            .order("price", { ascending: true });

        if (!error) {
            packageSelect.innerHTML = '<option value="">Select a package</option>' +
                data.map(p => `<option value="${p.id}">${escapeHtml(p.name)}${Number(p.price || 0) ? " — E" + Number(p.price).toFixed(2) : ""}</option>`).join("");
        }
    }

    form.addEventListener("submit", async event => {
        event.preventDefault();
        message.textContent = "Checking availability...";

        const fd = new FormData(form);
        const payload = {
            client_name: fd.get("client_name").trim(),
            whatsapp: fd.get("whatsapp").trim(),
            email: fd.get("email").trim(),
            event_type: fd.get("event_type").trim(),
            event_date: fd.get("event_date"),
            start_time: fd.get("start_time"),
            end_time: fd.get("end_time"),
            venue: fd.get("venue").trim(),
            location: fd.get("location").trim(),
            guest_count: fd.get("guest_count") ? Number(fd.get("guest_count")) : null,
            package_id: fd.get("package_id") || null,
            notes: fd.get("notes").trim()
        };

        if (!payload.package_id) {
            message.textContent = "Please select a package.";
            return;
        }

        if (payload.end_time <= payload.start_time) {
            message.textContent = "End time must be later than start time.";
            return;
        }

        const { data: available, error: availabilityError } = await supabaseClient.rpc(
            "check_dj_availability",
            {
                p_event_date: payload.event_date,
                p_start_time: payload.start_time,
                p_end_time: payload.end_time
            }
        );

        if (availabilityError) {
            console.error(availabilityError);
            message.textContent = "We could not check availability. Please try again.";
            return;
        }

        if (!available) {
            message.textContent = "Sorry, that date/time is currently unavailable.";
            return;
        }

        const { error } = await supabaseClient
            .from("bookings")
            .insert([payload]);

        if (error) {
            console.error(error);
            message.textContent = error.message.includes("no_active_booking_overlap")
                ? "That time has just been booked. Please choose another time."
                : "Your booking request could not be submitted.";
            return;
        }

        form.reset();
        message.textContent = "Booking request submitted. Scorpion_Jr will review it and contact you.";
    });
});

function escapeHtml(value) {
    return String(value ?? "").replace(/[&<>"']/g, char => ({
        "&":"&amp;", "<":"&lt;", ">":"&gt;", '"':"&quot;", "'":"&#039;"
    }[char]));
}
