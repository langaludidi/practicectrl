
create or replace function public.get_possible_pmb_relationships_batch(
  p_icd10_codes text[],
  p_source_release_id uuid default null
)
returns table(
  id uuid,
  source_release_id uuid,
  icd10_code text,
  pmb_category text,
  dtp_number text,
  cdl_condition text,
  pmb_descriptor text,
  qualification_notes text,
  treatment_context text
)
language sql
stable
security invoker
set search_path=public,pg_temp
as $$
with selected_release as (
  select coalesce(
    p_source_release_id,
    (
      select csr.id
      from public.coding_source_release csr
      where csr.authority='CMS'
        and csr.status='active'
      order by csr.published_date desc nulls last, csr.created_at desc
      limit 1
    )
  ) as release_id
),
wanted as (
  select distinct upper(regexp_replace(trim(x), '[^A-Za-z0-9*]+', '', 'g')) as normalized_code
  from unnest(coalesce(p_icd10_codes,'{}'::text[])) x
  where trim(x)<>''
)
select p.id,p.source_release_id,p.icd10_code,p.pmb_category,p.dtp_number,
       p.cdl_condition,p.pmb_descriptor,p.qualification_notes,p.treatment_context
from public.pmb_mapping p
cross join selected_release sr
join wanted w on w.normalized_code=p.normalized_code
where p.source_release_id=sr.release_id
order by p.normalized_code,p.pmb_category nulls last,p.dtp_number nulls last,p.cdl_condition nulls last;
$$;

revoke all on function public.get_possible_pmb_relationships_batch(text[],uuid) from public,anon;
grant execute on function public.get_possible_pmb_relationships_batch(text[],uuid) to authenticated;

