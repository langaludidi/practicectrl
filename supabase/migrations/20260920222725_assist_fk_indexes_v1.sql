create index if not exists assist_capability_module_idx
           on public.assist_capability(module_key)
           where module_key is not null;
         create index if not exists practice_assist_capability_idx
           on public.practice_assist_policy(capability_key);
