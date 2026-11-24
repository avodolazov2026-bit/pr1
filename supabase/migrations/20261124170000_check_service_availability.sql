-- Лёгкая проверка, что API и база отвечают. Данных не читает и не меняет.

create or replace function public.check_service_availability()
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select true;
$$;

revoke all privileges on function public.check_service_availability()
  from public, anon, authenticated;
grant execute on function public.check_service_availability()
  to anon, authenticated;
