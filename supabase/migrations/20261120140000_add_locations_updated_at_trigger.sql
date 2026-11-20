create or replace function public.set_locations_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_locations_updated_at on public.locations;

create trigger set_locations_updated_at
before update on public.locations
for each row
execute function public.set_locations_updated_at();
