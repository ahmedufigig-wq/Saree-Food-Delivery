-- Private, one-time courier identity verification.
begin;

create table if not exists public.courier_verification_documents (
  id uuid primary key default gen_random_uuid(),
  courier_id uuid not null references public.profiles(id) on delete cascade,
  document_type text not null check (document_type in ('id_front','id_back','residence','selfie')),
  storage_path text not null unique,
  created_at timestamptz not null default now(),
  unique (courier_id, document_type),
  constraint courier_verification_path_owner_check
    check (storage_path like courier_id::text || '/%')
);

create index if not exists courier_verification_documents_courier_idx
  on public.courier_verification_documents(courier_id);

alter table public.courier_verification_documents enable row level security;
grant select, insert on public.courier_verification_documents to authenticated;

drop policy if exists courier_verification_read_self_or_admin on public.courier_verification_documents;
create policy courier_verification_read_self_or_admin
  on public.courier_verification_documents for select to authenticated
  using (courier_id = (select auth.uid()) or public.is_admin());

drop policy if exists courier_verification_insert_self on public.courier_verification_documents;
create policy courier_verification_insert_self
  on public.courier_verification_documents for insert to authenticated
  with check (
    courier_id = (select auth.uid())
    and storage_path like (select auth.uid())::text || '/%'
    and exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'courier')
  );

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('courier-verification', 'courier-verification', false, 8388608,
        array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set
  public = false,
  file_size_limit = 8388608,
  allowed_mime_types = array['image/jpeg','image/png','image/webp'];

drop policy if exists courier_verification_upload_own on storage.objects;
create policy courier_verification_upload_own on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'courier-verification'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'courier')
  );

drop policy if exists courier_verification_read_own_or_admin on storage.objects;
create policy courier_verification_read_own_or_admin on storage.objects
  for select to authenticated
  using (
    bucket_id = 'courier-verification'
    and (
      (storage.foldername(name))[1] = (select auth.uid())::text
      or public.is_admin()
    )
  );

-- A courier cannot be approved unless all four metadata rows and their private
-- Storage objects exist under that courier's own folder.
create or replace function public.admin_review_user(p_user_id uuid, p_decision text, p_note text default null)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare target_role text;
begin
  if auth.uid() is null or not public.is_admin() then raise exception 'متاح للمدير فقط'; end if;
  if p_decision not in ('approved','rejected') then raise exception 'قرار اعتماد غير صالح'; end if;
  select role into target_role from public.profiles where id = p_user_id for update;
  if not found then raise exception 'الحساب غير موجود'; end if;
  if target_role in ('customer','admin') then raise exception 'هذا الحساب لا يحتاج اعتماداً'; end if;
  if target_role = 'courier' and p_decision = 'approved' and (
    select count(distinct d.document_type)
    from public.courier_verification_documents d
    join storage.objects o
      on o.bucket_id = 'courier-verification'
     and o.name = d.storage_path
    where d.courier_id = p_user_id
      and d.storage_path like p_user_id::text || '/%'
  ) <> 4 then
    raise exception 'لا يمكن اعتماد المندوب قبل استلام الهوية وإثبات السكن والصورة الشخصية كاملة';
  end if;
  update public.profiles
  set approval_status = p_decision,
      approved_at = case when p_decision = 'approved' then now() else null end,
      approval_note = nullif(trim(coalesce(p_note,'')), '')
  where id = p_user_id;
end;
$$;

revoke all on function public.admin_review_user(uuid,text,text) from public, anon;
grant execute on function public.admin_review_user(uuid,text,text) to authenticated;

notify pgrst, 'reload schema';
commit;
