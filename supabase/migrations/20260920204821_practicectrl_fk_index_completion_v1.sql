
create index if not exists billing_code_reference_source_release_idx
  on public.billing_code_reference(source_release_id);
create index if not exists integration_capability_capability_code_idx
  on public.integration_capability(capability_code);
create index if not exists integration_capability_interface_idx
  on public.integration_capability(interface_id);
create index if not exists payer_transaction_route_capability_idx
  on public.payer_transaction_route(capability_code);
create index if not exists practice_integration_connection_interface_idx
  on public.practice_integration_connection(interface_id);
create index if not exists practice_integration_connection_provider_idx
  on public.practice_integration_connection(provider_id);
create index if not exists practice_module_module_idx
  on public.practice_module(module_id);
create index if not exists remittance_advice_provider_idx
  on public.remittance_advice(provider_id);
create index if not exists tariff_rate_code_system_idx
  on public.tariff_rate(code_system);
create index if not exists tariff_schedule_option_idx
  on public.tariff_schedule(medical_scheme_option_id);
create index if not exists tariff_schedule_practice_idx
  on public.tariff_schedule(practice_id);

