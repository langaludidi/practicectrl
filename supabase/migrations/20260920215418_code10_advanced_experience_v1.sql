
begin;

create table if not exists public.code10_clinical_knowledge (
  id uuid primary key default gen_random_uuid(),
  code_id uuid not null references public.sa_icd10_code(id) on delete cascade,
  plain_language_summary text,
  documentation_prompts text[] not null default '{}',
  common_terms text[] not null default '{}',
  body_system text,
  clinical_notes text,
  source_references jsonb not null default '[]'::jsonb,
  review_status text not null default 'draft'
    check (review_status in ('draft','approved','retired')),
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(code_id)
);

create index if not exists code10_knowledge_status_idx
  on public.code10_clinical_knowledge(review_status,code_id);
create index if not exists code10_knowledge_reviewed_by_idx
  on public.code10_clinical_knowledge(reviewed_by)
  where reviewed_by is not null;

alter table public.code10_clinical_knowledge enable row level security;
revoke all on table public.code10_clinical_knowledge from anon,authenticated;
grant select on table public.code10_clinical_knowledge to authenticated;

drop policy if exists code10_knowledge_staff_read on public.code10_clinical_knowledge;
create policy code10_knowledge_staff_read
on public.code10_clinical_knowledge for select to authenticated
using (
  review_status='approved'
  and exists (
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.active
  )
);

create table if not exists public.code10_bookmark (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null references public.practice(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  code_id uuid not null references public.sa_icd10_code(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique(practice_id,user_id,code_id)
);
create index if not exists code10_bookmark_user_idx
  on public.code10_bookmark(user_id,created_at desc);
create index if not exists code10_bookmark_code_idx
  on public.code10_bookmark(code_id);

alter table public.code10_bookmark enable row level security;
revoke all on table public.code10_bookmark from anon,authenticated;
grant select,insert,delete on table public.code10_bookmark to authenticated;

drop policy if exists code10_bookmark_own_read on public.code10_bookmark;
create policy code10_bookmark_own_read
on public.code10_bookmark for select to authenticated
using (
  user_id=(select auth.uid())
  and exists (
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=code10_bookmark.practice_id
      and m.active
  )
);

drop policy if exists code10_bookmark_own_insert on public.code10_bookmark;
create policy code10_bookmark_own_insert
on public.code10_bookmark for insert to authenticated
with check (
  ((select auth.jwt())->>'aal')='aal2'
  and user_id=(select auth.uid())
  and exists (
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=code10_bookmark.practice_id
      and m.active
  )
);

drop policy if exists code10_bookmark_own_delete on public.code10_bookmark;
create policy code10_bookmark_own_delete
on public.code10_bookmark for delete to authenticated
using (
  ((select auth.jwt())->>'aal')='aal2'
  and user_id=(select auth.uid())
  and exists (
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=code10_bookmark.practice_id
      and m.active
  )
);

create table if not exists public.code10_search_event (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null references public.practice(id) on delete cascade,
  actor_user_id uuid not null references auth.users(id) on delete cascade,
  coding_session_id uuid references public.coding_session(id) on delete set null,
  query_sha256 text not null check (query_sha256 ~ '^[a-f0-9]{64}$'),
  query_length integer not null check (query_length between 2 and 4000),
  query_mode text not null
    check (query_mode in ('code','term','narrative','voice')),
  results_count integer not null default 0 check (results_count >= 0),
  latency_ms integer check (latency_ms is null or latency_ms >= 0),
  created_at timestamptz not null default now()
);
create index if not exists code10_search_event_practice_idx
  on public.code10_search_event(practice_id,created_at desc);
create index if not exists code10_search_event_actor_idx
  on public.code10_search_event(actor_user_id,created_at desc);
create index if not exists code10_search_event_session_idx
  on public.code10_search_event(coding_session_id)
  where coding_session_id is not null;

alter table public.code10_search_event enable row level security;
revoke all on table public.code10_search_event from anon,authenticated;
grant select,insert on table public.code10_search_event to authenticated;

drop policy if exists code10_search_event_own_insert on public.code10_search_event;
create policy code10_search_event_own_insert
on public.code10_search_event for insert to authenticated
with check (
  ((select auth.jwt())->>'aal')='aal2'
  and actor_user_id=(select auth.uid())
  and exists (
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=code10_search_event.practice_id
      and m.active
  )
);

drop policy if exists code10_search_event_privileged_read on public.code10_search_event;
create policy code10_search_event_privileged_read
on public.code10_search_event for select to authenticated
using (
  actor_user_id=(select auth.uid())
  or exists (
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=code10_search_event.practice_id
      and m.active
      and m.role in ('practice_manager','system_admin','auditor')
  )
);

create or replace function public.search_code10_v2(
  p_query text,
  p_source_release_id uuid default null,
  p_limit integer default 20
)
returns table(
  id uuid,
  code text,
  official_description text,
  chapter_no text,
  chapter_desc text,
  group_code text,
  group_desc text,
  icd10_3_code text,
  icd10_3_code_desc text,
  official_comment text,
  sa_status text,
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
  matched_text text,
  relevance double precision
)
language sql
stable
security invoker
set search_path=public,extensions,pg_temp
as $$
with q as (
  select
    trim(p_query) as raw,
    upper(regexp_replace(trim(p_query), '[^A-Za-z0-9*]+', '', 'g')) as code_q,
    lower(trim(p_query)) as text_q
),
selected_release as (
  select coalesce(
    p_source_release_id,
    (
      select csr.id
      from public.coding_source_release csr
      where csr.authority='NDOH'
        and csr.source_name='ICD-10 Master Industry Table'
        and csr.status='active'
      order by csr.effective_from desc nulls last, csr.created_at desc
      limit 1
    )
  ) as release_id
),
scored as (
  select
    c.*,
    a.alias as best_alias,
    case
      when c.normalized_code=q.code_q then 'exact_code'
      when length(q.code_q)>=2 and c.normalized_code like q.code_q || '%' then 'code_prefix'
      when lower(c.official_description)=q.text_q then 'exact_description'
      when lower(coalesce(a.alias,''))=q.text_q then 'exact_alias'
      when to_tsvector('simple',coalesce(c.official_description,'')) @@ websearch_to_tsquery('simple',q.raw) then 'description_text'
      when to_tsvector('simple',coalesce(c.icd10_3_code_desc,'')) @@ websearch_to_tsquery('simple',q.raw) then 'family_text'
      when to_tsvector('simple',coalesce(c.group_desc,'')) @@ websearch_to_tsquery('simple',q.raw) then 'group_text'
      when to_tsvector('simple',coalesce(c.chapter_desc,'')) @@ websearch_to_tsquery('simple',q.raw) then 'chapter_text'
      when extensions.similarity(lower(c.official_description),q.text_q)>=0.25 then 'fuzzy_description'
      when extensions.similarity(lower(coalesce(a.alias,'')),q.text_q)>=0.30 then 'fuzzy_alias'
      else null
    end as match_reason,
    case
      when c.normalized_code=q.code_q then c.code
      when length(q.code_q)>=2 and c.normalized_code like q.code_q || '%' then c.code
      when lower(c.official_description)=q.text_q then c.official_description
      when lower(coalesce(a.alias,''))=q.text_q then a.alias
      when to_tsvector('simple',coalesce(c.official_description,'')) @@ websearch_to_tsquery('simple',q.raw) then c.official_description
      when to_tsvector('simple',coalesce(c.icd10_3_code_desc,'')) @@ websearch_to_tsquery('simple',q.raw) then c.icd10_3_code_desc
      when to_tsvector('simple',coalesce(c.group_desc,'')) @@ websearch_to_tsquery('simple',q.raw) then c.group_desc
      when to_tsvector('simple',coalesce(c.chapter_desc,'')) @@ websearch_to_tsquery('simple',q.raw) then c.chapter_desc
      when extensions.similarity(lower(c.official_description),q.text_q)>=0.25 then c.official_description
      when extensions.similarity(lower(coalesce(a.alias,'')),q.text_q)>=0.30 then a.alias
      else null
    end as matched_text,
    greatest(
      case when c.normalized_code=q.code_q then 1.00 else 0 end,
      case when length(q.code_q)>=2 and c.normalized_code like q.code_q || '%' then 0.94 else 0 end,
      case when lower(c.official_description)=q.text_q then 0.98 else 0 end,
      case when lower(coalesce(a.alias,''))=q.text_q then 0.96 else 0 end,
      case when to_tsvector('simple',coalesce(c.official_description,'')) @@ websearch_to_tsquery('simple',q.raw)
        then 0.82 + least(ts_rank_cd(to_tsvector('simple',c.official_description),websearch_to_tsquery('simple',q.raw))::double precision,0.12)
        else 0 end,
      case when to_tsvector('simple',coalesce(c.icd10_3_code_desc,'')) @@ websearch_to_tsquery('simple',q.raw) then 0.75 else 0 end,
      case when to_tsvector('simple',coalesce(c.group_desc,'')) @@ websearch_to_tsquery('simple',q.raw) then 0.70 else 0 end,
      case when to_tsvector('simple',coalesce(c.chapter_desc,'')) @@ websearch_to_tsquery('simple',q.raw) then 0.62 else 0 end,
      extensions.similarity(lower(c.official_description),q.text_q)::double precision * 0.78,
      extensions.similarity(lower(coalesce(a.alias,'')),q.text_q)::double precision * 0.80
    ) as relevance
  from public.sa_icd10_code c
  cross join q
  cross join selected_release sr
  left join lateral (
    select ia.alias
    from public.icd10_search_alias ia
    where ia.icd10_code_id=c.id
      and ia.review_status='approved'
    order by
      (lower(ia.alias)=q.text_q) desc,
      extensions.similarity(lower(ia.alias),q.text_q) desc,
      ia.alias
    limit 1
  ) a on true
  where c.source_release_id=sr.release_id
    and (
      c.normalized_code=q.code_q
      or (length(q.code_q)>=2 and c.normalized_code like q.code_q || '%')
      or lower(c.official_description)=q.text_q
      or lower(coalesce(a.alias,''))=q.text_q
      or to_tsvector('simple',coalesce(c.official_description,'')) @@ websearch_to_tsquery('simple',q.raw)
      or to_tsvector('simple',coalesce(c.icd10_3_code_desc,'')) @@ websearch_to_tsquery('simple',q.raw)
      or to_tsvector('simple',coalesce(c.group_desc,'')) @@ websearch_to_tsquery('simple',q.raw)
      or to_tsvector('simple',coalesce(c.chapter_desc,'')) @@ websearch_to_tsquery('simple',q.raw)
      or extensions.similarity(lower(c.official_description),q.text_q)>=0.25
      or extensions.similarity(lower(coalesce(a.alias,'')),q.text_q)>=0.30
    )
)
select
  s.id,s.code,s.official_description,s.chapter_no,s.chapter_desc,
  s.group_code,s.group_desc,s.icd10_3_code,s.icd10_3_code_desc,
  s.official_comment,s.sa_status,s.valid_clinical_use,s.valid_primary,
  s.valid_asterisk,s.valid_dagger,s.valid_sequelae,s.age_range,s.gender,
  s.source_release_id,s.sa_start_date,s.sa_end_date,
  s.match_reason,s.matched_text,s.relevance
from scored s
where s.match_reason is not null
order by
  s.relevance desc,
  s.valid_clinical_use desc,
  s.valid_primary desc,
  s.code
limit greatest(1,least(coalesce(p_limit,20),50));
$$;

revoke all on function public.search_code10_v2(text,uuid,integer) from public,anon;
grant execute on function public.search_code10_v2(text,uuid,integer) to authenticated;

create or replace function public.get_code10_context(p_code_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path=public,pg_temp
as $$
select jsonb_build_object(
  'code',jsonb_build_object(
    'id',c.id,
    'code',c.code,
    'official_description',c.official_description,
    'chapter_no',c.chapter_no,
    'chapter_desc',c.chapter_desc,
    'group_code',c.group_code,
    'group_desc',c.group_desc,
    'icd10_3_code',c.icd10_3_code,
    'icd10_3_code_desc',c.icd10_3_code_desc,
    'official_comment',c.official_comment,
    'sa_status',c.sa_status,
    'age_range',c.age_range,
    'gender',c.gender,
    'sa_start_date',c.sa_start_date,
    'sa_end_date',c.sa_end_date
  ),
  'knowledge',(
    select case when k.id is null then null else jsonb_build_object(
      'plain_language_summary',k.plain_language_summary,
      'documentation_prompts',k.documentation_prompts,
      'common_terms',k.common_terms,
      'body_system',k.body_system,
      'clinical_notes',k.clinical_notes,
      'source_references',k.source_references,
      'reviewed_at',k.reviewed_at
    ) end
    from public.code10_clinical_knowledge k
    where k.code_id=c.id and k.review_status='approved'
    limit 1
  ),
  'siblings',coalesce((
    select jsonb_agg(x order by x->>'code')
    from (
      select jsonb_build_object(
        'id',s.id,
        'code',s.code,
        'official_description',s.official_description,
        'valid_clinical_use',s.valid_clinical_use,
        'valid_primary',s.valid_primary
      ) as x
      from public.sa_icd10_code s
      where s.source_release_id=c.source_release_id
        and s.group_code=c.group_code
        and s.id<>c.id
      order by s.code
      limit 12
    ) q
  ),'[]'::jsonb)
)
from public.sa_icd10_code c
where c.id=p_code_id;
$$;

revoke all on function public.get_code10_context(uuid) from public,anon;
grant execute on function public.get_code10_context(uuid) to authenticated;

commit;
