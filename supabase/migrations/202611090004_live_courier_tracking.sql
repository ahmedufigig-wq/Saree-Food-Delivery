-- Allow a customer to see only the courier location assigned to their active order.
drop policy if exists "couriers read own location" on public.courier_locations;
create policy "courier and active customer read location" on public.courier_locations
for select to authenticated using (
  courier_id = auth.uid()
  or public.is_admin()
  or exists (
    select 1 from public.orders o
    where o.courier_id = courier_locations.courier_id
      and o.customer_id = auth.uid()
      and o.status in ('assigned','picked_up')
  )
);
do $$
begin
  alter publication supabase_realtime add table public.courier_locations;
exception when duplicate_object then null;
end $$;
grant select, insert, update on public.courier_locations to authenticated;
notify pgrst, 'reload schema';