do $$
begin
  if not exists (
    select 1
    from pg_publication_rel publication_relation
    join pg_publication publication
      on publication.oid = publication_relation.prpubid
    where publication.pubname = 'supabase_realtime'
      and publication_relation.prrelid = 'public.locations'::regclass
  ) then
    alter publication supabase_realtime add table public.locations;
  end if;
end;
$$;
