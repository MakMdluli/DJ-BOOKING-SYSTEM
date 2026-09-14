const crypto = require('crypto');

function json(res, status, body) {
  res.status(status).json(body);
}

function esc(value) {
  return String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
}

function formatDate(value) {
  if (!value) return '—';
  return new Date(value + 'T00:00:00').toLocaleDateString('en-GB', {day:'2-digit', month:'long', year:'numeric'});
}

function formatTime(value) {
  return value ? String(value).slice(0,5) : '—';
}

function money(value) {
  return Number(value || 0).toLocaleString('en-SZ', {minimumFractionDigits:2, maximumFractionDigits:2});
}

async function supabase(path, options = {}) {
  const base = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!base || !key) throw new Error('Supabase server environment variables are not configured.');
  const response = await fetch(`${base}/rest/v1/${path}`, {
    ...options,
    headers: {
      apikey: key,
      Authorization: `Bearer ${key}`,
      'Content-Type': 'application/json',
      ...(options.headers || {})
    }
  });
  if (!response.ok) throw new Error(`Supabase request failed: ${response.status} ${await response.text()}`);
  return response.status === 204 ? null : response.json();
}

async function sendEmail({to, subject, html}) {
  const apiKey = process.env.BREVO_API_KEY;
  const fromEmail = process.env.NOTIFICATION_FROM_EMAIL;
  const fromName = process.env.NOTIFICATION_FROM_NAME || 'Scorpion_Jr';
  if (!apiKey) throw new Error('BREVO_API_KEY is not configured.');
  if (!fromEmail) throw new Error('NOTIFICATION_FROM_EMAIL is not configured.');

  const response = await fetch('https://api.brevo.com/v3/smtp/email', {
    method: 'POST',
    headers: {
      accept: 'application/json',
      'api-key': apiKey,
      'content-type': 'application/json'
    },
    body: JSON.stringify({
      sender: {email: fromEmail, name: fromName},
      to: [{email: to}],
      subject,
      htmlContent: html
    })
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) {
    const message = body.message || body.code || `HTTP ${response.status}`;
    throw new Error(`Brevo rejected the message: ${message}`);
  }
  return body;
}

async function claimDelivery(bookingId, eventType, recipient) {
  const key = crypto.createHash('sha256').update(`${bookingId}:${eventType}:${recipient.toLowerCase()}`).digest('hex');
  try {
    await supabase('notification_deliveries', {
      method:'POST',
      headers:{Prefer:'return=minimal'},
      body:JSON.stringify({delivery_key:key,booking_id:bookingId,event_type:eventType,recipient})
    });
    return true;
  } catch (error) {
    // A duplicate delivery key means this event has already been sent.
    if (String(error.message).includes('duplicate') || String(error.message).includes('23505')) return false;
    throw error;
  }
}

async function getBooking(id) {
  const rows = await supabase(`bookings?id=eq.${encodeURIComponent(id)}&select=*`);
  if (!rows?.length) throw new Error('Booking not found.');
  return rows[0];
}

function bookingSummary(b) {
  return `${esc(b.event_type)} · ${formatDate(b.event_date)} · ${formatTime(b.start_time)}–${formatTime(b.end_time)} · ${esc(b.venue)}, ${esc(b.location)}`;
}

module.exports = async (req, res) => {
  if (req.method !== 'POST') return json(res, 405, {error:'POST only'});
  try {
    const {event, booking_id, payment_id} = req.body || {};
    const adminEmail = process.env.ADMIN_NOTIFICATION_EMAIL;
    if (!event) return json(res, 400, {error:'Missing notification event.'});

    if (event === 'booking_created') {
      if (!adminEmail) throw new Error('ADMIN_NOTIFICATION_EMAIL is not configured.');
      const b = await getBooking(booking_id);
      const recipient = adminEmail;
      if (!(await claimDelivery(b.id, event, recipient))) return json(res, 200, {sent:false, duplicate:true});
      await sendEmail({
        to: recipient,
        subject: `New booking request — ${b.client_name}`,
        html:`<h2>New Scorpion_Jr booking request</h2><p><strong>${esc(b.client_name)}</strong> has submitted a new booking request.</p><p>${bookingSummary(b)}</p><p>WhatsApp: ${esc(b.whatsapp)}<br>Email: ${esc(b.email)}</p><p>Log in to the admin dashboard to review the request.</p>`
      });
      return json(res, 200, {sent:true});
    }

    if (event === 'payment_requested' || event === 'booking_declined' || event === 'booking_cancelled') {
      const b = await getBooking(booking_id);
      if (!b.email) return json(res, 200, {sent:false, reason:'No customer email'});
      const recipient = b.email;
      if (!(await claimDelivery(b.id, event, recipient))) return json(res, 200, {sent:false, duplicate:true});
      let subject, title, body;
      if (event === 'payment_requested') {
        const baseUrl = process.env.SITE_URLS || 'https://dj-booking-system-ivory.vercel.app';
        const link = `${baseUrl.replace(/\/$/,'')}/pay.html?token=${encodeURIComponent(b.payment_token)}`;
        subject = 'Your Scorpion_Jr booking has been accepted — payment required';
        title = 'Booking accepted — deposit required';
        body = `<p>Your booking request has been accepted.</p><p>${bookingSummary(b)}</p><p><strong>Deposit required: E ${money(b.deposit_amount)}</strong></p><p>Your booking is only confirmed after the deposit has been verified.</p><p><a href="${esc(link)}">Open your payment page</a></p>`;
      } else if (event === 'booking_declined') {
        subject = 'Scorpion_Jr booking request update';
        title = 'Booking request declined';
        body = `<p>Unfortunately, your booking request could not be accepted at this time.</p><p>${bookingSummary(b)}</p>`;
      } else {
        subject = 'Scorpion_Jr booking cancelled';
        title = 'Booking cancelled';
        body = `<p>Your booking has been cancelled.</p><p>${bookingSummary(b)}</p>`;
      }
      await sendEmail({to:recipient,subject,html:`<h2>${title}</h2><p>Hello ${esc(b.client_name)},</p>${body}<p>— Scorpion_Jr</p>`});
      return json(res, 200, {sent:true});
    }

    if (event === 'payment_submitted') {
      if (!adminEmail) throw new Error('ADMIN_NOTIFICATION_EMAIL is not configured.');
      const rows = await supabase(`payments?id=eq.${encodeURIComponent(payment_id)}&select=*,bookings(*)`);
      const p = rows?.[0];
      if (!p?.bookings) throw new Error('Payment/booking not found.');
      const b = p.bookings;
      const recipient = adminEmail;
      if (!(await claimDelivery(b.id, `${event}:${p.id}`, recipient))) return json(res, 200, {sent:false, duplicate:true});
      await sendEmail({to:recipient,subject:`Payment submitted — ${b.client_name}`,html:`<h2>Payment submitted for verification</h2><p><strong>${esc(b.client_name)}</strong> submitted a payment.</p><p>${bookingSummary(b)}</p><p>Method: ${esc(p.payment_method)}<br>Amount: E ${money(p.amount)}<br>Reference: ${esc(p.reference || 'Not supplied')}</p><p>Please verify the transaction in the admin dashboard.</p>`});
      return json(res, 200, {sent:true});
    }

    if (event === 'payment_confirmed') {
      const b = await getBooking(booking_id);
      if (!b.email) return json(res, 200, {sent:false, reason:'No customer email'});
      const recipient = b.email;
      if (!(await claimDelivery(b.id, event, recipient))) return json(res, 200, {sent:false, duplicate:true});
      await sendEmail({to:recipient,subject:'Your Scorpion_Jr booking is confirmed',html:`<h2>Booking confirmed</h2><p>Hello ${esc(b.client_name)},</p><p>Your payment has been verified and your booking is now <strong>CONFIRMED</strong>.</p><p>${bookingSummary(b)}</p><p>Thank you for booking Scorpion_Jr.</p>`});
      return json(res, 200, {sent:true});
    }

    return json(res, 400, {error:`Unknown event: ${event}`});
  } catch (error) {
    console.error(error);
    return json(res, 500, {error:error.message || 'Notification failed'});
  }
};
