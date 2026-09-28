
    create index if not exists integration_retry_policy_capability_idx
      on public.integration_retry_policy(capability_code);
    create index if not exists integration_retry_policy_interface_idx
      on public.integration_retry_policy(interface_id);
    create index if not exists payer_transaction_event_actor_idx
      on public.payer_transaction_event(actor_user_id)
      where actor_user_id is not null;
  
