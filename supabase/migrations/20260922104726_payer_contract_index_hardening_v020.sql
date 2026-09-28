
create unique index if not exists payer_contract_document_practice_sha256_uq
on public.payer_contract_document(practice_id,sha256) where sha256 is not null;

create index if not exists payer_contract_scheme_idx on public.payer_contract(medical_scheme_id);
create index if not exists payer_contract_option_idx on public.payer_contract(medical_scheme_option_id);
create index if not exists payer_contract_practitioner_idx on public.payer_contract(practitioner_id);
create index if not exists payer_contract_source_document_idx on public.payer_contract(source_document_id);
create index if not exists payer_contract_approved_by_idx on public.payer_contract(approved_by);
create index if not exists payer_contract_created_by_idx on public.payer_contract(created_by);

create index if not exists payer_rule_practitioner_idx on public.payer_billing_rule(practitioner_id);
create index if not exists payer_rule_scheme_idx on public.payer_billing_rule(medical_scheme_id);
create index if not exists payer_rule_option_idx on public.payer_billing_rule(medical_scheme_option_id);
create index if not exists payer_rule_tariff_schedule_idx on public.payer_billing_rule(tariff_schedule_id);
create index if not exists payer_rule_tariff_rate_idx on public.payer_billing_rule(tariff_rate_id);
create index if not exists payer_rule_source_document_idx on public.payer_billing_rule(source_document_id);
create index if not exists payer_rule_approved_by_idx on public.payer_billing_rule(approved_by);
create index if not exists payer_rule_created_by_idx on public.payer_billing_rule(created_by);

create index if not exists payer_contract_document_contract_idx on public.payer_contract_document(contract_id);
create index if not exists payer_contract_document_reviewed_by_idx on public.payer_contract_document(reviewed_by);
create index if not exists payer_contract_document_uploaded_by_idx on public.payer_contract_document(uploaded_by);

create index if not exists payer_resolution_invoice_line_idx on public.payer_rule_resolution(invoice_line_id);
create index if not exists payer_resolution_claim_line_idx on public.payer_rule_resolution(claim_line_id);
create index if not exists payer_resolution_practitioner_idx on public.payer_rule_resolution(practitioner_id);
create index if not exists payer_resolution_scheme_idx on public.payer_rule_resolution(medical_scheme_id);
create index if not exists payer_resolution_option_idx on public.payer_rule_resolution(medical_scheme_option_id);
create index if not exists payer_resolution_rule_idx on public.payer_rule_resolution(applied_rule_id);
create index if not exists payer_resolution_contract_idx on public.payer_rule_resolution(applied_contract_id);
create index if not exists payer_resolution_resolved_by_idx on public.payer_rule_resolution(resolved_by);

create index if not exists payer_variance_claim_line_idx on public.payer_remittance_variance(claim_line_id);
create index if not exists payer_variance_rule_resolution_idx on public.payer_remittance_variance(rule_resolution_id);
create index if not exists payer_variance_reviewed_by_idx on public.payer_remittance_variance(reviewed_by);

create index if not exists billing_invoice_line_payer_resolution_idx on public.billing_invoice_line(payer_rule_resolution_id);
create index if not exists claim_line_payer_resolution_idx on public.claim_line(payer_rule_resolution_id);

