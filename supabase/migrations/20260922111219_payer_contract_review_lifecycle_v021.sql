
create or replace function private.propose_payer_contract_document_terms_internal(
  p_document_id uuid,
  p_terms jsonb
) returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare
  v_user uuid := (select auth.uid());
  d public.payer_contract_document%rowtype;
begin
  if v_user is null or coalesce((select auth.jwt()->>'aal'),'') <> 'aal2' then
    raise exception 'AAL2 authentication required';
  end if;
  select * into d
  from public.payer_contract_document
  where id=p_document_id
  for update;
  if not found then raise exception 'Document not found'; end if;
  if d.review_status='approved' then
    raise exception 'Approved evidence is locked. Upload a new document version for changed terms';
  end if;
  if not exists(
    select 1 from public.practice_staff_member m
    where m.user_id=v_user and m.practice_id=d.practice_id and m.active
      and m.role in ('billing','practice_manager','clinical_admin','system_admin')
  ) then raise exception 'Contract-intelligence role required'; end if;
  if p_terms is null or jsonb_typeof(p_terms) <> 'object' or p_terms='{}'::jsonb then
    raise exception 'Structured proposed terms are required';
  end if;

  update public.payer_contract_document
     set proposed_terms = coalesce(proposed_terms,'{}'::jsonb) || p_terms
                         || jsonb_build_object(
                              'proposal_recorded_at', now(),
                              'proposal_recorded_by', v_user,
                              'proposal_source', coalesce(nullif(p_terms->>'proposal_source',''),'human_assisted')
                            ),
         extraction_status='proposed',
         review_status=case when review_status='rejected' then 'unreviewed' else 'in_review' end
   where id=p_document_id;

  return p_document_id;
end $$;

create or replace function public.propose_payer_contract_document_terms(
  p_document_id uuid,
  p_terms jsonb
) returns uuid
language sql
set search_path=''
as $$ select private.propose_payer_contract_document_terms_internal(p_document_id,p_terms) $$;

revoke all on function private.propose_payer_contract_document_terms_internal(uuid,jsonb) from public,anon;
revoke all on function public.propose_payer_contract_document_terms(uuid,jsonb) from public,anon;
grant execute on function private.propose_payer_contract_document_terms_internal(uuid,jsonb) to authenticated;
grant execute on function public.propose_payer_contract_document_terms(uuid,jsonb) to authenticated,service_role;

create or replace function private.submit_payer_contract_for_review_internal(
  p_contract_id uuid
) returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare
  v_user uuid := (select auth.uid());
  c public.payer_contract%rowtype;
begin
  if v_user is null or coalesce((select auth.jwt()->>'aal'),'') <> 'aal2' then
    raise exception 'AAL2 authentication required';
  end if;
  select * into c from public.payer_contract where id=p_contract_id for update;
  if not found then raise exception 'Contract not found'; end if;
  if not exists(
    select 1 from public.practice_staff_member m
    where m.user_id=v_user and m.practice_id=c.practice_id and m.active
      and m.role in ('billing','practice_manager','system_admin')
  ) then raise exception 'Contract management role required'; end if;
  if c.status not in ('draft','in_review') then
    raise exception 'Only a draft contract can be submitted for review';
  end if;
  if c.source_document_id is null then raise exception 'Contract evidence is required'; end if;
  if not exists(select 1 from public.payer_billing_rule r where r.contract_id=c.id and r.status in ('proposed','approved','active')) then
    raise exception 'At least one billing rule proposal is required before review';
  end if;

  update public.payer_contract set status='in_review',updated_at=now() where id=c.id;
  return c.id;
end $$;

create or replace function public.submit_payer_contract_for_review(p_contract_id uuid)
returns uuid
language sql
set search_path=''
as $$ select private.submit_payer_contract_for_review_internal(p_contract_id) $$;

revoke all on function private.submit_payer_contract_for_review_internal(uuid) from public,anon;
revoke all on function public.submit_payer_contract_for_review(uuid) from public,anon;
grant execute on function private.submit_payer_contract_for_review_internal(uuid) to authenticated;
grant execute on function public.submit_payer_contract_for_review(uuid) to authenticated,service_role;

create or replace function private.approve_payer_contract_internal(
  p_contract_id uuid
) returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare
  v_user uuid := (select auth.uid());
  c public.payer_contract%rowtype;
begin
  if v_user is null or coalesce((select auth.jwt()->>'aal'),'') <> 'aal2' then
    raise exception 'AAL2 authentication required';
  end if;
  select * into c from public.payer_contract where id=p_contract_id for update;
  if not found then raise exception 'Contract not found'; end if;
  if not exists(
    select 1 from public.practice_staff_member m
    where m.user_id=v_user and m.practice_id=c.practice_id and m.active
      and m.role in ('practice_manager','system_admin')
  ) then raise exception 'Practice manager role required'; end if;
  if c.status <> 'in_review' then raise exception 'Contract must be in review before approval'; end if;
  if c.source_document_id is null or not exists(
    select 1 from public.payer_contract_document d
    where d.id=c.source_document_id and d.practice_id=c.practice_id and d.review_status='approved'
  ) then raise exception 'Approved contract evidence is required'; end if;
  if not exists(select 1 from public.payer_billing_rule r where r.contract_id=c.id and r.status in ('proposed','approved')) then
    raise exception 'At least one proposed billing rule is required';
  end if;

  update public.payer_contract
     set status='approved',approved_by=v_user,approved_at=now(),last_verified_at=now(),updated_at=now()
   where id=c.id;

  update public.payer_billing_rule
     set status='approved',approved_by=v_user,approved_at=now(),last_verified_at=now(),updated_at=now()
   where contract_id=c.id and status='proposed';

  return c.id;
end $$;

create or replace function public.approve_payer_contract(p_contract_id uuid)
returns uuid
language sql
set search_path=''
as $$ select private.approve_payer_contract_internal(p_contract_id) $$;

revoke all on function private.approve_payer_contract_internal(uuid) from public,anon;
revoke all on function public.approve_payer_contract(uuid) from public,anon;
grant execute on function private.approve_payer_contract_internal(uuid) to authenticated;
grant execute on function public.approve_payer_contract(uuid) to authenticated,service_role;

create or replace function public.activate_payer_contract(p_contract_id uuid)
returns uuid
language plpgsql
set search_path to 'public','pg_temp'
as $function$
declare
  v_user uuid := (select auth.uid());
  c public.payer_contract%rowtype;
begin
  if v_user is null or coalesce((select auth.jwt()->>'aal'),'') <> 'aal2' then
    raise exception 'AAL2 authentication required';
  end if;
  select * into c from public.payer_contract where id=p_contract_id for update;
  if not found then raise exception 'Contract not found'; end if;
  if not exists(
    select 1 from public.practice_staff_member m
    where m.user_id=v_user and m.practice_id=c.practice_id and m.active
      and m.role in ('practice_manager','system_admin')
  ) then raise exception 'Practice manager role required'; end if;
  if c.status <> 'approved' then raise exception 'Contract must be approved before activation'; end if;
  if c.source_document_id is null or not exists(
    select 1 from public.payer_contract_document d
    where d.id=c.source_document_id and d.practice_id=c.practice_id and d.review_status='approved'
  ) then raise exception 'An approved source document is required before contract activation'; end if;

  update public.payer_contract
     set status='active',last_verified_at=coalesce(last_verified_at,now()),updated_at=now()
   where id=c.id;
  update public.payer_billing_rule
     set status='active',last_verified_at=coalesce(last_verified_at,now()),updated_at=now()
   where contract_id=c.id and status='approved';
  return c.id;
end $function$;

revoke all on function public.activate_payer_contract(uuid) from public,anon;
grant execute on function public.activate_payer_contract(uuid) to authenticated,service_role;

