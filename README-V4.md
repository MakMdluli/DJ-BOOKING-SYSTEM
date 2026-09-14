# Scorpion_Jr Booking System V4

V4 adds the first real payment-provider integration layer for manual payments while keeping eMali, MTN MoMo, and Bank/EFT as manual verification methods.

## Payment flow

1. DJ accepts booking.
2. Booking moves to AWAITING_PAYMENT.
3. Customer opens payment link.
4. Customer chooses manual payment, eMali, or Bank.
5. manual payment can initiate a real RequestToPay through a Supabase Edge Function.
6. MTN callback reports SUCCESSFUL or FAILED.
7. SUCCESSFUL payment atomically marks the payment PAID and booking CONFIRMED.
8. A DJ notification is inserted.

## Important

The V4 source contains integration scaffolding, not your merchant credentials. You must complete MTN merchant onboarding and add the credentials as Supabase Edge Function secrets before live manual payment payments can run.
