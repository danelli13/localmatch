create table if not exists public.billing_plans (
 id text primary key, name text not null,
 billing_model text not null check (billing_model in ('per_lead','subscription','custom')),
 price_cents integer check (price_cents is null or price_cents >= 0),
 currency text not null default 'usd' check (currency='usd'),
 interval text check (interval is null or interval in ('month','year')),
 included_leads integer check (included_leads is null or included_leads >= 0),
 active boolean not null default false, display_order integer not null default 0,
 description text, stripe_price_id text,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 constraint billing_plans_interval_model check ((billing_model='subscription' and interval is not null) or (billing_model<>'subscription' and interval is null))
);
insert into public.billing_plans(id,name,billing_model,price_cents,interval,included_leads,active,display_order,description)
values ('starter','Starter','per_lead',null,null,0,false,1,'Pay only for leads your business accepts.'),('growth','Growth','subscription',null,'month',null,false,2,'Monthly plan with an included lead allowance.'),('premium','Premium','custom',null,null,null,false,3,'Custom volume and service-area arrangements.')
on conflict(id) do nothing;
create table if not exists public.business_subscriptions (
 id uuid primary key default gen_random_uuid(), business_id uuid not null references public.businesses(id) on delete cascade,
 plan_id text not null references public.billing_plans(id), stripe_customer_id text unique, stripe_subscription_id text unique,
 status text not null default 'incomplete' check(status in ('incomplete','trialing','active','past_due','canceled','unpaid','paused')),
 current_period_start timestamptz, current_period_end timestamptz, cancel_at_period_end boolean not null default false,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index if not exists business_subscriptions_business_idx on public.business_subscriptions(business_id,status);
create table if not exists public.lead_charges (
 id uuid primary key default gen_random_uuid(), business_id uuid not null references public.businesses(id) on delete cascade,
 provider_lead_id uuid not null references public.provider_leads(id) on delete cascade, lead_id uuid not null references public.leads(id) on delete cascade,
 amount_cents integer not null check(amount_cents>0), currency text not null default 'usd' check(currency='usd'),
 status text not null default 'pending' check(status in ('pending','checkout_created','paid','failed','refunded','disputed','void')),
 stripe_checkout_session_id text unique, stripe_payment_intent_id text unique, paid_at timestamptz, refunded_at timestamptz,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(provider_lead_id)
);
create index if not exists lead_charges_business_status_idx on public.lead_charges(business_id,status,created_at desc);
create table if not exists public.stripe_webhook_events (
 id text primary key, event_type text not null, processed_at timestamptz, processing_error text, created_at timestamptz not null default now()
);
create table if not exists public.billing_ledger (
 id uuid primary key default gen_random_uuid(), business_id uuid references public.businesses(id) on delete set null,
 lead_charge_id uuid references public.lead_charges(id) on delete set null, subscription_id uuid references public.business_subscriptions(id) on delete set null,
 entry_type text not null check(entry_type in ('lead_payment','subscription_payment','refund','dispute','adjustment')),
 amount_cents integer not null, currency text not null default 'usd' check(currency='usd'),
 stripe_balance_transaction_id text unique, stripe_invoice_id text, created_at timestamptz not null default now()
);
create index if not exists billing_ledger_business_date_idx on public.billing_ledger(business_id,created_at desc);
alter table public.billing_plans enable row level security;
alter table public.business_subscriptions enable row level security;
alter table public.lead_charges enable row level security;
alter table public.stripe_webhook_events enable row level security;
alter table public.billing_ledger enable row level security;
create policy "Active plans are readable" on public.billing_plans for select to anon,authenticated using(active=true);
create policy "Platform admin manages billing plans" on public.billing_plans for all to authenticated using(auth.uid()='24414e46-0e3c-4979-b5c5-08dad6b39158'::uuid) with check(auth.uid()='24414e46-0e3c-4979-b5c5-08dad6b39158'::uuid);
create policy "Business members read own subscriptions" on public.business_subscriptions for select to authenticated using(private.is_business_member(business_id));
create policy "Platform admin manages subscriptions" on public.business_subscriptions for all to authenticated using(auth.uid()='24414e46-0e3c-4979-b5c5-08dad6b39158'::uuid) with check(auth.uid()='24414e46-0e3c-4979-b5c5-08dad6b39158'::uuid);
create policy "Business members read own lead charges" on public.lead_charges for select to authenticated using(private.is_business_member(business_id));
create policy "Platform admin manages lead charges" on public.lead_charges for all to authenticated using(auth.uid()='24414e46-0e3c-4979-b5c5-08dad6b39158'::uuid) with check(auth.uid()='24414e46-0e3c-4979-b5c5-08dad6b39158'::uuid);
create policy "Platform admin reads webhook events" on public.stripe_webhook_events for select to authenticated using(auth.uid()='24414e46-0e3c-4979-b5c5-08dad6b39158'::uuid);
create policy "Platform admin reads billing ledger" on public.billing_ledger for select to authenticated using(auth.uid()='24414e46-0e3c-4979-b5c5-08dad6b39158'::uuid);
create policy "Business members read own billing ledger" on public.billing_ledger for select to authenticated using(business_id is not null and private.is_business_member(business_id));
revoke all on public.stripe_webhook_events from anon,authenticated;
revoke insert,update,delete on public.business_subscriptions,public.lead_charges,public.billing_ledger from anon,authenticated;
grant select on public.billing_plans to anon,authenticated;
grant select on public.business_subscriptions,public.lead_charges,public.billing_ledger to authenticated;