# Scorpion_Jr DJ Booking System – V3

Plain HTML/CSS/JavaScript DJ booking system backed by Supabase.

## V3 payment workflow
- Customer submits booking request.
- DJ accepts and sets total/deposit.
- Booking moves to AWAITING_PAYMENT.
- Customer receives a payment link.
- Payment methods: eMali, MTN MoMo/MoMoPay, Bank/EFT.
- Customer submits transaction/reference details.
- Admin verifies the payment.
- Supabase atomically marks the payment PAID and booking CONFIRMED.
- A DJ notification is created for the payment event.

### Important
The V3 site does not pretend that a customer-submitted reference is proof of payment. Until live merchant APIs are connected, MoMo/eMali payments are submitted for verification and the admin must verify them. Bank/EFT payments are also manually verified. This prevents false booking confirmations.

MTN provides MoMo APIs for payment collection and payment status/callback workflows, and MTN lists eSwatini among supported MoMo markets.

## Supabase
Run the updated `supabase-schema.sql` in the Supabase SQL Editor. If you already have V2 data, the script is designed as a migration in most places, but review any existing status constraints before running it.

## Setup
1. Keep your existing `js/supabase.js` Project URL and Publishable key.
2. Run `supabase-schema.sql`.
3. Keep the existing admin Auth user/profile.
4. Open `admin/login.html`.
5. Accept a booking, set a deposit, and the booking becomes `AWAITING_PAYMENT`.
6. Open the payment link and submit a test payment intent.
7. Go to Admin → Payments and verify it.

## Going live with automatic MoMo/eMali confirmation
The database/payment architecture is ready for provider webhooks. Live API credentials must be stored server-side (Supabase Edge Function or another backend), never in browser JavaScript.

## Equipment policy
DJ service only. Sound, lighting and other equipment are not included unless separately agreed.
