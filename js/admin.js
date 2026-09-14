function esc(v){return String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));}
function money(v){const n=Number(v||0);return n.toLocaleString(undefined,{minimumFractionDigits:2,maximumFractionDigits:2});}
function fmtDate(v){if(!v)return '—';return new Date(v+'T00:00:00').toLocaleDateString(undefined,{day:'2-digit',month:'short',year:'numeric'});}
function fmtTime(v){return v?String(v).slice(0,5):'—';}
function statusClass(s){return 'status status-'+String(s||'').toLowerCase().replace(/_/g,'-');}
function nav(){return `<div class="admin-head"><a href="../index.html"><img class="logo" src="../assets/logo.png" alt="Scorpion_Jr"></a><div><span class="eyebrow">ADMIN PANEL</span><div class="admin-title">Scorpion_Jr Booking System</div></div></div><nav class="admin-nav"><a href="dashboard.html">Dashboard</a><a href="bookings.html">Bookings</a><a href="calendar.html">Calendar</a><a href="clients.html">Clients</a><a href="packages.html">Packages</a><a href="payments.html">Payments</a><a href="reviews.html">Reviews</a><a href="settings.html">Settings</a><a href="#" onclick="adminSignOut();return false;">Sign out</a></nav>`;}
async function loadAdminShell(){document.querySelector('.admin-main')?.insertAdjacentHTML('afterbegin',nav());return await requireAdmin();}
async function updateBookingStatus(id,status,extra={}){
    if(status==='CONFIRMED') throw new Error('Bookings are confirmed only after a verified payment.');
    const {data:before}=await supabaseClient.from('bookings').select('status').eq('id',id).maybeSingle();
    const {error}=await supabaseClient.from('bookings').update({status,...extra}).eq('id',id);
    if(error)throw error;
    if(before?.status!=='ACCEPTED' && status==='ACCEPTED'){
        await supabaseClient.from('notifications').insert({booking_id:id,notification_type:'BOOKING_ACCEPTED',title:'Booking accepted',message:'A booking request has been accepted. The customer will be notified.'});
    }
    if(before?.status!=='AWAITING_PAYMENT' && status==='AWAITING_PAYMENT'){
        await supabaseClient.from('notifications').insert({booking_id:id,notification_type:'PAYMENT_REQUEST',title:'Payment requested',message:'The booking is awaiting the required deposit. The customer has been emailed a payment request.'});
        if(location.protocol!=='file:') fetch('../api/notify',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({event:'payment_requested',booking_id:id})}).catch(err=>console.warn('Customer payment email failed:',err));
    }
    if(status==='DECLINED' && before?.status!=='DECLINED'){
        if(location.protocol!=='file:') fetch('../api/notify',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({event:'booking_declined',booking_id:id})}).catch(err=>console.warn('Customer decline email failed:',err));
    }
    if(status==='CANCELLED' && before?.status!=='CANCELLED'){
        if(location.protocol!=='file:') fetch('../api/notify',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({event:'booking_cancelled',booking_id:id})}).catch(err=>console.warn('Customer cancellation email failed:',err));
    }
}
async function unreadNotificationCount(){const {count}=await supabaseClient.from('notifications').select('*',{count:'exact',head:true}).is('read_at',null);return count||0;}
async function loadNotifications(){const {data}=await supabaseClient.from('notifications').select('*').order('created_at',{ascending:false}).limit(20);return data||[];}
async function markNotificationRead(id){await supabaseClient.from('notifications').update({read_at:new Date().toISOString()}).eq('id',id);}
