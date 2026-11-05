-- LocalMatch platform foundation: tenant accounts, CRM activity, and safe business access.
-- Additive migration: preserves existing lead/provider records and current admin workflow.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table if not exists public.businesses (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  name text not null,
  slug text not null unique,
  status text not null default 'active' check (status in ('active','pending','suspended')),
  website text,
  phone text,
  email text,
  description text
);

create table if not exists public.business_members (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('owner','manager','sales_rep')),
  created_at timestamptz not null default now(),
  unique (business_id, user_id)
);

alter table public.providers
  add column if not exists business_id uuid references public.businesses(id) on delete set null;

alter table public.provider_leads
  add column if not exists assigned_at timestamptz not null default now(),
  add column if not exists follow_up_at timestamptz,
  add column if not exists updated_at timestamptz not null default now();

create table if not exists public.lead_activity (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  provider_lead_id uuid not null references public.provider_leads(id) on delete cascade,
  actor_user_id uuid references auth.users(id) on delete set null,
  activity_type text not null check (activity_type in ('note','status_change','follow_up_set','contacted','quoted','won','lost')),
  body text,
  old_value text,
  new_value text
);

create table if not exists public.lead_categories (
  id uuid primary key default gen_random_uuid(),
  parent_id uuid references public.lead_categories(id) on delete set null,
  name text not null,
  slug text not null unique,
  description text,
  active boolean not null default true,
  sort_order integer not null default 100,
  created_at timestamptz not null default now()
);

create table if not exists public.platform_settings (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now()
);

insert into public.platform_settings(key,value)
values ('matching_radius_miles','25'::jsonb)
on conflict (key) do nothing;

insert into public.lead_categories(name,slug,sort_order) values
 ('Home & Property','home-property',10),
 ('Automotive & Transportation','automotive-transportation',20),
 ('Real Estate & Housing','real-estate-housing',30),
 ('Financial & Insurance','financial-insurance',40),
 ('Professional Services','professional-services',50),
 ('Business Services & Technology','business-services-technology',60),
 ('Travel, Events & Hospitality','travel-events-hospitality',70),
 ('Personal & Specialty Services','personal-specialty-services',80),
 ('Commercial Equipment & Services','commercial-equipment-services',90)
on conflict (slug) do nothing;

create index if not exists providers_business_id_idx on public.providers(business_id);
create index if not exists provider_leads_provider_id_idx on public.provider_leads(provider_id);
create index if not exists provider_leads_follow_up_at_idx on public.provider_leads(follow_up_at) where follow_up_at is not null;
create index if not exists lead_activity_business_created_idx on public.lead_activity(business_id, created_at desc);
create index if not exists lead_activity_assignment_idx on public.lead_activity(provider_lead_id, created_at desc);
create index if not exists business_members_user_id_idx on public.business_members(user_id);

-- Helper functions live outside exposed schemas and only answer membership questions.
create or replace function private.is_business_member(target_business_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
    from public.business_members bm
    join public.businesses b on b.id = bm.business_id
    where bm.business_id = target_business_id
      and bm.user_id = (select auth.uid())
      and b.status = 'active'
  );
$$;

create or replace function private.is_business_lead_member(target_assignment_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
    from public.provider_leads pl
    join public.providers p on p.id = pl.provider_id
    join public.business_members bm on bm.business_id = p.business_id
    join public.businesses b on b.id = p.business_id
    where pl.id = target_assignment_id
      and bm.user_id = (select auth.uid())
      and b.status = 'active'
  );
$$;

revoke all on function private.is_business_member(uuid) from public, anon;
revoke all on function private.is_business_lead_member(uuid) from public, anon;
grant usage on schema private to authenticated;
grant execute on function private.is_business_member(uuid) to authenticated;
grant execute on function private.is_business_lead_member(uuid) to authenticated;

alter table public.businesses enable row level security;
alter table public.business_members enable row level security;
alter table public.lead_activity enable row level security;
alter table public.lead_categories enable row level security;
alter table public.platform_settings enable row level security;

-- Businesses and memberships are provisioned by the platform admin; members can only see their own business.
drop policy if exists "business members can view their business" on public.businesses;
create policy "business members can view their business"
on public.businesses for select to authenticated
using (private.is_business_member(id));

drop policy if exists "members can view their memberships" on public.business_members;
create policy "members can view their memberships"
on public.business_members for select to authenticated
using (user_id = (select auth.uid()));

-- Public category list is intentionally readable; only platform admin may manage it.
drop policy if exists "anyone can read active categories" on public.lead_categories;
create policy "anyone can read active categories"
on public.lead_categories for select to anon, authenticated
using (active = true);

-- Business users see only assignments belonging to a business they belong to.
drop policy if exists "business members can read assigned leads" on public.provider_leads;
create policy "business members can read assigned leads"
on public.provider_leads for select to authenticated
using (private.is_business_lead_member(id));

drop policy if exists "business members can update assigned leads" on public.provider_leads;
create policy "business members can update assigned leads"
on public.provider_leads for update to authenticated
using (private.is_business_lead_member(id))
with check (private.is_business_lead_member(id));

drop policy if exists "business members can read assigned customer details" on public.leads;
create policy "business members can read assigned customer details"
on public.leads for select to authenticated
using (
  exists (
    select 1
    from public.provider_leads pl
    where pl.lead_id = leads.id
      and private.is_business_lead_member(pl.id)
  )
);

drop policy if exists "business members can read their activity" on public.lead_activity;
create policy "business members can read their activity"
on public.lead_activity for select to authenticated
using (private.is_business_member(business_id));

drop policy if exists "business members can add activity to their assignments" on public.lead_activity;
create policy "business members can add activity to their assignments"
on public.lead_activity for insert to authenticated
with check (
  actor_user_id = (select auth.uid())
  and private.is_business_member(business_id)
  and private.is_business_lead_member(provider_lead_id)
  and exists (
    select 1 from public.provider_leads pl
    join public.providers p on p.id = pl.provider_id
    where pl.id = provider_lead_id and p.business_id = business_id
  )
);

-- Prevent browser roles from directly invoking privileged matching/event-trigger functions.
-- The lead INSERT trigger continues to invoke its trigger function as the function owner.
revoke execute on function public.match_lead_to_providers(uuid) from public, anon, authenticated;
revoke execute on function public.trigger_match_new_lead() from public, anon, authenticated;
revoke execute on function public.rls_auto_enable() from public, anon, authenticated;

-- Explicitly grant the exposed tables only the operations required by their RLS policies.
grant select on public.businesses, public.business_members, public.lead_categories, public.lead_activity to authenticated;
grant insert on public.lead_activity to authenticated;
grant select, update on public.provider_leads to authenticated;
grant select on public.leads to authenticated;
grant select on public.lead_categories to anon;
grant usage, select on all sequences in schema public to authenticated;

comment on table public.businesses is 'A customer-facing business tenant on the LocalMatch platform.';
comment on table public.business_members is 'Users and roles belonging to each business tenant.';
comment on table public.lead_activity is 'Append-only CRM timeline for a business assignment.';
comment on column public.providers.business_id is 'Links a legacy provider record to its business tenant.';
