-- Keep all active restaurants open 24 hours, every day.
-- Equal opening and closing times mean "open all day" in create_order().
-- Relax the table constraint to permit that representation.
alter table public.restaurant_hours
  drop constraint if exists restaurant_hours_check;

alter table public.restaurant_hours
  add constraint restaurant_hours_check
  check (
    is_closed
    or (
      opens_at is not null
      and closes_at is not null
      and opens_at <= closes_at
    )
  );

update public.restaurant_hours h
set opens_at = time '00:00',
    closes_at = time '00:00',
    is_closed = false
from public.restaurants r
where r.id = h.restaurant_id
  and r.is_active = true;
