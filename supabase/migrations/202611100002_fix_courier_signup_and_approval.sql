-- Correct role and approval state for new signups.
-- Only the allowed self-selected account types are accepted; non-customer
-- roles are always pending until an administrator approves them.
create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  requested_role text;
  new_name text;
  new_phone text;
begin
  requested_role := coalesce(nullif(trim(new.raw_user_meta_data ->> 'requested_role'), ''), 'customer');
  if requested_role not in ('customer', 'courier', 'restaurant_owner') then
    requested_role := 'customer';
  end if;

  new_name := coalesce(
    nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''),
    split_part(coalesce(new.email, ''), '@', 1)
  );
  new_phone := nullif(trim(coalesce(new.raw_user_meta_data ->> 'phone', '')), '');

  insert into public.profiles (
    id, full_name, phone, role, approval_status,
    approval_requested_at, approved_at, approval_note
  )
  values (
    new.id,
    new_name,
    new_phone,
    requested_role::public.app_role,
    case when requested_role = 'customer' then 'approved' else 'pending' end,
    case when requested_role = 'customer' then null else now() end,
    case when requested_role = 'customer' then now() else null end,
    null
  )
  on conflict (id) do nothing;

  if requested_role in ('courier', 'restaurant_owner') then
    insert into public.notifications (user_id, title, body, kind)
    select p.id,
           'طلب اعتماد جديد',
           'يوجد طلب تسجيل جديد بصفة ' ||
             case when requested_role = 'courier' then 'مندوب توصيل' else 'صاحب مطعم' end ||
             ' ويحتاج إلى مراجعة الإدارة.',
           'account_approval'
    from public.profiles p
    where p.role = 'admin';
  end if;

  return new;
end;
$function$;

-- Keep app users from changing their own role or approval status. Trusted
-- direct database operators retain maintenance capability for controlled fixes.
create or replace function public.protect_profile_privileges()
returns trigger
language plpgsql
security definer
set search_path = 'public', 'pg_temp'
as $function$
begin
  if session_user not in ('postgres', 'supabase_admin')
     and (
       new.role is distinct from old.role
       or new.approval_status is distinct from old.approval_status
       or new.approved_at is distinct from old.approved_at
     )
     and not public.is_admin() then
    raise exception 'تغيير الدور أو الاعتماد متاح للمدير فقط';
  end if;
  return new;
end;
$function$;
