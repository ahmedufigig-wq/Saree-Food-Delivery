-- Expose approval status in the restaurant's own courier team list.
-- Existing team links and user/order data are preserved.
create or replace function public.restaurant_courier_team_v2(p_restaurant_id uuid)
returns table(
  courier_id uuid,
  full_name text,
  phone text,
  is_active boolean,
  is_available boolean,
  last_seen timestamptz,
  approval_status text
)
language plpgsql
security definer
set search_path = 'public', 'pg_temp'
as $function$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'يرجى تسجيل الدخول';
  end if;

  if not exists (
    select 1 from public.profiles p
    where p.id = v_uid
      and p.role = 'restaurant_owner'
      and p.approval_status = 'approved'
      and p.is_blocked = false
  ) or not public.is_restaurant_member(p_restaurant_id) then
    raise exception 'ليس لديك صلاحية إدارة فريق هذا المطعم';
  end if;

  return query
  select p.id, p.full_name, p.phone, rc.is_active,
    coalesce(cl.is_available and cl.updated_at >= now() - interval '15 minutes', false),
    cl.updated_at, p.approval_status
  from public.restaurant_couriers rc
  join public.profiles p on p.id = rc.courier_id
  left join public.courier_locations cl on cl.courier_id = p.id
  where rc.restaurant_id = p_restaurant_id
  order by (p.approval_status = 'pending') desc, rc.is_active desc, p.full_name;
end;
$function$;

revoke execute on function public.restaurant_courier_team_v2(uuid) from public, anon;
grant execute on function public.restaurant_courier_team_v2(uuid) to authenticated;
