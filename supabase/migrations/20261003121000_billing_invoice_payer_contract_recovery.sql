begin;

alter table public.billing_invoice
  add column if not exists payer_contract_id uuid;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname='billing_invoice_payer_contract_id_fkey'
      and conrelid='public.billing_invoice'::regclass
  ) then
    alter table public.billing_invoice
      add constraint billing_invoice_payer_contract_id_fkey
      foreign key (payer_contract_id)
      references public.payer_contract(id)
      on delete restrict;
  end if;
end $$;

create index if not exists billing_invoice_payer_contract_idx
  on public.billing_invoice(payer_contract_id)
  where payer_contract_id is not null;

drop trigger if exists tenant_guard_invoice_payer_contract on public.billing_invoice;
create trigger tenant_guard_invoice_payer_contract
before insert or update of practice_id,payer_contract_id
on public.billing_invoice
for each row
when (new.payer_contract_id is not null)
execute function public.enforce_same_practice_reference('payer_contract','payer_contract_id');

commit;
