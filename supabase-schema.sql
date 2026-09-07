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
            'PENDING','ACCEPTED','AWAITING_DEPOSIT','CONFIRMED',
            'COMPLETED','DECLINED','CANCELLED'
        )),
    deposit_amount numeric(12,2) default 0,
    total_amount numeric(12,2),
    created_at timestamptz not null default now(),
    check (end_time > start_time),
    check (guest_count is null or guest_count > 0),
    check (deposit_amount >= 0)
);

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

do $$
begin
    alter table public.bookings
        add constraint no_active_booking_overlap
        exclude using gist (
            event_window with &&
        )
        where (status in ('ACCEPTED','AWAITING_DEPOSIT','CONFIRMED'));
exception
    when duplicate_object then null;
end $$;

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
    payment_status text not null default 'PENDING',
    paid_at timestamptz,
    reference text,
    created_at timestamptz not null default now()
);

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
          and status in ('ACCEPTED','AWAITING_DEPOSIT','CONFIRMED')
          and start_time < p_end_time
          and end_time > p_start_time
    );
end;
$$;

grant execute on function public.check_dj_availability(date,time,time) to anon, authenticated;

-- Enable RLS.
alter table public.profiles enable row level security;
alter table public.packages enable row level security;
alter table public.bookings enable row level security;
alter table public.blocked_dates enable row level security;
alter table public.payments enable row level security;
alter table public.reviews enable row level security;

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
