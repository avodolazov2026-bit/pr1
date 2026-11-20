-- Geo Groups — final least-privilege grants for the confirmed public schema.
--
-- Apply this migration to the existing remote project only after it has been
-- reviewed. It is idempotent for grants/revokes, but it intentionally changes
-- client access rights.

-- Remove the unsafe and unnecessary table privileges discovered in the audit.
revoke all privileges on table public.groups from anon, authenticated;
revoke all privileges on table public.memberships from anon, authenticated;
revoke all privileges on table public.profiles from anon, authenticated;
revoke all privileges on table public.group_invite_links from anon, authenticated;
revoke all privileges on table public.invitations from anon, authenticated;
revoke all privileges on table public.locations from anon, authenticated;

-- Do not leave SECURITY DEFINER helpers executable by PUBLIC or anon.
revoke all privileges on function public.create_group(text, timestamptz, timestamptz)
  from public, anon, authenticated;
revoke all privileges on function public.join_group_by_token(text)
  from public, anon, authenticated;
revoke all privileges on function public.handle_new_user()
  from public, anon, authenticated;
revoke all privileges on function public.is_group_open(uuid)
  from public, anon, authenticated;
revoke all privileges on function public.is_active_member(uuid, uuid)
  from public, anon, authenticated;
revoke all privileges on function public.is_active_organizer(uuid, uuid)
  from public, anon, authenticated;

-- RLS does not itself grant table access: grant only operations used by policies.
grant select on table public.groups to authenticated;
grant select on table public.memberships to authenticated;
grant select, update on table public.profiles to authenticated;
grant select on table public.invitations to authenticated;
grant select, insert, update, delete on table public.locations to authenticated;

-- Invite tokens remain inaccessible by direct table queries. Joining happens
-- only through the controlled SECURITY DEFINER RPC.

-- Public client RPC surface.
grant execute on function public.create_group(text, timestamptz, timestamptz)
  to authenticated;
grant execute on function public.join_group_by_token(text)
  to authenticated;

-- These helpers are called while RLS policies are evaluated.
grant execute on function public.is_group_open(uuid) to authenticated;
grant execute on function public.is_active_member(uuid, uuid) to authenticated;
grant execute on function public.is_active_organizer(uuid, uuid) to authenticated;
