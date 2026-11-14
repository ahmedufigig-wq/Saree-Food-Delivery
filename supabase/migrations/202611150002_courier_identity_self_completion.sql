-- Couriers become eligible after completing the required identity upload.
-- Restaurant owners, not Saree platform administrators, decide whether to hire them.
-- Existing profiles, documents, applications, memberships, and orders are preserved.

begin;

create or replace function public.protect_profile_privileges()
returns trigger
language plpgsql
security definer
set search_path = 'public', 'pg_temp'
as $function$
begin
  if (
    new.role is distinct from old.role
    or new.approval_status is distinct from old.approval_status
    or new.approved_at is distinct from old.approved_at
  ) and not public.is_admin() then
    if current_setting('saree.allow_courier_identity_complete', true) = 'on'
       and auth.uid() = old.id
       and old.role = 'courier'
       and new.role = old.role
       and old.approval_status in ('pending', 'rejected')
       and new.approval_status = 'approved'
       and new.approved_at is not null then
      return new;
    end if;
    raise exception 'تغيير الدور أو الاعتماد متاح للمدير فقط';
  end if;
  return new;
end;
$function$;

create or replace function public.submit_courier_verification_for_review()
returns void
language plpgsql
security definer
set search_path = 'public', 'pg_temp'
as $function$
declare
  v_uid uuid := auth.uid();
  v_document_count integer;
begin
  if v_uid is null then
    raise exception 'يرجى تسجيل الدخول';
  end if;

  if not exists (
    select 1 from public.profiles
    where id = v_uid and role = 'courier' and is_blocked = false
  ) then
    raise exception 'هذه الخدمة متاحة لحسابات المندوبين فقط';
  end if;

  select count(distinct d.document_type)
    into v_document_count
  from public.courier_verification_documents d
  join storage.objects o
    on o.bucket_id = 'courier-verification'
   and o.name = d.storage_path
  where d.courier_id = v_uid
    and d.document_type in ('id_front', 'id_back', 'selfie')
    and d.storage_path like v_uid::text || '/%';

  if v_document_count <> 3 then
    raise exception 'لم تكتمل صور الهوية والسيلفي؛ أعد إرسال المستندات المطلوبة';
  end if;

  -- This status means the required files were submitted, not that a human
  -- or government authority has authenticated the identity.
  perform set_config('saree.allow_courier_identity_complete', 'on', true);
  update public.profiles
     set approval_status = 'approved',
         approved_at = coalesce(approved_at, now()),
         approval_note = null
   where id = v_uid
     and role = 'courier'
     and approval_status is distinct from 'approved';
end;
$function$;

revoke all on function public.submit_courier_verification_for_review() from public, anon;
grant execute on function public.submit_courier_verification_for_review() to authenticated;

notify pgrst, 'reload schema';
commit;
