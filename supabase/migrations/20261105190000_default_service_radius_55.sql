-- LocalMatch default service radius.
-- Businesses can override this per provider record; 55 miles is the platform default.
alter table public.providers
  add column if not exists service_radius_miles integer not null default 55
  check (service_radius_miles between 1 and 250);

insert into public.platform_settings(key,value)
values ('matching_radius_miles','55'::jsonb)
on conflict (key) do update
set value = excluded.value, updated_at = now();
