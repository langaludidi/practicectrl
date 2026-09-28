
begin;

-- Explicitly deny all Data API access to server-only staging/ingestion tables.
drop policy if exists sa_icd10_import_staging_deny_client on public.sa_icd10_import_staging;
create policy sa_icd10_import_staging_deny_client
on public.sa_icd10_import_staging for all
to anon, authenticated
using (false) with check (false);

drop policy if exists pmb_import_staging_deny_client on public.pmb_import_staging;
create policy pmb_import_staging_deny_client
on public.pmb_import_staging for all
to anon, authenticated
using (false) with check (false);

drop policy if exists coding_ingestion_job_deny_client on public.coding_ingestion_job;
create policy coding_ingestion_job_deny_client
on public.coding_ingestion_job for all
to anon, authenticated
using (false) with check (false);

-- Keep extension objects outside the exposed public schema.
alter extension pg_trgm set schema extensions;

-- Recreate deterministic search with explicit extensions schema resolution.
create or replace function public.search_sa_icd10(
  p_query text,
  p_source_release_id uuid default null,
  p_limit integer default 20
)
returns table (
  id uuid,
  code text,
  official_description text,
  valid_clinical_use boolean,
  valid_primary boolean,
  valid_asterisk boolean,
  valid_dagger boolean,
  valid_sequelae boolean,
  age_range text,
  gender public.coding_gender_rule,
  source_release_id uuid,
  sa_start_date date,
  sa_end_date date,
  match_reason text,
  relevance double precision
)
language sql
stable
security invoker
set search_path = public, extensions, pg_temp
as $$
  with q as (
    select
      trim(p_query) as raw,
      upper(regexp_replace(trim(p_query), '[^A-Za-z0-9*]+', '', 'g')) as code_q,
      lower(trim(p_query)) as text_q
  ), selected_release as (
    select coalesce(
      p_source_release_id,
      (
        select csr.id
        from public.coding_source_release csr
        where csr.authority = 'NDOH'
          and csr.source_name = 'ICD-10 Master Industry Table'
          and csr.status = 'active'
        order by csr.effective_from desc nulls last, csr.created_at desc
        limit 1
      )
    ) as release_id
  ), candidates as (
    select
      c.*,
      case
        when c.normalized_code = q.code_q then 'exact_code'
        when c.normalized_code like q.code_q || '%' and length(q.code_q) >= 2 then 'code_prefix'
        when lower(c.official_description) = q.text_q then 'exact_description'
        when a.alias_normalized = q.text_q then 'exact_alias'
        when to_tsvector('simple', c.official_description) @@ plainto_tsquery('simple', q.raw) then 'full_text'
        when extensions.similarity(lower(c.official_description), q.text_q) >= 0.28 then 'fuzzy_description'
        when extensions.similarity(coalesce(a.alias_normalized,''), q.text_q) >= 0.32 then 'fuzzy_alias'
        else null
      end as match_reason,
      greatest(
        case when c.normalized_code = q.code_q then 1.0 else 0.0 end,
        case when c.normalized_code like q.code_q || '%' and length(q.code_q) >= 2 then 0.90 else 0.0 end,
        case when lower(c.official_description) = q.text_q then 0.95 else 0.0 end,
        case when a.alias_normalized = q.text_q then 0.92 else 0.0 end,
        extensions.similarity(lower(c.official_description), q.text_q),
        extensions.similarity(coalesce(a.alias_normalized,''), q.text_q)
      )::double precision as relevance
    from public.sa_icd10_code c
    cross join q
    cross join selected_release sr
    left join public.icd10_search_alias a
      on a.icd10_code_id = c.id and a.review_status = 'approved'
    where c.source_release_id = sr.release_id
      and (
        c.normalized_code = q.code_q
        or (length(q.code_q) >= 2 and c.normalized_code like q.code_q || '%')
        or lower(c.official_description) = q.text_q
        or a.alias_normalized = q.text_q
        or to_tsvector('simple', c.official_description) @@ plainto_tsquery('simple', q.raw)
        or extensions.similarity(lower(c.official_description), q.text_q) >= 0.28
        or extensions.similarity(coalesce(a.alias_normalized,''), q.text_q) >= 0.32
      )
  )
  select d.id,
         d.code,
         d.official_description,
         d.valid_clinical_use,
         d.valid_primary,
         d.valid_asterisk,
         d.valid_dagger,
         d.valid_sequelae,
         d.age_range,
         d.gender,
         d.source_release_id,
         d.sa_start_date,
         d.sa_end_date,
         d.match_reason,
         d.relevance
  from (
    select distinct on (c.id)
      c.id, c.code, c.official_description, c.valid_clinical_use, c.valid_primary,
      c.valid_asterisk, c.valid_dagger, c.valid_sequelae, c.age_range, c.gender,
      c.source_release_id, c.sa_start_date, c.sa_end_date, c.match_reason, c.relevance
    from candidates c
    where c.match_reason is not null
    order by c.id, c.relevance desc
  ) d
  order by d.relevance desc, d.valid_clinical_use desc, d.code
  limit greatest(1, least(coalesce(p_limit,20), 50));
$$;

revoke all on function public.search_sa_icd10(text, uuid, integer) from public, anon;
grant execute on function public.search_sa_icd10(text, uuid, integer) to authenticated;

-- Cover foreign keys used by integrity checks and cleanup paths.
create index if not exists coding_ai_actor_user_idx on public.coding_ai_interaction(actor_user_id);
create index if not exists coding_candidate_actor_user_idx on public.coding_candidate_snapshot(actor_user_id);
create index if not exists coding_candidate_code_idx on public.coding_candidate_snapshot(code_id);
create index if not exists coding_confidentiality_actor_user_idx on public.coding_confidentiality_event(actor_user_id);
create index if not exists coding_confidentiality_session_idx on public.coding_confidentiality_event(coding_session_id);
create index if not exists coding_decision_code_idx on public.coding_decision(code_id);
create index if not exists coding_decision_selected_by_idx on public.coding_decision(selected_by);
create index if not exists coding_ingestion_activated_by_idx on public.coding_ingestion_job(activated_by);
create index if not exists coding_ingestion_reviewed_by_idx on public.coding_ingestion_job(reviewed_by);
create index if not exists coding_ingestion_source_release_idx on public.coding_ingestion_job(source_release_id);
create index if not exists coding_session_actor_user_idx on public.coding_session(actor_user_id);
create index if not exists coding_session_cms_release_idx on public.coding_session(cms_release_id);
create index if not exists coding_session_mit_release_idx on public.coding_session(mit_release_id);
create index if not exists coding_session_phisc_release_idx on public.coding_session(phisc_release_id);
create index if not exists coding_source_activated_by_idx on public.coding_source_release(activated_by);
create index if not exists coding_source_imported_by_idx on public.coding_source_release(imported_by);
create index if not exists coding_validation_actor_user_idx on public.coding_validation_event(actor_user_id);
create index if not exists coding_validation_rule_idx on public.coding_validation_event(coding_rule_id);
create index if not exists coding_validation_resolved_by_idx on public.coding_validation_event(resolved_by);
create index if not exists icd10_alias_reviewed_by_idx on public.icd10_search_alias(reviewed_by);
create index if not exists pmb_review_coding_session_idx on public.pmb_review(coding_session_id);
create index if not exists pmb_review_icd10_code_idx on public.pmb_review(icd10_code_id);
create index if not exists pmb_review_mapping_idx on public.pmb_review(pmb_mapping_id);
create index if not exists pmb_review_reviewed_by_idx on public.pmb_review(reviewed_by);

commit;
