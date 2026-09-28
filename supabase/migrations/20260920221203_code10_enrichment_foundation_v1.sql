
begin;

create table if not exists public.code10_enrichment_source (
  id uuid primary key default gen_random_uuid(),
  source_key text not null unique,
  authority_name text not null,
  source_type text not null
    check (source_type in ('regulator','standards_body','clinical_reference','visual_library','internal_review')),
  title text not null,
  source_url text,
  version text,
  published_date date,
  licence_name text,
  licence_url text,
  commercial_use_allowed boolean,
  adaptation_allowed boolean,
  attribution_required boolean,
  attribution_template text,
  notes text,
  verified_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.code10_knowledge_reference (
  id uuid primary key default gen_random_uuid(),
  knowledge_id uuid not null references public.code10_clinical_knowledge(id) on delete cascade,
  source_id uuid not null references public.code10_enrichment_source(id) on delete restrict,
  component text not null
    check (component in ('summary','documentation_prompt','clinical_note','terminology','other')),
  source_locator text,
  evidence_note text,
  created_at timestamptz not null default now(),
  unique(knowledge_id,source_id,component,source_locator)
);
create index if not exists code10_knowledge_reference_source_idx
  on public.code10_knowledge_reference(source_id);

create table if not exists public.code10_code_relation (
  id uuid primary key default gen_random_uuid(),
  source_code_id uuid not null references public.sa_icd10_code(id) on delete cascade,
  target_code_id uuid not null references public.sa_icd10_code(id) on delete cascade,
  relation_type text not null
    check (relation_type in (
      'related','broader','narrower','commonly_confused',
      'etiology','manifestation','code_also','code_first',
      'external_cause','sequela','clinical_companion'
    )),
  authority_level text not null
    check (authority_level in ('official','standards_based','clinically_reviewed','editorial')),
  source_id uuid references public.code10_enrichment_source(id) on delete restrict,
  evidence_note text,
  review_status text not null default 'draft'
    check (review_status in ('draft','approved','retired')),
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint code10_relation_not_self_ck check (source_code_id <> target_code_id),
  unique(source_code_id,target_code_id,relation_type)
);
create index if not exists code10_relation_source_code_idx
  on public.code10_code_relation(source_code_id,review_status,relation_type);
create index if not exists code10_relation_target_code_idx
  on public.code10_code_relation(target_code_id,review_status,relation_type);
create index if not exists code10_relation_source_ref_idx
  on public.code10_code_relation(source_id)
  where source_id is not null;
create index if not exists code10_relation_reviewed_by_idx
  on public.code10_code_relation(reviewed_by)
  where reviewed_by is not null;

create table if not exists public.code10_visual_asset (
  id uuid primary key default gen_random_uuid(),
  source_id uuid not null references public.code10_enrichment_source(id) on delete restrict,
  external_asset_ref text,
  title text not null,
  source_page_url text not null,
  original_asset_url text,
  storage_bucket text,
  storage_object_path text,
  mime_type text,
  sha256 text,
  licence_name text not null,
  licence_url text not null,
  attribution_text text not null,
  adapted boolean not null default false,
  adaptation_note text,
  review_status text not null default 'draft'
    check (review_status in ('draft','approved','retired')),
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint code10_visual_hash_ck check (sha256 is null or sha256 ~ '^[a-f0-9]{64}$'),
  constraint code10_visual_storage_ck check (
    (storage_bucket is null and storage_object_path is null)
    or (storage_bucket is not null and storage_object_path is not null)
  ),
  unique(source_id,external_asset_ref)
);
create index if not exists code10_visual_asset_status_idx
  on public.code10_visual_asset(review_status,source_id);
create index if not exists code10_visual_asset_reviewed_by_idx
  on public.code10_visual_asset(reviewed_by)
  where reviewed_by is not null;

create table if not exists public.code10_visual_link (
  id uuid primary key default gen_random_uuid(),
  visual_asset_id uuid not null references public.code10_visual_asset(id) on delete cascade,
  code_id uuid not null references public.sa_icd10_code(id) on delete cascade,
  link_type text not null
    check (link_type in ('anatomy','pathology','mechanism','procedure_context','patient_education')),
  caption text,
  display_priority integer not null default 100 check (display_priority between 1 and 1000),
  created_at timestamptz not null default now(),
  unique(visual_asset_id,code_id,link_type)
);
create index if not exists code10_visual_link_code_idx
  on public.code10_visual_link(code_id,display_priority);

create table if not exists public.code10_enrichment_review_item (
  id uuid primary key default gen_random_uuid(),
  item_type text not null
    check (item_type in ('alias','knowledge','relation','visual','reference')),
  entity_id uuid not null,
  action text not null
    check (action in ('create','update','retire')),
  proposed_change jsonb not null,
  rationale text,
  submitted_by uuid references auth.users(id) on delete set null,
  submitted_at timestamptz not null default now(),
  review_status text not null default 'pending'
    check (review_status in ('pending','approved','rejected','superseded')),
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  review_note text
);
create index if not exists code10_enrichment_review_status_idx
  on public.code10_enrichment_review_item(review_status,item_type,submitted_at);
create index if not exists code10_enrichment_review_submitted_by_idx
  on public.code10_enrichment_review_item(submitted_by)
  where submitted_by is not null;
create index if not exists code10_enrichment_review_reviewed_by_idx
  on public.code10_enrichment_review_item(reviewed_by)
  where reviewed_by is not null;

alter table public.icd10_search_alias
  add column if not exists source_id uuid references public.code10_enrichment_source(id) on delete restrict,
  add column if not exists origin text not null default 'internal'
    check (origin in ('official','standards_based','clinically_reviewed','internal'));

create index if not exists icd10_alias_source_idx
  on public.icd10_search_alias(source_id)
  where source_id is not null;

alter table public.code10_enrichment_source enable row level security;
alter table public.code10_knowledge_reference enable row level security;
alter table public.code10_code_relation enable row level security;
alter table public.code10_visual_asset enable row level security;
alter table public.code10_visual_link enable row level security;
alter table public.code10_enrichment_review_item enable row level security;

revoke all on table public.code10_enrichment_source from anon,authenticated;
revoke all on table public.code10_knowledge_reference from anon,authenticated;
revoke all on table public.code10_code_relation from anon,authenticated;
revoke all on table public.code10_visual_asset from anon,authenticated;
revoke all on table public.code10_visual_link from anon,authenticated;
revoke all on table public.code10_enrichment_review_item from anon,authenticated;

grant select on table public.code10_enrichment_source to authenticated;
grant select on table public.code10_knowledge_reference to authenticated;
grant select on table public.code10_code_relation to authenticated;
grant select on table public.code10_visual_asset to authenticated;
grant select on table public.code10_visual_link to authenticated;
grant select on table public.code10_enrichment_review_item to authenticated;

drop policy if exists code10_enrichment_source_staff_read on public.code10_enrichment_source;
create policy code10_enrichment_source_staff_read
on public.code10_enrichment_source for select to authenticated
using (exists (
  select 1 from public.practice_staff_member m
  where m.user_id=(select auth.uid()) and m.active
));

drop policy if exists code10_knowledge_reference_staff_read on public.code10_knowledge_reference;
create policy code10_knowledge_reference_staff_read
on public.code10_knowledge_reference for select to authenticated
using (exists (
  select 1
  from public.code10_clinical_knowledge k
  join public.practice_staff_member m on m.user_id=(select auth.uid()) and m.active
  where k.id=code10_knowledge_reference.knowledge_id
    and k.review_status='approved'
));

drop policy if exists code10_relation_staff_read on public.code10_code_relation;
create policy code10_relation_staff_read
on public.code10_code_relation for select to authenticated
using (
  review_status='approved'
  and exists (
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.active
  )
);

drop policy if exists code10_visual_asset_staff_read on public.code10_visual_asset;
create policy code10_visual_asset_staff_read
on public.code10_visual_asset for select to authenticated
using (
  review_status='approved'
  and exists (
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.active
  )
);

drop policy if exists code10_visual_link_staff_read on public.code10_visual_link;
create policy code10_visual_link_staff_read
on public.code10_visual_link for select to authenticated
using (
  exists (
    select 1
    from public.code10_visual_asset a
    join public.practice_staff_member m on m.user_id=(select auth.uid()) and m.active
    where a.id=code10_visual_link.visual_asset_id
      and a.review_status='approved'
  )
);

drop policy if exists code10_enrichment_review_privileged_read on public.code10_enrichment_review_item;
create policy code10_enrichment_review_privileged_read
on public.code10_enrichment_review_item for select to authenticated
using (exists (
  select 1 from public.practice_staff_member m
  where m.user_id=(select auth.uid())
    and m.active
    and m.role in ('practitioner','clinical_admin','system_admin','auditor')
));

-- Seed authoritative/licence metadata only; no clinical content or images are auto-approved.
insert into public.code10_enrichment_source(
  source_key,authority_name,source_type,title,source_url,version,
  licence_name,licence_url,commercial_use_allowed,adaptation_allowed,
  attribution_required,attribution_template,notes,verified_at
)
values
(
  'servier-medical-art',
  'Servier Medical Art',
  'visual_library',
  'Servier Medical Art image library',
  'https://smart.servier.com/',
  null,
  'CC BY 4.0',
  'https://creativecommons.org/licenses/by/4.0/',
  true,true,true,
  'Image(s) provided by Servier Medical Art (https://smart.servier.com/), licensed under CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/).',
  'Only individual medical images from the Servier Medical Art library are covered by CC BY 4.0; the surrounding website content is not.',
  now()
),
(
  'ndoh-mit',
  'National Department of Health',
  'regulator',
  'South African ICD-10 Master Industry Table',
  'https://www.health.gov.za/icd-10-master-industry-table/',
  '2021',
  null,null,null,null,null,null,
  'Canonical South African ICD-10 code-validity source.',
  now()
),
(
  'phisc-icd10-standards',
  'Private Healthcare Information Standards Committee',
  'standards_body',
  'South African ICD-10 Coding Standards and Addendum',
  'https://www.phisc.net/standards/phisc-standards',
  'Version 8 / October 2025',
  null,null,null,null,null,null,
  'Industry coding standards/guidance. Must not be represented as legislation.',
  now()
),
(
  'cms-pmb',
  'Council for Medical Schemes',
  'regulator',
  'Prescribed Minimum Benefit guidance and coded lists',
  'https://www.medicalschemes.co.za/resources/pmb/pmb-conditions/',
  '2026',
  null,null,null,null,null,null,
  'PMB coded-list content is a guidance layer; entitlement requires applicable regulatory/clinical criteria.',
  now()
)
on conflict (source_key) do update set
  authority_name=excluded.authority_name,
  source_type=excluded.source_type,
  title=excluded.title,
  source_url=excluded.source_url,
  version=excluded.version,
  licence_name=excluded.licence_name,
  licence_url=excluded.licence_url,
  commercial_use_allowed=excluded.commercial_use_allowed,
  adaptation_allowed=excluded.adaptation_allowed,
  attribution_required=excluded.attribution_required,
  attribution_template=excluded.attribution_template,
  notes=excluded.notes,
  verified_at=excluded.verified_at;

create or replace function public.get_code10_context_v2(p_code_id uuid)
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
      'id',k.id,
      'plain_language_summary',k.plain_language_summary,
      'documentation_prompts',k.documentation_prompts,
      'common_terms',k.common_terms,
      'body_system',k.body_system,
      'clinical_notes',k.clinical_notes,
      'reviewed_at',k.reviewed_at,
      'references',coalesce((
        select jsonb_agg(jsonb_build_object(
          'source_key',s.source_key,
          'authority_name',s.authority_name,
          'title',s.title,
          'source_url',s.source_url,
          'version',s.version,
          'component',kr.component,
          'source_locator',kr.source_locator,
          'evidence_note',kr.evidence_note
        ) order by s.authority_name,s.title)
        from public.code10_knowledge_reference kr
        join public.code10_enrichment_source s on s.id=kr.source_id
        where kr.knowledge_id=k.id
      ),'[]'::jsonb)
    ) end
    from public.code10_clinical_knowledge k
    where k.code_id=c.id and k.review_status='approved'
    limit 1
  ),
  'relations',coalesce((
    select jsonb_agg(jsonb_build_object(
      'relation_type',r.relation_type,
      'authority_level',r.authority_level,
      'target',jsonb_build_object(
        'id',t.id,'code',t.code,'official_description',t.official_description
      ),
      'source',case when s.id is null then null else jsonb_build_object(
        'source_key',s.source_key,'authority_name',s.authority_name,
        'title',s.title,'source_url',s.source_url,'version',s.version
      ) end,
      'evidence_note',r.evidence_note
    ) order by r.relation_type,t.code)
    from public.code10_code_relation r
    join public.sa_icd10_code t on t.id=r.target_code_id
    left join public.code10_enrichment_source s on s.id=r.source_id
    where r.source_code_id=c.id and r.review_status='approved'
  ),'[]'::jsonb),
  'visuals',coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',a.id,
      'title',a.title,
      'source_page_url',a.source_page_url,
      'original_asset_url',a.original_asset_url,
      'storage_bucket',a.storage_bucket,
      'storage_object_path',a.storage_object_path,
      'mime_type',a.mime_type,
      'licence_name',a.licence_name,
      'licence_url',a.licence_url,
      'attribution_text',a.attribution_text,
      'adapted',a.adapted,
      'adaptation_note',a.adaptation_note,
      'link_type',l.link_type,
      'caption',l.caption,
      'display_priority',l.display_priority
    ) order by l.display_priority,a.title)
    from public.code10_visual_link l
    join public.code10_visual_asset a on a.id=l.visual_asset_id and a.review_status='approved'
    where l.code_id=c.id
  ),'[]'::jsonb),
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

revoke all on function public.get_code10_context_v2(uuid) from public,anon;
grant execute on function public.get_code10_context_v2(uuid) to authenticated;

commit;
