create or replace function public.admin_set_user_role(p_user_id uuid, p_role public.app_role)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'هذه العملية متاحة للمدير فقط';
  end if;
  if p_user_id = auth.uid() and p_role <> 'admin' then
    raise exception 'لا يمكنك إزالة صلاحية المدير من حسابك الحالي';
  end if;
  update public.profiles set role = p_role where id = p_user_id;
  if not found then raise exception 'الحساب غير موجود'; end if;
end;
$$;
revoke all on function public.admin_set_user_role(uuid, public.app_role) from public, anon;
grant execute on function public.admin_set_user_role(uuid, public.app_role) to authenticated;
notify pgrst, 'reload schema';
