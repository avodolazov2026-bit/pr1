create or replace function public.create_group(
  p_name text,
  p_starts_at timestamp with time zone default now(),
  p_ends_at timestamp with time zone default null
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_user_id uuid := auth.uid();
  v_group_id uuid;
  v_display_name text;
begin
  if v_user_id is null then
    raise exception 'Требуется авторизация';
  end if;
  if coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then
    raise exception 'Создание группы доступно после подтверждения номера телефона';
  end if;
  if char_length(btrim(coalesce(p_name, ''))) not between 1 and 120 then
    raise exception 'Название группы должно содержать от 1 до 120 символов';
  end if;
  if p_starts_at is null
     or (p_ends_at is not null and p_ends_at <= p_starts_at) then
    raise exception 'Время окончания должно быть позже времени начала';
  end if;
  select display_name
  into v_display_name
  from public.profiles
  where id = v_user_id;
  insert into public.groups (name, creator_id, starts_at, ends_at)
  values (btrim(p_name), v_user_id, p_starts_at, p_ends_at)
  returning id into v_group_id;
  insert into public.memberships (
    group_id,
    user_id,
    role,
    status,
    display_name
  )
  values (
    v_group_id,
    v_user_id,
    'organizer',
    'active',
    coalesce(v_display_name, 'Участник')
  );
  insert into public.group_invite_links (group_id, created_by_user_id)
  values (v_group_id, v_user_id);
  return v_group_id;
end;
$function$;
