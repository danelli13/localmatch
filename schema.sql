-- LocalMatch Supabase database schema
create extension if not exists pgcrypto;

create table if not exists public.leads (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  request text not null,
  zip text not null,
  budget text,
  timeline text not null,
  contact_pref text not null,
  name text not null,
  phone text not null,
  email text not null,
  status text not null default 'new' check (status in ('new','qualified','sold'))
);

alter table public.leads enable row level security;

-- Public customers may submit leads, but cannot read them.
drop policy if exists "public can submit leads" on public.leads;
create policy "public can submit leads"
on public.leads for insert
to anon
with check (true);

-- For this MVP, dashboard reads/updates are intentionally open only to authenticated users.
drop policy if exists "authenticated can read leads" on public.leads;
create policy "authenticated can read leads"
on public.leads for select
to authenticated
using (true);

drop policy if exists "authenticated can update leads" on public.leads;
create policy "authenticated can update leads"
on public.leads for update
to authenticated
using (true)
with check (true);
