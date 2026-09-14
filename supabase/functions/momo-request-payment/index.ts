import { serve } from 'https://deno.land/std@0.224.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS'
}

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { ...cors, 'Content-Type': 'application/json' }
})

function normalizeMsisdn(value: string) {
  const digits = String(value || '').replace(/\D/g, '')
  if (digits.startsWith('268')) return digits
  if (digits.startsWith('0')) return '268' + digits.slice(1)
  return digits
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405)

  try {
    const body = await req.json()
    const token = body.token
    const paymentId = body.payment_id
    if (!token || !paymentId) return json({ error: 'token and payment_id are required' }, 400)

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const momoBase = Deno.env.get('MOMO_BASE_URL') || 'https://sandbox.momodeveloper.mtn.com'
    const subscriptionKey = Deno.env.get('MOMO_COLLECTION_SUBSCRIPTION_KEY')!
    const apiUser = Deno.env.get('MOMO_API_USER')!
    const apiKey = Deno.env.get('MOMO_API_KEY')!
    const targetEnvironment = Deno.env.get('MOMO_TARGET_ENVIRONMENT') || 'sandbox'
    const callbackUrl = Deno.env.get('MOMO_CALLBACK_URL') || `${supabaseUrl}/functions/v1/momo-callback`

    const admin = createClient(supabaseUrl, serviceKey)
    const { data: booking, error: bookingError } = await admin
      .from('bookings')
      .select('id, payment_token, client_name, whatsapp, deposit_amount, status')
      .eq('payment_token', token)
      .single()
    if (bookingError || !booking) return json({ error: 'Booking not found' }, 404)
    if (booking.status !== 'AWAITING_PAYMENT') return json({ error: 'Booking is not awaiting payment' }, 409)

    const { data: payment, error: paymentError } = await admin
      .from('payments')
      .select('id, booking_id, amount, payment_method, payment_status, provider_reference')
      .eq('id', paymentId)
      .eq('booking_id', booking.id)
      .single()
    if (paymentError || !payment) return json({ error: 'Payment record not found' }, 404)
    if (payment.payment_method !== 'MOMO') return json({ error: 'Payment method is not MoMo' }, 400)
    if (payment.payment_status === 'PAID') return json({ error: 'Payment is already paid' }, 409)

    const msisdn = normalizeMsisdn(booking.whatsapp)
    if (msisdn.length < 10) return json({ error: 'A valid Eswatini mobile number is required for MoMo payment.' }, 400)

    const tokenResponse = await fetch(`${momoBase}/collection/token/`, {
      method: 'POST',
      headers: {
        'Authorization': `Basic ${btoa(`${apiUser}:${apiKey}`)}`,
        'Ocp-Apim-Subscription-Key': subscriptionKey,
        'Content-Type': 'application/json'
      }
    })
    if (!tokenResponse.ok) return json({ error: 'Could not authenticate with MTN MoMo', detail: await tokenResponse.text() }, 502)
    const tokenData = await tokenResponse.json()

    const referenceId = payment.id
    const amount = Number(payment.amount).toFixed(2)
    const requestResponse = await fetch(`${momoBase}/collection/v1_0/requesttopay`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${tokenData.access_token}`,
        'X-Reference-Id': referenceId,
        'X-Target-Environment': targetEnvironment,
        'Ocp-Apim-Subscription-Key': subscriptionKey,
        'X-Callback-Url': callbackUrl,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        amount,
        currency: 'SZL',
        externalId: booking.id,
        payer: { partyIdType: 'MSISDN', partyId: msisdn },
        payerMessage: 'Scorpion_Jr DJ booking deposit',
        payeeNote: `Scorpion_Jr booking ${booking.id.slice(0, 8)}`
      })
    })

    if (requestResponse.status !== 202) {
      return json({ error: 'MTN MoMo rejected the payment request', detail: await requestResponse.text() }, 502)
    }

    await admin.from('payments').update({
      provider: 'MTN_MOMO',
      provider_reference: referenceId,
      payment_status: 'PENDING'
    }).eq('id', payment.id)

    return json({ ok: true, payment_id: payment.id, status: 'PENDING', message: 'A MoMo payment request was sent to the customer.' })
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : 'Unexpected error' }, 500)
  }
})
