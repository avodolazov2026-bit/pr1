-- Многоразовая HTTPS-ссылка группы.
--
-- Переиспользуется public.group_invite_links: одна строка на группу.
-- Личные invitations не подходят для общей ссылки: там обязателен конкретный
-- получатель, запрет пригласить себя, один pending на пару группа+получатель
-- и политика чтения для организатора. Открывшие ссылку стали бы видны как
-- личные приглашения. Поэтому сохранённые ссылки лежат отдельно.
-- Исходный токен остаётся в group_invite_links.token: create_or_get должен
-- вернуть ту же действующую ссылку. В сохранённой записи хранится только хеш.
-- Просмотр, сохранение и вступление токен не отзывают и не заменяют.

alter table public.group_invite_links
  add column if not exists id uuid not null default gen_random_uuid();

create unique index if not exists group_invite_links_id_key
  on public.group_invite_links (id);

comment on table public.group_invite_links is
  'Одна многоразовая ссылка на группу. Просмотр и вступление не отзывают токен.';

comment on column public.group_invite_links.token is
  'Случайные 32 байта в hex. Клиентам таблица недоступна; токен отдаёт только RPC организатора.';

-- Сохранённое входящее приглашение по общей ссылке. Токена здесь нет.
create type public.saved_group_invitation_status as enum ('pending', 'accepted');

create table public.saved_group_invitations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  group_id uuid not null references public.groups(id) on delete cascade,
  invite_link_id uuid not null references public.group_invite_links(id) on delete cascade,
  token_hash text not null,
  status public.saved_group_invitation_status not null default 'pending',
  seen_at timestamptz,
  accepted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint saved_group_invitations_token_hash_format check (token_hash ~ '^[0-9a-f]{64}$'),
  constraint saved_group_invitations_accepted_at check (
    (status = 'accepted' and accepted_at is not null)
    or (status = 'pending' and accepted_at is null)
  )
);

create unique index saved_group_invitations_user_group_key
  on public.saved_group_invitations (user_id, group_id);

create index saved_group_invitations_user_pending_idx
  on public.saved_group_invitations (user_id, created_at desc)
  where status = 'pending';

create trigger saved_group_invitations_set_updated_at
before update on public.saved_group_invitations
for each row execute function public.set_updated_at();

alter table public.saved_group_invitations enable row level security;

comment on table public.saved_group_invitations is
  'Входящая общая ссылка текущего пользователя. Не членство и не личное invitation.';

create or replace function public.create_or_get_group_invitation(p_group_id uuid)
returns table (
  invitation_id uuid,
  invite_token text,
  group_id uuid,
  is_active boolean,
  expires_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  v_user_id uuid := auth.uid();
  v_id uuid;
  v_token text;
  v_expires_at timestamptz;
  v_revoked_at timestamptz;
begin
  if v_user_id is null then
    raise exception 'Требуется авторизация';
  end if;
  if coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then
    -- Как в create_group: единственный неанонимный вход в проекте — телефонный OTP.
    raise exception 'Приглашение может создать только организатор с подтверждённым номером телефона';
  end if;
  if p_group_id is null or not exists (
    select 1
    from public.memberships m
    where m.group_id = p_group_id
      and m.user_id = v_user_id
      and m.role = 'organizer'
      and m.status = 'active'
  ) then
    raise exception 'Недостаточно прав';
  end if;
  if not exists (
    select 1
    from public.groups g
    where g.id = p_group_id
      and g.ended_at is null
      and (g.ends_at is null or g.ends_at > now())
  ) then
    raise exception 'Группа недоступна для приглашений';
  end if;

  -- Одна активная ссылка даже при двух одновременных вызовах.
  perform pg_advisory_xact_lock(hashtext('group-invite:' || p_group_id::text));

  perform 1
  from public.groups g
  where g.id = p_group_id
    and g.ended_at is null
    and (g.ends_at is null or g.ends_at > now())
  for update;

  if not found then
    raise exception 'Группа недоступна для приглашений';
  end if;

  select l.id, l.token, l.expires_at, l.revoked_at
    into v_id, v_token, v_expires_at, v_revoked_at
  from public.group_invite_links l
  where l.group_id = p_group_id
  for update;

  if found
     and v_revoked_at is null
     and (v_expires_at is null or v_expires_at > now()) then
    return query
    select v_id, v_token, p_group_id, true, v_expires_at;
    return;
  end if;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');

  if found then
    update public.group_invite_links
    set token = v_token,
        revoked_at = null,
        expires_at = null,
        created_by_user_id = v_user_id,
        created_at = now()
    where group_id = p_group_id
    returning id into v_id;
  else
    insert into public.group_invite_links (group_id, token, created_by_user_id)
    values (p_group_id, v_token, v_user_id)
    returning id into v_id;
  end if;

  return query
  select v_id, v_token, p_group_id, true, null::timestamptz;
end;
$$;

create or replace function public.revoke_group_invitation(p_group_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'Требуется авторизация';
  end if;
  if coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then
    -- Как в create_group: единственный неанонимный вход в проекте — телефонный OTP.
    raise exception 'Приглашение может отозвать только организатор с подтверждённым номером телефона';
  end if;
  if p_group_id is null then
    raise exception 'Недостаточно прав';
  end if;

  -- Тот же ключ, что у create_or_get: операции выполняются целиком по очереди.
  perform pg_advisory_xact_lock(hashtext('group-invite:' || p_group_id::text));

  if not exists (
    select 1
    from public.memberships m
    where m.group_id = p_group_id
      and m.user_id = v_user_id
      and m.role = 'organizer'
      and m.status = 'active'
  ) then
    raise exception 'Недостаточно прав';
  end if;

  -- Завершённую группу не отзываем: тот же критерий, что у create_or_get.
  perform 1
  from public.groups g
  where g.id = p_group_id
    and g.ended_at is null
    and (g.ends_at is null or g.ends_at > now())
  for update;

  if not found then
    return false;
  end if;

  update public.group_invite_links
  set revoked_at = now()
  where group_id = p_group_id
    and revoked_at is null;

  return found;
end;
$$;

-- Публичная проверка токена. Не пишет в базу и не различает причину отказа.
create or replace function public.resolve_group_invitation(p_invite_token text)
returns table (
  available boolean,
  invitation_id uuid,
  group_id uuid,
  group_name text,
  starts_at timestamptz,
  ends_at timestamptz,
  organizer_display_name text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if p_invite_token is null or p_invite_token !~ '^[0-9a-f]{64}$' then
    return query
    select
      false,
      null::uuid,
      null::uuid,
      null::text,
      null::timestamptz,
      null::timestamptz,
      null::text;
    return;
  end if;

  return query
  select
    true,
    l.id,
    g.id,
    g.name,
    g.starts_at,
    g.ends_at,
    org.display_name
  from public.group_invite_links l
  join public.groups g on g.id = l.group_id
  join lateral (
    select m.display_name
    from public.memberships m
    where m.group_id = g.id
      and m.role = 'organizer'
      and m.status = 'active'
    limit 1
  ) org on true
  where l.token = p_invite_token
    and l.revoked_at is null
    and (l.expires_at is null or l.expires_at > now())
    and g.ended_at is null
    and (g.ends_at is null or g.ends_at > now());

  if found then
    return;
  end if;

  return query
  select
    false,
    null::uuid,
    null::uuid,
    null::text,
    null::timestamptz,
    null::timestamptz,
    null::text;
end;
$$;

-- Явное вступление. Токен остаётся многоразовым.
create or replace function public.accept_group_invitation(p_invite_token text)
returns table (
  group_id uuid,
  membership_result text
)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  v_user_id uuid := auth.uid();
  v_group_id uuid;
  v_display_name text;
begin
  if v_user_id is null then
    raise exception 'Требуется авторизация';
  end if;
  if p_invite_token is null or p_invite_token !~ '^[0-9a-f]{64}$' then
    raise exception 'Приглашение недоступно';
  end if;

  select l.group_id
    into v_group_id
  from public.group_invite_links l
  where l.token = p_invite_token;

  if v_group_id is null then
    raise exception 'Приглашение недоступно';
  end if;

  -- Тот же ключ, что у create_or_get и revoke. Держится до конца транзакции.
  perform pg_advisory_xact_lock(hashtext('group-invite:' || v_group_id::text));

  -- Повторная проверка уже под замком: ссылка и строка группы блокируются,
  -- поэтому отзыв не может вклиниться до insert membership.
  select g.id
    into v_group_id
  from public.group_invite_links l
  join public.groups g on g.id = l.group_id
  where l.token = p_invite_token
    and l.revoked_at is null
    and (l.expires_at is null or l.expires_at > now())
    and g.ended_at is null
    and (g.ends_at is null or g.ends_at > now())
  for update of l, g;

  if v_group_id is null then
    raise exception 'Приглашение недоступно';
  end if;

  if exists (
    select 1
    from public.memberships m
    where m.group_id = v_group_id
      and m.user_id = v_user_id
  ) then
    update public.saved_group_invitations s
    set status = 'accepted',
        accepted_at = coalesce(s.accepted_at, now())
    where s.user_id = v_user_id
      and s.group_id = v_group_id
      and s.status = 'pending';
    return query select v_group_id, 'already_member'::text;
    return;
  end if;

  select p.display_name
    into v_display_name
  from public.profiles p
  where p.id = v_user_id;

  begin
    -- Те же столбцы, что у join_group_by_token. avatar_id, joined_at, left_at
    -- и updated_at закрывают ограничения и значения по умолчанию memberships.
    -- Существующая строка, в том числе left/removed, выше даёт already_member
    -- и membership не меняет. Ссылку эта вставка не отзывает.
    insert into public.memberships (group_id, user_id, role, status, display_name)
    values (
      v_group_id,
      v_user_id,
      'participant',
      'active',
      coalesce(v_display_name, 'Участник')
    );
  exception
    when unique_violation then
      update public.saved_group_invitations s
      set status = 'accepted',
          accepted_at = coalesce(s.accepted_at, now())
      where s.user_id = v_user_id
        and s.group_id = v_group_id
        and s.status = 'pending';
      return query select v_group_id, 'already_member'::text;
      return;
  end;

  update public.saved_group_invitations s
  set status = 'accepted',
      accepted_at = coalesce(s.accepted_at, now())
  where s.user_id = v_user_id
    and s.group_id = v_group_id
    and s.status = 'pending';

  return query select v_group_id, 'joined'::text;
end;
$$;

-- Хеш исходного токена. Сам токен в saved_group_invitations не пишется.
create or replace function public.group_invite_token_hash(p_invite_token text)
returns text
language sql
immutable
set search_path = public
as $$
  select encode(extensions.digest(convert_to(p_invite_token, 'UTF8'), 'sha256'), 'hex');
$$;

create or replace function public.save_group_invitation(p_invite_token text)
returns table (
  available boolean,
  saved_invitation_id uuid,
  invitation_id uuid,
  group_id uuid,
  group_name text,
  starts_at timestamptz,
  ends_at timestamptz,
  organizer_display_name text,
  is_pending boolean
)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  v_user_id uuid := auth.uid();
  v_group_id uuid;
  v_link_id uuid;
  v_hash text;
  v_has_membership boolean;
  v_status public.saved_group_invitation_status;
begin
  if v_user_id is null then
    raise exception 'Требуется авторизация';
  end if;
  if p_invite_token is null or p_invite_token !~ '^[0-9a-f]{64}$' then
    return query
    select false, null::uuid, null::uuid, null::uuid, null::text,
           null::timestamptz, null::timestamptz, null::text, false;
    return;
  end if;

  select l.group_id
    into v_group_id
  from public.group_invite_links l
  where l.token = p_invite_token;

  if v_group_id is null then
    return query
    select false, null::uuid, null::uuid, null::uuid, null::text,
           null::timestamptz, null::timestamptz, null::text, false;
    return;
  end if;

  perform pg_advisory_xact_lock(hashtext('group-invite:' || v_group_id::text));

  select l.id, g.id
    into v_link_id, v_group_id
  from public.group_invite_links l
  join public.groups g on g.id = l.group_id
  where l.token = p_invite_token
    and l.revoked_at is null
    and (l.expires_at is null or l.expires_at > now())
    and g.ended_at is null
    and (g.ends_at is null or g.ends_at > now())
  for update of g;

  if v_link_id is null then
    return query
    select false, null::uuid, null::uuid, null::uuid, null::text,
           null::timestamptz, null::timestamptz, null::text, false;
    return;
  end if;

  v_hash := public.group_invite_token_hash(p_invite_token);
  v_has_membership := exists (
    select 1
    from public.memberships m
    where m.group_id = v_group_id
      and m.user_id = v_user_id
  );
  v_status := case
    when v_has_membership
      then 'accepted'::public.saved_group_invitation_status
    else 'pending'::public.saved_group_invitation_status
  end;

  insert into public.saved_group_invitations (
    user_id,
    group_id,
    invite_link_id,
    token_hash,
    status,
    accepted_at
  )
  values (
    v_user_id,
    v_group_id,
    v_link_id,
    v_hash,
    v_status,
    case when v_has_membership then now() else null end
  )
  on conflict (user_id, group_id) do update
  set invite_link_id = excluded.invite_link_id,
      token_hash = excluded.token_hash,
      status = case
        when public.saved_group_invitations.token_hash = excluded.token_hash
          then public.saved_group_invitations.status
        else excluded.status
      end,
      accepted_at = case
        when public.saved_group_invitations.token_hash = excluded.token_hash
          then public.saved_group_invitations.accepted_at
        else excluded.accepted_at
      end,
      seen_at = case
        when public.saved_group_invitations.token_hash = excluded.token_hash
          then public.saved_group_invitations.seen_at
        else null
      end;

  if v_has_membership then
    update public.saved_group_invitations t
    set status = 'accepted',
        accepted_at = coalesce(t.accepted_at, now())
    where t.user_id = v_user_id
      and t.group_id = v_group_id
      and t.status = 'pending';
  end if;

  return query
  select
    true,
    s.id,
    l.id,
    g.id,
    g.name,
    g.starts_at,
    g.ends_at,
    org.display_name,
    s.status = 'pending'
  from public.saved_group_invitations s
  join public.group_invite_links l on l.id = s.invite_link_id
  join public.groups g on g.id = s.group_id
  join lateral (
    select m.display_name
    from public.memberships m
    where m.group_id = g.id
      and m.role = 'organizer'
      and m.status = 'active'
    limit 1
  ) org on true
  where s.user_id = v_user_id
    and s.group_id = v_group_id;
end;
$$;

create or replace function public.list_saved_group_invitations()
returns table (
  saved_invitation_id uuid,
  invitation_id uuid,
  group_id uuid,
  group_name text,
  starts_at timestamptz,
  ends_at timestamptz,
  organizer_display_name text,
  is_unseen boolean,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    s.id,
    l.id,
    g.id,
    g.name,
    g.starts_at,
    g.ends_at,
    org.display_name,
    s.seen_at is null,
    s.created_at
  from public.saved_group_invitations s
  join public.group_invite_links l on l.id = s.invite_link_id
  join public.groups g on g.id = s.group_id
  join lateral (
    select m.display_name
    from public.memberships m
    where m.group_id = g.id
      and m.role = 'organizer'
      and m.status = 'active'
    limit 1
  ) org on true
  where s.user_id = auth.uid()
    and s.status = 'pending'
    and s.token_hash = public.group_invite_token_hash(l.token)
    and l.revoked_at is null
    and (l.expires_at is null or l.expires_at > now())
    and g.ended_at is null
    and (g.ends_at is null or g.ends_at > now())
  order by s.created_at desc;
$$;

create or replace function public.count_unseen_saved_group_invitations()
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::integer
  from public.list_saved_group_invitations() item
  where item.is_unseen;
$$;

create or replace function public.mark_saved_group_invitations_seen()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_updated integer;
begin
  if auth.uid() is null then
    raise exception 'Требуется авторизация';
  end if;

  update public.saved_group_invitations s
  set seen_at = now()
  where s.user_id = auth.uid()
    and s.status = 'pending'
    and s.seen_at is null
    and s.id in (
      select item.saved_invitation_id
      from public.list_saved_group_invitations() item
    );

  get diagnostics v_updated = row_count;
  return v_updated;
end;
$$;

revoke all privileges on table public.group_invite_links from anon, authenticated;
revoke all privileges on table public.saved_group_invitations from anon, authenticated;

revoke all privileges on function public.group_invite_token_hash(text)
  from public, anon, authenticated;
revoke all privileges on function public.create_or_get_group_invitation(uuid)
  from public, anon, authenticated;
revoke all privileges on function public.revoke_group_invitation(uuid)
  from public, anon, authenticated;
revoke all privileges on function public.resolve_group_invitation(text)
  from public, anon, authenticated;
revoke all privileges on function public.accept_group_invitation(text)
  from public, anon, authenticated;
revoke all privileges on function public.save_group_invitation(text)
  from public, anon, authenticated;
revoke all privileges on function public.list_saved_group_invitations()
  from public, anon, authenticated;
revoke all privileges on function public.count_unseen_saved_group_invitations()
  from public, anon, authenticated;
revoke all privileges on function public.mark_saved_group_invitations_seen()
  from public, anon, authenticated;

grant execute on function public.create_or_get_group_invitation(uuid) to authenticated;
grant execute on function public.revoke_group_invitation(uuid) to authenticated;
grant execute on function public.resolve_group_invitation(text) to anon, authenticated;
grant execute on function public.accept_group_invitation(text) to authenticated;
grant execute on function public.save_group_invitation(text) to authenticated;
grant execute on function public.list_saved_group_invitations() to authenticated;
grant execute on function public.count_unseen_saved_group_invitations() to authenticated;
grant execute on function public.mark_saved_group_invitations_seen() to authenticated;
