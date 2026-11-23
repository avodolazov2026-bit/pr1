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

revoke all privileges on function public.save_group_invitation(text)
  from public, anon, authenticated;
grant execute on function public.save_group_invitation(text) to authenticated;
