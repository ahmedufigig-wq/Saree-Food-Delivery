-- Keep courier location writes tied to a live delivery.
-- Customers only see a fresh location for their own assigned/picked-up order.
begin;

drop policy if exists "couriers manage own location" on public.courier_locations;
drop policy if exists "couriers insert location during active delivery" on public.courier_locations;
drop policy if exists "couriers update location during active delivery or stop" on public.courier_locations;
drop policy if exists "couriers delete own location" on public.courier_locations;
drop policy if exists "courier and active customer read location" on public.courier_locations;

create policy "courier and active customer read location"
on public.courier_locations
for select
to authenticated
using (
  courier_id = (select auth.uid())
  or (select public.is_admin())
  or (
    is_available is true
    and updated_at >= now() - interval '2 minutes'
    and exists (
      select 1
      from public.orders o
      where o.courier_id = courier_locations.courier_id
        and o.customer_id = (select auth.uid())
        and o.status in ('assigned', 'picked_up')
    )
  )
);

create policy "couriers insert location during active delivery"
on public.courier_locations
for insert
to authenticated
with check (
  (select public.is_admin())
  or (
    courier_id = (select auth.uid())
    and is_available is true
    and exists (
      select 1
      from public.orders o
      where o.courier_id = (select auth.uid())
        and o.status in ('assigned', 'picked_up')
    )
  )
);

create policy "couriers update location during active delivery or stop"
on public.courier_locations
for update
to authenticated
using (
  courier_id = (select auth.uid())
  or (select public.is_admin())
)
with check (
  (select public.is_admin())
  or (
    courier_id = (select auth.uid())
    and (
      is_available is false
      or exists (
        select 1
        from public.orders o
        where o.courier_id = (select auth.uid())
          and o.status in ('assigned', 'picked_up')
      )
    )
  )
);

create policy "couriers delete own location"
on public.courier_locations
for delete
to authenticated
using (
  courier_id = (select auth.uid())
  or (select public.is_admin())
);

commit;
