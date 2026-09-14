-- SCORPION_JR BOOKING SYSTEM
-- Run this in Supabase SQL Editor.
-- This version includes RLS, admin profiles, availability RPC, and overlap protection.

create extension if not exists pgcrypto;
create extension if not exists btree_gist;

create table if not exists public.profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    full_name text,
    role text not null default 'admin' check (role in ('admin')),
    created_at timestamptz not null default now()
);

create table if not exists public.packages (
    id uuid primary key default gen_random_uuid(),
    name text not null unique,
    description text,
    price numeric(12,2),
    duration_hours numeric(5,2),
    active boolean not null default true,
    created_at timestamptz not null default now()
);

create table if not exists public.bookings (
    id uuid primary key default gen_random_uuid(),
    client_name text not null,
    whatsapp text not null,
    email text not null,
    event_type text not null,
    event_date date not null,
    start_time time not null,
    end_time time not null,
    venue text not null,
    location text not null,
    guest_count integer,
    package_id uuid references public.packages(id),
    notes text,
    status text not null default 'PENDING'
        check (status in (
            'PENDING','ACCEPTED','AWAITING_PAYMENT','CONFIRMED',
            'COMPLETED','DECLINED','CANCELLED'
        )),
    deposit_amount numeric(12,2) default 0,
    total_amount numeric(12,2),
    created_at timestamptz not null default now(),
    payment_token uuid not null default gen_random_uuid() unique,
    check (end_time > start_time),
    check (guest_count is null or guest_count > 0),
    check (deposit_amount >= 0)
);

-- Migration helpers for existing V2 installations.
alter table public.bookings add column if not exists payment_token uuid default gen_random_uuid();
update public.bookings set payment_token=gen_random_uuid() where payment_token is null;
alter table public.bookings alter column payment_token set not null;
create unique index if not exists bookings_payment_token_unique_idx on public.bookings(payment_token);

alter table public.bookings drop constraint if exists bookings_status_check;
alter table public.bookings add constraint bookings_status_check check (status in ('PENDING','ACCEPTED','AWAITING_PAYMENT','CONFIRMED','COMPLETED','DECLINED','CANCELLED'));
-- Generated range used to prevent overlapping accepted/deposit/confirmed bookings.
alter table public.bookings
    add column if not exists event_window tsrange
    generated always as (
        tsrange(
            (event_date + start_time)::timestamp,
            (event_date + end_time)::timestamp,
            '[)'
        )
    ) stored;

alter table public.bookings drop constraint if exists no_active_booking_overlap;
alter table public.bookings
    add constraint no_active_booking_overlap
    exclude using gist (
        event_window with &&
    )
    where (status in ('ACCEPTED','AWAITING_PAYMENT','CONFIRMED'));

create table if not exists public.blocked_dates (
    id uuid primary key default gen_random_uuid(),
    blocked_date date not null unique,
    reason text,
    created_at timestamptz not null default now()
);

create table if not exists public.payments (
    id uuid primary key default gen_random_uuid(),
    booking_id uuid not null references public.bookings(id) on delete cascade,
    amount numeric(12,2) not null check (amount > 0),
    payment_type text not null default 'DEPOSIT',
    payment_method text not null default 'BANK' check (payment_method in ('EMALI','MOMO','BANK')),
    payment_status text not null default 'PENDING' check (payment_status in ('PENDING','PAID','FAILED','CANCELLED')),
    paid_at timestamptz,
    reference text,
    created_at timestamptz not null default now()
);

create table if not exists public.payment_settings (
    id integer primary key default 1 check (id = 1),
    emali_number text,
    emali_name text,
    momo_number text,
    momo_name text,
    bank_name text,
    bank_account_name text,
    bank_account_number text,
    bank_branch text,
    payment_instructions text,
    updated_at timestamptz not null default now()
);

insert into public.payment_settings (id)
values (1)
on conflict (id) do nothing;

-- Payment migration helpers for existing installations.
alter table public.payment_settings add column if not exists momo_number text;
alter table public.payment_settings add column if not exists momo_name text;
alter table public.payments add column if not exists payment_method text default 'BANK';
alter table public.payments add column if not exists payment_status text default 'PENDING';
update public.payments set payment_method='BANK' where payment_method is null;
update public.payments set payment_status='PENDING' where payment_status is null;
alter table public.payments drop constraint if exists payments_payment_method_check;
alter table public.payments add constraint payments_payment_method_check check (payment_method in ('EMALI','MOMO','BANK'));
alter table public.payments drop constraint if exists payments_payment_status_check;
alter table public.payments add constraint payments_payment_status_check check (payment_status in ('PENDING','PAID','FAILED','CANCELLED'));

create table if not exists public.reviews (
    id uuid primary key default gen_random_uuid(),
    booking_id uuid references public.bookings(id) on delete set null,
    client_name text not null,
    rating integer not null check (rating between 1 and 5),
    review_text text not null,
    published boolean not null default false,
    created_at timestamptz not null default now()
);

insert into public.packages (name, description, price, duration_hours)
values
('Essential','DJ service for smaller events and straightforward bookings.',0,4),
('Premium','Extended DJ performance for parties and celebrations.',0,6),
('Signature','Extended premium DJ experience for major events.',0,8)
on conflict (name) do nothing;

create index if not exists bookings_event_date_idx on public.bookings(event_date);
create index if not exists bookings_status_idx on public.bookings(status);
create index if not exists payments_booking_id_idx on public.payments(booking_id);
create index if not exists bookings_payment_token_idx on public.bookings(payment_token);

create table if not exists public.notifications (
    id uuid primary key default gen_random_uuid(),
    booking_id uuid references public.bookings(id) on delete cascade,
    notification_type text not null,
    title text not null,
    message text not null,
    read_at timestamptz,
    created_at timestamptz not null default now()
);
create index if not exists notifications_created_at_idx on public.notifications(created_at desc);


-- Email notification delivery ledger. Service-side Vercel notifications use this to prevent duplicates.
create table if not exists public.notification_deliveries (
    id uuid primary key default gen_random_uuid(),
    delivery_key text not null unique,
    booking_id uuid not null references public.bookings(id) on delete cascade,
    event_type text not null,
    recipient text not null,
    created_at timestamptz not null default now()
);
create index if not exists notification_deliveries_booking_idx on public.notification_deliveries(booking_id);

-- Every new booking creates an in-dashboard DJ notification immediately.
create or replace function public.notify_new_booking()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    insert into public.notifications(booking_id,notification_type,title,message)
    values(NEW.id,'BOOKING_NEW','New booking request',
           NEW.client_name||' submitted a '||NEW.event_type||' booking request for '||to_char(NEW.event_date,'DD Mon YYYY')||'.');
    return NEW;
end;
$$;

drop trigger if exists trg_notify_new_booking on public.bookings;
create trigger trg_notify_new_booking
after insert on public.bookings
for each row execute function public.notify_new_booking();

-- Admin helper. SECURITY DEFINER avoids RLS recursion.
create or replace function public.is_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
    select exists (
        select 1 from public.profiles
        where id = auth.uid()
          and role = 'admin'
    );
$$;

revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated;

-- Public availability check. Returns only true/false.
create or replace function public.check_dj_availability(
    p_event_date date,
    p_start_time time,
    p_end_time time
)
returns boolean
language plpgsql
security definer
set search_path = public
stable
as $$
begin
    if p_end_time <= p_start_time then
        return false;
    end if;

    if exists (
        select 1 from public.blocked_dates
        where blocked_date = p_event_date
    ) then
        return false;
    end if;

    return not exists (
        select 1
        from public.bookings
        where event_date = p_event_date
          and status in ('ACCEPTED','AWAITING_PAYMENT','CONFIRMED')
          and start_time < p_end_time
          and end_time > p_start_time
    );
end;
$$;

grant execute on function public.check_dj_availability(date,time,time) to anon, authenticated;


-- Public booking submission RPC. Returns the new booking id without exposing the bookings table.
create or replace function public.create_booking_request(
    p_client_name text, p_whatsapp text, p_email text, p_event_type text,
    p_event_date date, p_start_time time, p_end_time time, p_venue text,
    p_location text, p_guest_count integer default null, p_package_id uuid default null, p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    v_id uuid;
begin
    if p_end_time <= p_start_time then raise exception 'End time must be later than start time'; end if;
    if p_event_date < current_date then raise exception 'Event date must be in the future'; end if;
    if p_package_id is null or not exists(select 1 from public.packages where id=p_package_id and active=true) then raise exception 'Please select an active package'; end if;
    if exists(select 1 from public.blocked_dates where blocked_date=p_event_date) then raise exception 'That date is unavailable'; end if;
    insert into public.bookings(client_name,whatsapp,email,event_type,event_date,start_time,end_time,venue,location,guest_count,package_id,notes)
    values(trim(p_client_name),trim(p_whatsapp),trim(p_email),trim(p_event_type),p_event_date,p_start_time,p_end_time,trim(p_venue),trim(p_location),p_guest_count,p_package_id,p_notes)
    returning id into v_id;
    return v_id;
exception
    when exclusion_violation then raise exception 'That time has just been booked. Please choose another time';
end;
$$;
grant execute on function public.create_booking_request(text,text,text,text,date,time,time,text,text,integer,uuid,text) to anon, authenticated;

-- Customer payment portal: exposes only non-sensitive booking details by payment token.
create or replace function public.get_payment_booking(p_token uuid)
returns table (
    id uuid,
    client_name text,
    event_type text,
    event_date date,
    start_time time,
    end_time time,
    venue text,
    total_amount numeric,
    deposit_amount numeric,
    status text
)
language sql
security definer
set search_path = public
stable
as $$
    select b.id,b.client_name,b.event_type,b.event_date,b.start_time,b.end_time,b.venue,
           b.total_amount,b.deposit_amount,b.status
    from public.bookings b
    where b.payment_token = p_token;
$$;
grant execute on function public.get_payment_booking(uuid) to anon, authenticated;

-- Atomic payment verification: payment is marked PAID and booking is confirmed together.
create or replace function public.confirm_booking_payment(
    p_payment_id uuid,
    p_reference text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    v_booking_id uuid;
    v_amount numeric;
    v_deposit numeric;
begin
    if not public.is_admin() then
        raise exception 'Only an admin can verify a payment';
    end if;

    select booking_id, amount into v_booking_id, v_amount
    from public.payments
    where id = p_payment_id
    for update;

    if v_booking_id is null then
        raise exception 'Payment not found';
    end if;

    select coalesce(deposit_amount,0) into v_deposit
    from public.bookings where id = v_booking_id for update;

    update public.payments
       set payment_status='PAID', paid_at=coalesce(paid_at,now()), reference=coalesce(p_reference,reference)
     where id=p_payment_id;

    if v_amount < v_deposit then
        raise exception 'Payment is below the required deposit';
    end if;

    update public.bookings
       set status='CONFIRMED'
     where id=v_booking_id
       and status='AWAITING_PAYMENT';

    insert into public.notifications(booking_id,notification_type,title,message)
    values(v_booking_id,'PAYMENT_RECEIVED','Payment received — booking confirmed',
           'A payment of E'||to_char(v_amount,'FM999999990.00')||' was verified. The booking is now CONFIRMED.');

    return v_booking_id;
end;
$$;
revoke all on function public.confirm_booking_payment(uuid,text) from public;
grant execute on function public.confirm_booking_payment(uuid,text) to authenticated;

-- Public customers may submit a payment-intent record through a payment token.
create or replace function public.submit_payment_intent(
    p_token uuid,
    p_method text,
    p_reference text default null,
    p_amount numeric default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    v_booking_id uuid;
    v_deposit numeric;
    v_payment_id uuid;
begin
    if p_method not in ('EMALI','MOMO','BANK') then raise exception 'Invalid payment method'; end if;
    select id,deposit_amount into v_booking_id,v_deposit from public.bookings
    where payment_token=p_token and status='AWAITING_PAYMENT';
    if v_booking_id is null then raise exception 'Payment is not available for this booking'; end if;
    insert into public.payments(booking_id,amount,payment_type,payment_method,payment_status,reference)
    values(v_booking_id,coalesce(p_amount,v_deposit),'DEPOSIT',p_method,'PENDING',p_reference)
    returning id into v_payment_id;
    insert into public.notifications(booking_id,notification_type,title,message)
    values(v_booking_id,'PAYMENT_ATTEMPT','Payment submitted for verification',
           'The customer submitted a '||p_method||' payment reference. Please verify the payment before confirming the booking.');
    return v_payment_id;
end;
$$;
grant execute on function public.submit_payment_intent(uuid,text,text,numeric) to anon,authenticated;

-- Enable RLS.
alter table public.profiles enable row level security;
alter table public.packages enable row level security;
alter table public.bookings enable row level security;
alter table public.blocked_dates enable row level security;
alter table public.payments enable row level security;
alter table public.reviews enable row level security;
alter table public.payment_settings enable row level security;


-- Payment details are intentionally public because customers need them to pay.
drop policy if exists "Public can read payment settings" on public.payment_settings;
create policy "Public can read payment settings"
on public.payment_settings for select
to anon, authenticated
using (true);

drop policy if exists "Admins manage payment settings" on public.payment_settings;
create policy "Admins manage payment settings"
on public.payment_settings for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

-- Profiles: admin only.
drop policy if exists "Admins can read profiles" on public.profiles;
create policy "Admins can read profiles"
on public.profiles for select
to authenticated
using (public.is_admin());

drop policy if exists "Admins can manage profiles" on public.profiles;
create policy "Admins can manage profiles"
on public.profiles for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

-- Packages: public can read active packages; admin manages all.
drop policy if exists "Public can view active packages" on public.packages;
create policy "Public can view active packages"
on public.packages for select
to anon, authenticated
using (active = true or public.is_admin());

drop policy if exists "Admins manage packages" on public.packages;
create policy "Admins manage packages"
on public.packages for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

-- Bookings: anonymous customers may create pending requests only.
drop policy if exists "Public can submit pending bookings" on public.bookings;
create policy "Public can submit pending bookings"
on public.bookings for insert
to anon, authenticated
with check (
    status = 'PENDING'
    and coalesce(deposit_amount,0) = 0
    and total_amount is null
    and exists (
        select 1 from public.packages p
        where p.id = package_id
          and p.active = true
    )
);

drop policy if exists "Admins can view bookings" on public.bookings;
create policy "Admins can view bookings"
on public.bookings for select
to authenticated
using (public.is_admin());

drop policy if exists "Admins can update bookings" on public.bookings;
create policy "Admins can update bookings"
on public.bookings for update
to authenticated
using (public.is_admin())
with check (public.is_admin());

drop policy if exists "Admins can delete bookings" on public.bookings;
create policy "Admins can delete bookings"
on public.bookings for delete
to authenticated
using (public.is_admin());

-- Blocked dates: public sees only dates for availability; admin manages.
drop policy if exists "Public can view blocked dates" on public.blocked_dates;
create policy "Public can view blocked dates"
on public.blocked_dates for select
to anon, authenticated
using (true);

drop policy if exists "Admins manage blocked dates" on public.blocked_dates;
create policy "Admins manage blocked dates"
on public.blocked_dates for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

-- Payments: admin only.
drop policy if exists "Admins manage payments" on public.payments;
create policy "Admins manage payments"
on public.payments for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

-- Reviews: public sees published reviews; admin manages.
drop policy if exists "Public can view published reviews" on public.reviews;
create policy "Public can view published reviews"
on public.reviews for select
to anon, authenticated
using (published = true or public.is_admin());

drop policy if exists "Admins manage reviews" on public.reviews;
create policy "Admins manage reviews"
on public.reviews for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

-- IMPORTANT:
-- After creating the admin user in Authentication > Users, copy that user's UUID
-- and run:
--
-- insert into public.profiles (id, full_name, role)
-- values ('YOUR-AUTH-USER-UUID', 'Scorpion_Jr', 'admin')
-- on conflict (id) do update set role='admin';


-- Notifications: admin can read/manage DJ notifications.
alter table public.notifications enable row level security;
drop policy if exists "Admins manage notifications" on public.notifications;
create policy "Admins manage notifications"
on public.notifications for all
to authenticated
using (public.is_admin())
with check (public.is_admin());


-- Delivery ledger is server-managed and never exposed to public clients.
alter table public.notification_deliveries enable row level security;
drop policy if exists "No public access to notification deliveries" on public.notification_deliveries;
create policy "No public access to notification deliveries"
on public.notification_deliveries for all
to anon, authenticated
using (false)
with check (false);

-- Customer payment portal must not expose the full bookings table; use RPCs above.
-- Existing admin-only payments policy remains in force.

-- Payments are manual in this version. Provider columns are retained only for backwards compatibility.
alter table public.payments add column if not exists provider text default 'MANUAL';
alter table public.payments add column if not exists provider_reference text;
create index if not exists payments_provider_reference_idx on public.payments(provider_reference);

-- Customer payment details are read from payment_settings.
