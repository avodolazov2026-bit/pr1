-- Geo Groups — baseline of the confirmed public schema.
-- Source: catalog inventory of geo-groups-dev on 2026-11-20.
--
-- REVIEW ONLY. Do not apply to an existing database and do not run db push/reset
-- until the migration chain is approved.
-- Managed Supabase extensions not used by the app (pg_stat_statements,
-- supabase_vault) are intentionally not recreated here.

create extension if not exists pgcrypto with schema extensions;
create extension if not exists "uuid-ossp" with schema extensions;

create type public.group_role as enum ('organizer', 'participant');
create type public.membership_status as enum ('active', 'invited', 'left', 'removed');
create type public.invitation_status as enum ('pending', 'accepted', 'declined', 'revoked', 'expired');

create table public.groups (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  creator_id uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  ended_at timestamptz,
  ended_by_user_id uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  constraint groups_ended_after_start check (ended_at is null or ended_at >= starts_at),
  constraint groups_ends_after_start check (ends_at is null or ends_at > starts_at),
  constraint groups_name_not_blank check (
    char_length(btrim(name)) >= 1 and char_length(btrim(name)) <= 120
  )
);

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  avatar_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_display_name_not_blank check (
    char_length(btrim(display_name)) >= 1 and char_length(btrim(display_name)) <= 80
  )
);

create table public.memberships (
  group_id uuid not null references public.groups(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role public.group_role not null default 'participant',
  status public.membership_status not null default 'active',
  display_name text not null,
  avatar_id text,
  joined_at timestamptz not null default now(),
  left_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (group_id, user_id),
  constraint memberships_display_name_not_blank check (
    char_length(btrim(display_name)) >= 1 and char_length(btrim(display_name)) <= 80
  ),
  constraint memberships_left_at_for_left_status check (
    (status = 'left' and left_at is not null)
    or (status <> 'left' and left_at is null)
  ),
  constraint memberships_organizer_is_active check (
    role <> 'organizer' or status = 'active'
  )
);

create table public.group_invite_links (
  group_id uuid primary key references public.groups(id) on delete cascade,
  token text not null unique default encode(gen_random_bytes(32), 'hex'),
  created_by_user_id uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  expires_at timestamptz,
  revoked_at timestamptz,
  updated_at timestamptz not null default now(),
  constraint group_invite_links_expires_after_create check (
    expires_at is null or expires_at > created_at
  )
);

create table public.invitations (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups(id) on delete cascade,
  recipient_user_id uuid not null references auth.users(id) on delete cascade,
  invited_by_user_id uuid not null references auth.users(id) on delete restrict,
  status public.invitation_status not null default 'pending',
  created_at timestamptz not null default now(),
  expires_at timestamptz,
  responded_at timestamptz,
  updated_at timestamptz not null default now(),
  constraint invitations_expires_after_create check (
    expires_at is null or expires_at > created_at
  ),
  constraint invitations_no_self_invite check (
    recipient_user_id <> invited_by_user_id
  ),
  constraint invitations_response_matches_status check (
    ((status in ('accepted', 'declined')) and responded_at is not null)
    or ((status not in ('accepted', 'declined')) and responded_at is null)
  )
);

create table public.locations (
  group_id uuid not null,
  user_id uuid not null,
  latitude double precision not null,
  longitude double precision not null,
  updated_at timestamptz not null default now(),
  primary key (group_id, user_id),
  constraint locations_group_id_user_id_fkey
    foreign key (group_id, user_id)
    references public.memberships(group_id, user_id) on delete cascade,
  constraint locations_latitude_range check (latitude >= -90 and latitude <= 90),
  constraint locations_longitude_range check (longitude >= -180 and longitude <= 180)
);

create index groups_active_window_idx
  on public.groups (starts_at, ends_at) where ended_at is null;
create index groups_creator_idx on public.groups (creator_id, created_at desc);
create index invitations_group_status_idx on public.invitations (group_id, status);
create unique index invitations_one_open_per_recipient
  on public.invitations (group_id, recipient_user_id) where status = 'pending';
create index invitations_recipient_status_idx
  on public.invitations (recipient_user_id, status, created_at desc);
create index locations_updated_at_idx on public.locations (updated_at);
create index memberships_group_status_idx on public.memberships (group_id, status);
create unique index memberships_one_organizer_per_group
  on public.memberships (group_id) where role = 'organizer';
create index memberships_user_status_idx on public.memberships (user_id, status);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  fallback_name text;
begin
  fallback_name := coalesce(
    nullif(btrim(new.raw_user_meta_data ->> 'full_name'), ''),
    nullif(btrim(new.raw_user_meta_data ->> 'name'), ''),
    nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
    'Участник'
  );

  insert into public.profiles (id, display_name)
  values (new.id, left(fallback_name, 80))
  on conflict (id) do nothing;

  return new;
end;
$$;

create or replace function public.is_group_open(p_group_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.groups g
    where g.id = p_group_id
      and g.ended_at is null
      and g.starts_at <= now()
      and (g.ends_at is null or g.ends_at > now())
  );
$$;

create or replace function public.is_active_member(p_group_id uuid, p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_group_open(p_group_id)
     and exists (
       select 1
       from public.memberships m
       where m.group_id = p_group_id
         and m.user_id = p_user_id
         and m.status = 'active'
     );
$$;

create or replace function public.is_active_organizer(p_group_id uuid, p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_active_member(p_group_id, p_user_id)
     and exists (
       select 1
       from public.memberships m
       where m.group_id = p_group_id
         and m.user_id = p_user_id
         and m.role = 'organizer'
     );
$$;

create or replace function public.create_group(
  p_name text,
  p_starts_at timestamptz default now(),
  p_ends_at timestamptz default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
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
  if p_starts_at is null or (p_ends_at is not null and p_ends_at <= p_starts_at) then
    raise exception 'Время окончания должно быть позже времени начала';
  end if;

  select display_name into v_display_name
  from public.profiles where id = v_user_id;

  insert into public.groups (name, creator_id, starts_at, ends_at)
  values (btrim(p_name), v_user_id, p_starts_at, p_ends_at)
  returning id into v_group_id;

  insert into public.memberships (group_id, user_id, role, status, display_name)
  values (v_group_id, v_user_id, 'organizer', 'active', coalesce(v_display_name, 'Участник'));

  insert into public.group_invite_links (group_id, created_by_user_id)
  values (v_group_id, v_user_id);

  return v_group_id;
end;
$$;

create or replace function public.join_group_by_token(p_token text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_group_id uuid;
  v_display_name text;
  v_existing_role public.group_role;
begin
  if v_user_id is null then
    raise exception 'Требуется авторизация';
  end if;

  select l.group_id into v_group_id
  from public.group_invite_links l
  join public.groups g on g.id = l.group_id
  where l.token = p_token
    and l.revoked_at is null
    and (l.expires_at is null or l.expires_at > now())
    and g.ended_at is null
    and (g.ends_at is null or g.ends_at > now());

  if v_group_id is null then
    raise exception 'Приглашение недействительно, отозвано или срок группы истёк';
  end if;

  select role into v_existing_role
  from public.memberships
  where group_id = v_group_id and user_id = v_user_id;

  if v_existing_role is not null then
    return v_group_id;
  end if;

  select display_name into v_display_name
  from public.profiles where id = v_user_id;

  insert into public.memberships (group_id, user_id, role, status, display_name)
  values (v_group_id, v_user_id, 'participant', 'active', coalesce(v_display_name, 'Участник'));

  return v_group_id;
end;
$$;

create trigger groups_set_updated_at
before update on public.groups
for each row execute function public.set_updated_at();

create trigger memberships_set_updated_at
before update on public.memberships
for each row execute function public.set_updated_at();

create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

create trigger group_invite_links_set_updated_at
before update on public.group_invite_links
for each row execute function public.set_updated_at();

create trigger invitations_set_updated_at
before update on public.invitations
for each row execute function public.set_updated_at();

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

alter table public.groups enable row level security;
alter table public.memberships enable row level security;
alter table public.profiles enable row level security;
alter table public.group_invite_links enable row level security;
alter table public.invitations enable row level security;
alter table public.locations enable row level security;

create policy "groups: creator or member reads"
on public.groups for select to authenticated
using (
  creator_id = auth.uid()
  or exists (
    select 1 from public.memberships m
    where m.group_id = groups.id and m.user_id = auth.uid()
  )
);

create policy "memberships: allowed reads"
on public.memberships for select to authenticated
using (
  user_id = auth.uid()
  or (status = 'active' and public.is_active_member(group_id, auth.uid()))
);

create policy "profiles: user reads own"
on public.profiles for select to authenticated
using (id = auth.uid());

create policy "profiles: user updates own"
on public.profiles for update to authenticated
using (id = auth.uid())
with check (id = auth.uid());

create policy "invitations: recipient or organizer reads"
on public.invitations for select to authenticated
using (
  recipient_user_id = auth.uid()
  or public.is_active_organizer(group_id, auth.uid())
);

create policy "locations: active members read fresh locations"
on public.locations for select to authenticated
using (
  updated_at >= now() - interval '10 minutes'
  and public.is_active_member(group_id, auth.uid())
);

create policy "locations: member inserts own location"
on public.locations for insert to authenticated
with check (user_id = auth.uid() and public.is_active_member(group_id, auth.uid()));

create policy "locations: member updates own location"
on public.locations for update to authenticated
using (user_id = auth.uid() and public.is_active_member(group_id, auth.uid()))
with check (user_id = auth.uid() and public.is_active_member(group_id, auth.uid()));

create policy "locations: member deletes own location"
on public.locations for delete to authenticated
using (user_id = auth.uid() and public.is_active_member(group_id, auth.uid()));

-- There are deliberately no policies on group_invite_links.
-- Client access to its tokens is available only through join_group_by_token(...).

-- Existing client RPC surface; the following migration hardens all final grants.
grant execute on function public.create_group(text, timestamptz, timestamptz) to authenticated;
grant execute on function public.join_group_by_token(text) to authenticated;
