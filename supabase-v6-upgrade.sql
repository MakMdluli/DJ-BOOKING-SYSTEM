-- SCORPION_JR V6 UPGRADE
-- Run AFTER the existing V4 schema in Supabase SQL Editor.
-- Adds quotations, invoices, customer document access, and invoice payment tracking.

create sequence if not exists public.quotation_number_seq;
create sequence if not exists public.invoice_number_seq;

create table if not exists public.quotations (
    id uuid primary key default gen_random_uuid(),
    booking_id uuid not null unique references public.bookings(id) on delete cascade,
    quotation_number text not null unique,
    issued_at timestamptz not null default now(),
    valid_until date,
    service_description text not null default 'Professional DJ performance and entertainment services for the specified event.',
    total_amount numeric(12,2) not null default 0 check (total_amount >= 0),
    deposit_amount numeric(12,2) not null default 0 check (deposit_amount >= 0),
    artist_rider text,
    terms text,
    status text not null default 'SENT' check (status in ('DRAFT','SENT','ACCEPTED','EXPIRED','CANCELLED')),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table if not exists public.invoices (
    id uuid primary key default gen_random_uuid(),
    booking_id uuid not null unique references public.bookings(id) on delete cascade,
    invoice_number text not null unique,
    issued_at timestamptz not null default now(),
    due_date date,
    total_amount numeric(12,2) not null default 0 check (total_amount >= 0),
    amount_paid numeric(12,2) not null default 0 check (amount_paid >= 0),
    balance_due numeric(12,2) not null default 0 check (balance_due >= 0),
    status text not null default 'UNPAID' check (status in ('UNPAID','PARTIALLY_PAID','PAID','VOID')),
    notes text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index if not exists quotations_booking_id_idx on public.quotations(booking_id);
create index if not exists invoices_booking_id_idx on public.invoices(booking_id);
create index if not exists invoices_status_idx on public.invoices(status);

-- Artist-document defaults based on the supplied quotation sample.
create or replace function public.default_quotation_terms()
returns text
language sql
immutable
as $$
select 'This quotation is valid for 30 days from the date of issue.\nAny changes to the event details may affect the quoted price.\nCancellation terms will apply once the booking has been confirmed.\nDJ services only; sound equipment, lighting, staging and other technical requirements are not included unless separately agreed in writing.\nA deposit is required to confirm the booking. The balance must be paid before or on the day of the event. Proof of payment may be requested before performance.';
$$;

create or replace function public.default_artist_rider()
returns text
language sql
immutable
as $$
select 'Artist rider: a bottle and/or 12-pack may be required with ice and a cool drink option such as Schweppes, Appletiser or Red Bull. Bottled water will also be required (1.5L bottle). Rider requirements should be agreed with the client before the event.';
$$;

create or replace function public.make_quotation_for_booking(p_booking_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    v_id uuid;
    v_number text;
    v_date date;
    v_total numeric;
    v_deposit numeric;
begin
    select event_date, coalesce(total_amount,0), coalesce(deposit_amount,0)
      into v_date, v_total, v_deposit
    from public.bookings where id=p_booking_id for update;
    if v_date is null then raise exception 'Booking not found'; end if;

    select id into v_id from public.quotations where booking_id=p_booking_id;
    if v_id is not null then
        update public.quotations
           set total_amount=v_total, deposit_amount=v_deposit, updated_at=now()
         where id=v_id;
        return v_id;
    end if;

    v_number := 'QTN-' || to_char(current_date,'YYYY') || '-' || lpad(nextval('public.quotation_number_seq')::text,4,'0');
    insert into public.quotations(booking_id,quotation_number,valid_until,total_amount,deposit_amount,artist_rider,terms,status)
    values(p_booking_id,v_number,current_date + 30,v_total,v_deposit,public.default_artist_rider(),public.default_quotation_terms(),'SENT')
    returning id into v_id;
    return v_id;
end;
$$;

create or replace function public.make_invoice_for_booking(p_booking_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    v_id uuid;
    v_number text;
    v_date date;
    v_total numeric;
    v_paid numeric;
begin
    select event_date, coalesce(total_amount,0) into v_date, v_total
    from public.bookings where id=p_booking_id for update;
    if v_date is null then raise exception 'Booking not found'; end if;

    select id into v_id from public.invoices where booking_id=p_booking_id;
    select coalesce(sum(amount),0) into v_paid
      from public.payments where booking_id=p_booking_id and payment_status='PAID';

    if v_id is not null then
        update public.invoices
           set total_amount=v_total,
               amount_paid=v_paid,
               balance_due=greatest(v_total-v_paid,0),
               status=case when v_paid >= v_total and v_total > 0 then 'PAID' when v_paid > 0 then 'PARTIALLY_PAID' else 'UNPAID' end,
               updated_at=now()
         where id=v_id;
        return v_id;
    end if;

    v_number := 'INV-' || to_char(current_date,'YYYY') || '-' || lpad(nextval('public.invoice_number_seq')::text,4,'0');
    insert into public.invoices(booking_id,invoice_number,due_date,total_amount,amount_paid,balance_due,status,notes)
    values(p_booking_id,v_number,v_date,v_total,v_paid,greatest(v_total-v_paid,0),
           case when v_paid >= v_total and v_total > 0 then 'PAID' when v_paid > 0 then 'PARTIALLY_PAID' else 'UNPAID' end,
           'Generated from the confirmed DJ booking.')
    returning id into v_id;
    return v_id;
end;
$$;

-- Create/update documents as the booking moves through the workflow.
create or replace function public.sync_booking_documents()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if new.status in ('ACCEPTED','AWAITING_PAYMENT','CONFIRMED','COMPLETED') then
        perform public.make_quotation_for_booking(new.id);
    end if;
    if new.status in ('CONFIRMED','COMPLETED') then
        perform public.make_invoice_for_booking(new.id);
    end if;
    return new;
end;
$$;

drop trigger if exists trg_sync_booking_documents on public.bookings;
create trigger trg_sync_booking_documents
after insert or update of status,total_amount,deposit_amount on public.bookings
for each row execute function public.sync_booking_documents();

-- Keep invoice totals in sync when payments are verified/changed.
create or replace function public.sync_invoice_after_payment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if exists(select 1 from public.invoices where booking_id=coalesce(new.booking_id,old.booking_id)) then
        update public.invoices i
           set amount_paid=(select coalesce(sum(p.amount),0) from public.payments p where p.booking_id=i.booking_id and p.payment_status='PAID'),
               balance_due=greatest(i.total_amount-(select coalesce(sum(p.amount),0) from public.payments p where p.booking_id=i.booking_id and p.payment_status='PAID'),0),
               status=case
                    when (select coalesce(sum(p.amount),0) from public.payments p where p.booking_id=i.booking_id and p.payment_status='PAID') >= i.total_amount and i.total_amount > 0 then 'PAID'
                    when (select coalesce(sum(p.amount),0) from public.payments p where p.booking_id=i.booking_id and p.payment_status='PAID') > 0 then 'PARTIALLY_PAID'
                    else 'UNPAID' end,
               updated_at=now()
         where i.booking_id=coalesce(new.booking_id,old.booking_id);
    end if;
    return coalesce(new,old);
end;
$$;

drop trigger if exists trg_sync_invoice_after_payment on public.payments;
create trigger trg_sync_invoice_after_payment
after insert or update of amount,payment_status on public.payments
for each row execute function public.sync_invoice_after_payment();

-- Customer-facing document data is protected by the booking payment token.
create or replace function public.get_customer_documents(p_token uuid)
returns jsonb
language sql
security definer
set search_path = public
stable
as $$
select jsonb_build_object(
    'booking', jsonb_build_object(
        'id',b.id,'client_name',b.client_name,'event_type',b.event_type,'event_date',b.event_date,
        'start_time',b.start_time,'end_time',b.end_time,'venue',b.venue,'location',b.location,
        'total_amount',b.total_amount,'deposit_amount',b.deposit_amount,'status',b.status
    ),
    'quotation', (select to_jsonb(q) from public.quotations q where q.booking_id=b.id),
    'invoice', (select to_jsonb(i) from public.invoices i where i.booking_id=b.id),
    'payments', coalesce((select jsonb_agg(jsonb_build_object('amount',p.amount,'payment_method',p.payment_method,'payment_status',p.payment_status,'reference',p.reference,'created_at',p.created_at,'paid_at',p.paid_at) order by p.created_at desc) from public.payments p where p.booking_id=b.id),'[]'::jsonb)
)
from public.bookings b
where b.payment_token=p_token;
$$;
grant execute on function public.get_customer_documents(uuid) to anon, authenticated;

-- Admin access.
alter table public.quotations enable row level security;
alter table public.invoices enable row level security;

drop policy if exists "Admins manage quotations" on public.quotations;
create policy "Admins manage quotations" on public.quotations for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "Admins manage invoices" on public.invoices;
create policy "Admins manage invoices" on public.invoices for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Keep these helper functions admin-only.
revoke all on function public.make_quotation_for_booking(uuid) from public;
grant execute on function public.make_quotation_for_booking(uuid) to authenticated;
revoke all on function public.make_invoice_for_booking(uuid) from public;
grant execute on function public.make_invoice_for_booking(uuid) to authenticated;

-- DJ Setlist Builder
create table if not exists public.music_tracks (
    id uuid primary key default gen_random_uuid(),
    title text not null,
    artist text,
    bpm numeric(6,2),
    musical_key text,
    genre text,
    energy integer check (energy is null or energy between 1 and 10),
    notes text,
    created_at timestamptz not null default now()
);

create table if not exists public.setlists (
    id uuid primary key default gen_random_uuid(),
    name text not null,
    notes text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table if not exists public.setlist_tracks (
    id uuid primary key default gen_random_uuid(),
    setlist_id uuid not null references public.setlists(id) on delete cascade,
    track_id uuid not null references public.music_tracks(id) on delete cascade,
    position integer not null default 1,
    notes text,
    unique(setlist_id,track_id),
    unique(setlist_id,position)
);

alter table public.bookings add column if not exists setlist_id uuid references public.setlists(id) on delete set null;

alter table public.music_tracks enable row level security;
alter table public.setlists enable row level security;
alter table public.setlist_tracks enable row level security;

drop policy if exists "Admins manage music tracks" on public.music_tracks;
create policy "Admins manage music tracks" on public.music_tracks for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "Admins manage setlists" on public.setlists;
create policy "Admins manage setlists" on public.setlists for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "Admins manage setlist tracks" on public.setlist_tracks;
create policy "Admins manage setlist tracks" on public.setlist_tracks for all to authenticated using (public.is_admin()) with check (public.is_admin());

create index if not exists setlist_tracks_setlist_idx on public.setlist_tracks(setlist_id,position);
