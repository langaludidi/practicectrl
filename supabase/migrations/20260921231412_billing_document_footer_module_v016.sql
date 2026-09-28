
create or replace function public.billing_supplier_snapshot(p_practice_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path=public,pg_temp
as $$
  select jsonb_build_object(
    'practice_id',p.id,
    'legal_name',coalesce(bp.legal_name,p.legal_name,p.name),
    'trading_name',coalesce(bp.trading_name,p.name),
    'registration_number',bp.registration_number,
    'vat_registered',coalesce(bp.vat_registered,false),
    'vat_registration_number',bp.vat_registration_number,
    'address',coalesce(bp.address,'{}'::jsonb),
    'email',bp.email,
    'phone',bp.phone,
    'banking_details',coalesce(bp.banking_details,'{}'::jsonb),
    'invoice_footer',bp.invoice_footer,
    'quote_footer',bp.quote_footer,
    'statement_footer',bp.statement_footer,
    'payment_terms_days',bp.payment_terms_days,
    'country_code',p.country_code
  )
  from public.practice p
  left join public.practice_billing_profile bp on bp.practice_id=p.id
  where p.id=p_practice_id;
$$;

update public.platform_module
set display_name='Billing & Revenue',
    descriptor='Quotes, clinical and transactional invoicing, debtor accounts, receipts, credit notes, statements, claims and revenue integrity',
    enabled_by_default=true
where module_key='billing';

insert into public.practice_module(practice_id,module_id,enabled,enabled_at,configuration)
select p.id,m.id,true,now(),'{}'::jsonb
from public.practice p
join public.platform_module m on m.module_key='billing'
on conflict(practice_id,module_id) do update
set enabled=true,enabled_at=coalesce(public.practice_module.enabled_at,excluded.enabled_at);

