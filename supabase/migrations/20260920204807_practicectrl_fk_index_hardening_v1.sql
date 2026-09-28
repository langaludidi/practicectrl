
do $$
declare
  r record;
  idx_name text;
begin
  for r in
    with fk as (
      select con.oid as con_oid, con.conrelid, con.conname,
             n.nspname as schema_name, c.relname as table_name,
             con.conkey
      from pg_constraint con
      join pg_class c on c.oid=con.conrelid
      join pg_namespace n on n.oid=c.relnamespace
      where con.contype='f' and n.nspname='public'
    )
    select fk.*,
           string_agg(format('%I',a.attname), ', ' order by k.ord) as column_list
    from fk
    cross join lateral unnest(fk.conkey) with ordinality as k(attnum,ord)
    join pg_attribute a on a.attrelid=fk.conrelid and a.attnum=k.attnum
    where not exists (
      select 1
      from pg_index i
      where i.indrelid=fk.conrelid
        and i.indisvalid
        and fk.conkey <@ (string_to_array(trim(i.indkey::text),' ')::smallint[])
    )
    group by fk.con_oid,fk.conrelid,fk.conname,fk.schema_name,fk.table_name,fk.conkey
  loop
    idx_name := left('fkidx_' || r.conname, 63);
    execute format(
      'create index if not exists %I on %I.%I (%s)',
      idx_name, r.schema_name, r.table_name, r.column_list
    );
  end loop;
end $$;
