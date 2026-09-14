import { serve } from 'https://deno.land/std@0.224.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { 'Content-Type': 'application/json' }
})

serve(async (req) => {
  if (!['POST','PUT'].includes(req.method)) return json({ error: 'Method not allowed' }, 405)
  try {
    const payload = await req.json()
    const referenceId = req.headers.get('x-reference-id') || payload.referenceId || payload.reference_id
    const status = String(payload.status || '').toUpperCase()
    if (!referenceId) return json({ error: 'Missing reference id' }, 400)

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    const { data: payment, error } = await supabase
      .from('payments')
      .select('id, booking_id, amount, payment_status')
      .eq('id', referenceId)
      .single()
    if (error || !payment) return json({ error: 'Payment not found' }, 404)

    if (status === 'SUCCESSFUL') {
      const { error: confirmError } = await supabase.rpc('confirm_booking_payment', {
        p_payment_id: payment.id,
        p_reference: payload.financialTransactionId || payload.financial_transaction_id || referenceId
      })
      if (confirmError) return json({ error: confirmError.message }, 409)
    } else if (status === 'FAILED') {
      await supabase.from('payments').update({ payment_status: 'FAILED' }).eq('id', payment.id)
      await supabase.from('notifications').insert({
        booking_id: payment.booking_id,
        notification_type: 'PAYMENT_FAILED',
        title: 'MoMo payment failed',
        message: 'The MTN MoMo payment attempt failed. The customer can try again.'
      })
    }

    return json({ ok: true })
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : 'Unexpected error' }, 500)
  }
})
