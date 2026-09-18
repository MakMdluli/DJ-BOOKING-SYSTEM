# Scorpion_Jr Booking System — V6

V6 keeps the working V4 booking/notification foundation and adds a more polished public website, customer document downloads, EPK/media downloads, invoice tracking, and a first setlist-builder foundation.

## New in V6
- Bold & energetic visual direction based on the selected Template 3 concept.
- Public Media page with the supplied Scorpion_Jr EPK download.
- Customer-facing quotation/invoice document page using a secure booking token.
- Downloadable quotation and invoice PDFs from the customer document page.
- Automatic quotation creation when a booking is accepted/awaiting payment.
- Automatic invoice creation when a booking becomes confirmed.
- Invoice totals, amount paid and balance tracking from verified payments.
- Admin Invoice Tracker.
- Admin Setlist Builder with music library + reusable setlists.
- Existing manual payment channels retained: eMali, MTN MoMo and Bank/EFT.
- Payment architecture remains ready for a compatible online Eswatini gateway later; no gateway is falsely presented as active in this version.
- Brevo notification endpoint uses `SITE_URLS`.

## Upgrade steps
1. Keep your current V4 Supabase data.
2. Run `supabase-v6-upgrade.sql` in the Supabase SQL Editor.
3. Keep your existing V4/V4-Brevo environment variables, including:
   - `SUPABASE_URL`
   - `SUPABASE_SERVICE_ROLE_KEY`
   - `BREVO_API_KEY`
   - `NOTIFICATION_FROM_EMAIL`
   - `NOTIFICATION_FROM_NAME`
   - `ADMIN_NOTIFICATION_EMAIL`
   - `SITE_URLS`
4. Deploy this project to the existing Vercel project.
5. Upload additional promo photos later under the Media section as the library grows.

## Customer document links
Customer documents are accessed through:
`documents.html?token=<booking-payment-token>`

The token is not displayed publicly in the normal site navigation. It is delivered through the customer's booking/payment link.

## Payment channels
Current V6 customer payment page supports the same manual channels already configured in Settings:
- eMali
- MTN MoMo
- Bank / EFT

An online gateway should be added only after its Eswatini API/webhook requirements have been verified.
