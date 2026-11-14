-- Preserve earlier uploads, but require a new image-content precheck for all couriers.
-- Old/random images are not deleted; they simply do not satisfy the new gate.

begin;

alter table public.courier_verification_documents
  add column if not exists image_precheck_passed boolean not null default false;

create or replace function public.mark_courier_identity_precheck_passed()
returns void
language plpgsql
security definer
set search_path = 'public', 'pg_temp'
as $function$
declare
  v_uid uuid := auth.uid();
  v_count integer;
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

  with latest as (
    select distinct on (document_type) id
    from public.courier_verification_documents
    where courier_id = v_uid
      and document_type in ('id_front', 'id_back', 'selfie')
      and created_at >= now() - interval '10 minutes'
    order by document_type, created_at desc
  )
  update public.courier_verification_documents d
     set image_precheck_passed = true
    from latest l
   where d.id = l.id;

  select count(distinct d.document_type)
    into v_count
  from public.courier_verification_documents d
  join storage.objects o
    on o.bucket_id = 'courier-verification'
   and o.name = d.storage_path
  where d.courier_id = v_uid
    and d.image_precheck_passed = true
    and d.document_type in ('id_front', 'id_back', 'selfie')
    and d.storage_path like v_uid::text || '/%';

  if v_count <> 3 then
    raise exception 'لم تكتمل صور الهوية الثلاث المطلوبة';
  end if;
end;
$function$;

revoke all on function public.mark_courier_identity_precheck_passed() from public, anon;
grant execute on function public.mark_courier_identity_precheck_passed() to authenticated;

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
    and d.image_precheck_passed = true
    and d.document_type in ('id_front', 'id_back', 'selfie')
    and d.storage_path like v_uid::text || '/%';

  if v_document_count <> 3 then
    raise exception 'لم تجتز صور الهوية فحص المحتوى المطلوب';
  end if;

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
