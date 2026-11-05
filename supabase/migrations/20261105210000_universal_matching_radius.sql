-- Keep provider-specific service radius in the universal lead matcher.
-- All provider types, including repair services, default to 55 miles.
create or replace function public.match_lead_to_providers(p_lead_id uuid)
returns void language plpgsql security definer
set search_path = pg_catalog, public
as $$
begin
  insert into public.provider_leads (lead_id, provider_id, status)
  select l.id, p.id, 'new'
  from public.leads l
  join public.providers p on p.active = true
  join public.zip_centroids lz on lz.zip = left(regexp_replace(coalesce(l.zip,''), '[^0-9]', '', 'g'), 5)
  join public.zip_centroids pz on pz.zip = left(regexp_replace(coalesce(p.zip,''), '[^0-9]', '', 'g'), 5)
  where l.id = p_lead_id
    and (
      lower(regexp_replace(trim(coalesce(p.category,'')), '[^a-z0-9]+', '-', 'g')) =
      lower(regexp_replace(trim(coalesce(l.category,'')), '[^a-z0-9]+', '-', 'g'))
      or lower(coalesce(l.category,'')) like '%' || lower(trim(coalesce(p.category,''))) || '%'
      or lower(coalesce(p.category,'')) like '%' || lower(trim(coalesce(l.category,''))) || '%'
      or exists (
        select 1 from regexp_split_to_table(lower(coalesce(p.services,'')), '[,;|/]+') s(term)
        where length(trim(s.term)) >= 3 and (
          lower(coalesce(l.request,'')) like '%' || trim(s.term) || '%'
          or lower(coalesce(l.category,'')) like '%' || trim(s.term) || '%'
        )
      )
    )
    and 3958.7613 * 2 * asin(sqrt(
      power(sin(radians(pz.latitude-lz.latitude)/2),2) +
      cos(radians(lz.latitude))*cos(radians(pz.latitude))*
      power(sin(radians(pz.longitude-lz.longitude)/2),2)
    )) <= coalesce(p.service_radius_miles, 55)
  on conflict (lead_id, provider_id) do nothing;
end;
$$;
revoke execute on function public.match_lead_to_providers(uuid) from public, anon, authenticated;
