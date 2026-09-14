# MTN MoMo setup for Scorpion_Jr

The V4 project keeps MTN credentials server-side in a Supabase Edge Function. Never place the API user, API key, subscription key, or service-role key in HTML/JavaScript.

## 1. MTN onboarding

For Eswatini, subscribe to the **Collections** product in the MTN MoMo developer/merchant portal and obtain the production credentials when you are approved. MTN's Eswatini Collections documentation says the product is for collecting customer payments and uses a collections account.

## 2. Supabase secrets

Set these Edge Function secrets:

- `MOMO_BASE_URL` — sandbox or production base URL supplied by MTN
- `MOMO_COLLECTION_SUBSCRIPTION_KEY`
- `MOMO_API_USER`
- `MOMO_API_KEY`
- `MOMO_TARGET_ENVIRONMENT` — `sandbox` for testing; `mtnswaziland` for the Swaziland production target
- `MOMO_CALLBACK_URL` — `https://YOUR_PROJECT_REF.supabase.co/functions/v1/momo-callback`

Supabase already provides `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` to Edge Functions when configured normally.

## 3. Deploy

From the project directory:

```bash
supabase functions deploy momo-request-payment
supabase functions deploy momo-callback
```

## 4. Callback

MTN RequestToPay is asynchronous. A successful request returns `202`, then MTN sends the final status to the callback. The callback function calls the database's atomic `confirm_booking_payment` RPC when the final status is `SUCCESSFUL`.

MTN documents that callbacks are sent once and recommends status polling as a fallback if a callback is missed. The next production hardening step should add a scheduled status-polling function.

## 5. Customer experience

The booking payment page creates a MoMo payment intent and then invokes the server-side function. The customer approves the debit on their phone. No PIN is ever entered into the Scorpion_Jr website.
