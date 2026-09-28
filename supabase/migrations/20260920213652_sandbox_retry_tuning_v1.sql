
    update public.integration_retry_policy p
    set timeout_ms=500,
        initial_delay_ms=50,
        max_delay_ms=100,
        jitter_ratio=0.000,
        max_attempts=2,
        updated_at=now()
    from public.integration_provider pr
    where p.provider_id=pr.id
      and pr.slug='practicectrl-sandbox'
      and p.environment='sandbox';
  
