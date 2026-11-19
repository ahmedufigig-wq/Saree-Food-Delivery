begin;

drop function if exists public.restaurant_courier_applications(uuid);

create function public.restaurant_courier_applications(p_restaurant_id uuid)
returns table(
  application_id uuid,
  courier_id uuid,
  full_name text,
  phone text,
  email text,
  status text,
  created_at timestamptz,
  id_front_path text,
  id_back_path text,
  selfie_path text,
  residence_path text,
  platform_approval_status text
)
language plpgsql
security definer
set search_path=public,auth,pg_temp
as $$
declare v_uid uuid:=auth.uid();
begin
  if v_uid is null then raise exception 'يرجى تسجيل الدخول'; end if;
  if not exists(
    select 1 from public.profiles p
    where p.id=v_uid and p.role='restaurant_owner'
      and p.approval_status='approved' and p.is_blocked=false
  ) or not public.is_restaurant_member(p_restaurant_id) then
    raise exception 'ليس لديك صلاحية مراجعة طلبات مندوبي هذا المطعم';
  end if;

  return query
  select
    a.id,
    p.id,
    p.full_name,
    p.phone,
    u.email,
    a.status,
    a.created_at,
    (select d.storage_path from public.courier_verification_documents d
      where d.courier_id=p.id and d.document_type='id_front'
      order by d.created_at desc limit 1),
    (select d.storage_path from public.courier_verification_documents d
      where d.courier_id=p.id and d.document_type='id_back'
      order by d.created_at desc limit 1),
    (select d.storage_path from public.courier_verification_documents d
      where d.courier_id=p.id and d.document_type='selfie'
      order by d.created_at desc limit 1),
    (select d.storage_path from public.courier_verification_documents d
      where d.courier_id=p.id and d.document_type='residence'
      order by d.created_at desc limit 1),
    p.approval_status
  from public.courier_restaurant_applications a
  join public.profiles p on p.id=a.courier_id
  left join auth.users u on u.id=p.id
  where a.restaurant_id=p_restaurant_id
  order by case a.status when 'pending' then 0 when 'accepted' then 1 else 2 end,a.created_at desc;
end;
$$;

revoke all on function public.restaurant_courier_applications(uuid) from public,anon;
grant execute on function public.restaurant_courier_applications(uuid) to authenticated;
notify pgrst,'reload schema';

commit;