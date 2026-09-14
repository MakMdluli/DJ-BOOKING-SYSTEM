# Scorpion_Jr notifications setup

This version adds transactional email notifications while keeping the booking system account-free for customers.

## What is notified

- **New booking:** admin receives an email immediately after a customer submits a booking request.
- **New booking:** admin also gets an in-dashboard notification (database trigger), even if email delivery is unavailable.
- **Payment request:** customer receives an email when the admin accepts the request and it moves to `AWAITING_PAYMENT`. The email contains the payment-page link.
- **Declined/cancelled:** customer receives an email when the admin declines or cancels a booking.
- **Payment submitted:** admin receives an email when a customer submits a payment reference.
- **Payment verified:** customer receives an email when the admin verifies the payment and the booking becomes `CONFIRMED`.

## Email provider

The website uses Brevo Transactional Email through the Vercel serverless endpoint `/api/notify`. The Brevo API key is never placed in browser JavaScript. Brevo sends the messages through `POST https://api.brevo.com/v3/smtp/email`.

Set these Vercel environment variables:

- `BREVO_API_KEY` = your Brevo API key
- `NOTIFICATION_FROM_EMAIL` = the verified sender email in Brevo, e.g. `bookings@yourverifieddomain.com`
- `NOTIFICATION_FROM_NAME` = sender display name, e.g. `Scorpion_Jr`
- `ADMIN_NOTIFICATION_EMAIL` = the email address that should receive admin alerts
- `SUPABASE_URL` = your Supabase project URL
- `SUPABASE_SERVICE_ROLE_KEY` = your Supabase service-role key (Vercel server environment variable only; never put this in frontend files)
- `PUBLIC_SITE_URL` = `https://dj-booking-system-ivory.vercel.app`

## Supabase SQL

Run the updated `supabase-schema.sql` in the Supabase SQL Editor. It adds the `notification_deliveries` table and a trigger that creates a DJ notification for every new booking.

## Important

Do not put `SUPABASE_SERVICE_ROLE_KEY` or `BREVO_API_KEY` in `js/supabase.js`, HTML, or any public frontend file. They belong only in Vercel environment variables.

## Brevo setup

1. In Brevo, open **Settings → SMTP & API → API Keys** and generate a new API key.
2. Configure and verify the sender email/domain you want to use for transactional mail.
3. Add the variables above to the Vercel project under **Settings → Environment Variables**.
4. Redeploy the project after saving the variables.
5. Test a booking, an accepted booking/payment request, a payment submission, and a payment verification.

Brevo's API uses the `api-key` header and the `/v3/smtp/email` endpoint for transactional email. A verified sender is required for normal sending. You can use Brevo sandbox mode while validating the API request, but sandbox mode does not deliver actual emails.

Official Brevo documentation: https://developers.brevo.com/docs/send-a-transactional-email
