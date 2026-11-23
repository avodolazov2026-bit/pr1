-- Вступление по сохранённой ссылке. Токен клиенту не передаётся.
create or replace function public.accept_saved_group_invitation(
  p_saved_invitation_id uuid
)
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
  v_status public.saved_group_invitation_status;
begin
  if v_user_id is null then
    raise exception 'Требуется авторизация';
  end if;
  if p_saved_invitation_id is null then
    raise exception 'Приглашение недоступно';
  end if;

  select s.group_id
    into v_group_id
  from public.saved_group_invitations s
  where s.id = p_saved_invitation_id
    and s.user_id = v_user_id;

  if not found then
    raise exception 'Приглашение недоступно';
  end if;

  -- Тот же ключ, что у create_or_get, revoke, accept и save.
  perform pg_advisory_xact_lock(hashtext('group-invite:' || v_group_id::text));

  select g.id
    into v_group_id
  from public.saved_group_invitations s
  join public.group_invite_links l on l.id = s.invite_link_id
  join public.groups g on g.id = s.group_id
  where s.id = p_saved_invitation_id
    and s.user_id = v_user_id
    and l.revoked_at is null
    and (l.expires_at is null or l.expires_at > now())
    and g.ended_at is null
    and (g.ends_at is null or g.ends_at > now())
  for update of l, g;

  if not found then
    raise exception 'Приглашение недоступно';
  end if;

  v_status := 'accepted'::public.saved_group_invitation_status;

  if exists (
    select 1
    from public.memberships m
    where m.group_id = v_group_id
      and m.user_id = v_user_id
  ) then
    update public.saved_group_invitations s
    set status = v_status,
        accepted_at = coalesce(s.accepted_at, now())
    where s.id = p_saved_invitation_id
      and s.user_id = v_user_id;
    return query select v_group_id, 'already_member'::text;
    return;
  end if;

  select p.display_name
    into v_display_name
  from public.profiles p
  where p.id = v_user_id;

  begin
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
      set status = v_status,
          accepted_at = coalesce(s.accepted_at, now())
      where s.id = p_saved_invitation_id
        and s.user_id = v_user_id;
      return query select v_group_id, 'already_member'::text;
      return;
  end;

  update public.saved_group_invitations s
  set status = v_status,
      accepted_at = coalesce(s.accepted_at, now())
  where s.id = p_saved_invitation_id
    and s.user_id = v_user_id;

  return query select v_group_id, 'joined'::text;
end;
$$;

revoke all privileges on function public.accept_saved_group_invitation(uuid)
  from public, anon, authenticated;
grant execute on function public.accept_saved_group_invitation(uuid)
  to authenticated;
