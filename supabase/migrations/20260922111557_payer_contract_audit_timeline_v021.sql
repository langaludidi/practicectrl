
create table if not exists public.payer_contract_event(
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null references public.practice(id) on delete cascade,
  contract_id uuid references public.payer_contract(id) on delete cascade,
  document_id uuid references public.payer_contract_document(id) on delete cascade,
  rule_id uuid references public.payer_billing_rule(id) on delete cascade,
  event_type text not null,
  from_status text,
  to_status text,
  actor_user_id uuid references auth.users(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  check (contract_id is not null or document_id is not null or rule_id is not null)
);

alter table public.payer_contract_event enable row level security;

drop policy if exists payer_contract_event_staff_read on public.payer_contract_event;
create policy payer_contract_event_staff_read
on public.payer_contract_event
for select
to authenticated
using (
  exists(
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=payer_contract_event.practice_id
      and m.active
  )
);

revoke all on public.payer_contract_event from anon,authenticated;
grant select on public.payer_contract_event to authenticated;
grant all on public.payer_contract_event to service_role;

create index if not exists payer_contract_event_practice_time_idx on public.payer_contract_event(practice_id,created_at desc);
create index if not exists payer_contract_event_contract_idx on public.payer_contract_event(contract_id,created_at desc);
create index if not exists payer_contract_event_document_idx on public.payer_contract_event(document_id,created_at desc);
create index if not exists payer_contract_event_rule_idx on public.payer_contract_event(rule_id,created_at desc);
create index if not exists payer_contract_event_actor_idx on public.payer_contract_event(actor_user_id);

create or replace function private.audit_payer_contract_lifecycle()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_practice uuid;
  v_event text;
  v_from text;
  v_to text;
  v_contract uuid;
  v_document uuid;
  v_rule uuid;
  v_meta jsonb := '{}'::jsonb;
begin
  if tg_table_name='payer_contract' then
    v_practice:=new.practice_id;v_contract:=new.id;
    if tg_op='INSERT' then
      v_event:='contract_created';v_to:=new.status;
      v_meta:=jsonb_build_object('contract_reference',new.contract_reference,'version',new.version);
    elsif old.status is distinct from new.status then
      v_event:='contract_status_changed';v_from:=old.status;v_to:=new.status;
    else return new;
    end if;
  elsif tg_table_name='payer_contract_document' then
    v_practice:=new.practice_id;v_document:=new.id;v_contract:=new.contract_id;
    if tg_op='INSERT' then
      v_event:='evidence_uploaded';v_to:=new.review_status;
      v_meta:=jsonb_build_object('document_type',new.document_type,'sha256',new.sha256,'extraction_status',new.extraction_status);
    elsif old.review_status is distinct from new.review_status then
      v_event:='evidence_review_status_changed';v_from:=old.review_status;v_to:=new.review_status;
      v_meta:=jsonb_build_object('extraction_status',new.extraction_status);
    elsif old.extraction_status is distinct from new.extraction_status then
      v_event:='evidence_terms_status_changed';v_from:=old.extraction_status;v_to:=new.extraction_status;
    else return new;
    end if;
  elsif tg_table_name='payer_billing_rule' then
    v_practice:=new.practice_id;v_rule:=new.id;v_contract:=new.contract_id;
    if tg_op='INSERT' then
      v_event:='rule_proposed';v_to:=new.status;
      v_meta:=jsonb_build_object('rule_type',new.rule_type,'code_system',new.code_system,'code',new.code,'scope',new.rule_scope);
    elsif old.status is distinct from new.status then
      v_event:='rule_status_changed';v_from:=old.status;v_to:=new.status;
      v_meta:=jsonb_build_object('rule_type',new.rule_type,'code',new.code);
    else return new;
    end if;
  end if;

  insert into public.payer_contract_event(practice_id,contract_id,document_id,rule_id,event_type,from_status,to_status,actor_user_id,metadata)
  values(v_practice,v_contract,v_document,v_rule,v_event,v_from,v_to,v_actor,v_meta);
  return new;
end $$;

revoke all on function private.audit_payer_contract_lifecycle() from public,anon,authenticated;

drop trigger if exists payer_contract_audit_trg on public.payer_contract;
create trigger payer_contract_audit_trg
after insert or update on public.payer_contract
for each row execute function private.audit_payer_contract_lifecycle();

drop trigger if exists payer_contract_document_audit_trg on public.payer_contract_document;
create trigger payer_contract_document_audit_trg
after insert or update on public.payer_contract_document
for each row execute function private.audit_payer_contract_lifecycle();

drop trigger if exists payer_billing_rule_audit_trg on public.payer_billing_rule;
create trigger payer_billing_rule_audit_trg
after insert or update on public.payer_billing_rule
for each row execute function private.audit_payer_contract_lifecycle();

