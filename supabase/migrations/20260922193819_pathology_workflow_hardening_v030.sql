
do $$
begin
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='pathology_order' and column_name='order_category') then
    raise exception 'pathology order category hardening missing';
  end if;
  if to_regclass('public.pathology_result_inbox') is null then
    raise exception 'pathology unsolicited-result inbox missing';
  end if;
  if to_regprocedure('public.get_pathology_numeric_trend(uuid,uuid,text,integer)') is null then
    raise exception 'pathology trend RPC missing';
  end if;
  if to_regprocedure('public.register_unsolicited_pathology_result(uuid,uuid,uuid,text,text,text,text,text,text)') is null then
    raise exception 'unsolicited pathology result registration missing';
  end if;
  if to_regprocedure('public.match_pathology_result_inbox(uuid,uuid,uuid)') is null then
    raise exception 'pathology inbox matching RPC missing';
  end if;
  if to_regprocedure('public.create_pathology_order(uuid,uuid,uuid,uuid,text,text,text,boolean,text,jsonb)') is null then
    raise exception 'pathology order category-aware create RPC missing';
  end if;
end $$;
