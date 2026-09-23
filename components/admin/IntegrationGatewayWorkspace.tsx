type Adapter={id:string;adapter_key:string;adapter_family:string;adapter_version:string;canonical_contract_version:string;executor_key:string;status:string;provider_id:string;interface_id:string};
type Operation={adapter_id:string;capability_code:string;operation_code:string;http_method:string|null;contains_phi:boolean;active:boolean;evidence_url:string|null};
type Provider={id:string;slug:string;name:string};
type Connection={provider_id:string;interface_id:string;environment:string;status:string;credential_secret_ref?:string|null};
type Capability={provider_id:string;interface_id:string;capability_code:string;implementation_status:string;executable_sandbox:boolean;executable_production:boolean};

export function IntegrationGatewayWorkspace({adapters,operations,providers,connections,capabilities}:{adapters:Adapter[];operations:Operation[];providers:Provider[];connections:Connection[];capabilities:Capability[]}){
  const pname=(id:string)=>providers.find(p=>p.id===id)?.name||"Unknown provider";
  return <section className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm">
    <div className="flex flex-wrap items-start justify-between gap-3">
      <div><p className="text-xs font-semibold uppercase tracking-[.14em] text-[#25A6A1]">Medical Scheme Integration Gateway</p><h2 className="mt-1 text-lg font-semibold text-[#173B5E]">One canonical contract, many external adapters</h2><p className="mt-2 max-w-4xl text-sm text-stone-600">PracticeCtrl resolves a provider-neutral capability first, then hands execution to a versioned adapter. Credentials remain server-side secret references; production stays fail-closed until connection, conformance and accreditation gates are satisfied.</p></div>
      <span className="rounded-full bg-stone-100 px-3 py-1 text-xs font-medium text-stone-700">pc-gateway-v1</span>
    </div>
    <div className="mt-5 grid gap-4 lg:grid-cols-2">
      {adapters.map(a=>{const ops=operations.filter(o=>o.adapter_id===a.id);const cap=capabilities.filter(c=>c.provider_id===a.provider_id&&c.interface_id===a.interface_id);const conn=connections.filter(c=>c.provider_id===a.provider_id&&c.interface_id===a.interface_id);return <article key={a.id} className="rounded-xl border border-stone-200 p-4">
        <div className="flex flex-wrap items-start justify-between gap-2"><div><p className="text-xs uppercase tracking-[.12em] text-stone-500">{a.adapter_family} · {a.executor_key}</p><h3 className="mt-1 font-semibold text-[#4a1f3e]">{pname(a.provider_id)}</h3><p className="mt-1 text-xs text-stone-500">{a.adapter_key} · adapter {a.adapter_version}</p></div><span className="rounded-full bg-stone-100 px-2.5 py-1 text-xs">{a.status}</span></div>
        <div className="mt-3 space-y-2">{ops.map(o=>{const readiness=cap.find(c=>c.capability_code===o.capability_code);return <div key={o.operation_code} className="rounded-lg bg-stone-50 p-3"><div className="flex flex-wrap items-center justify-between gap-2"><p className="text-sm font-medium text-stone-800">{o.operation_code}</p><span className="text-xs text-stone-500">{o.capability_code}</span></div><p className="mt-1 text-xs text-stone-600">{o.http_method?`${o.http_method} transport · `:""}{o.contains_phi?"PHI-sensitive":"reference/non-PHI"} · {readiness?.implementation_status||"not registered"}</p><p className="mt-1 text-xs text-stone-500">Sandbox {readiness?.executable_sandbox?"executable":"blocked"} · Production {readiness?.executable_production?"executable":"blocked"}</p></div>})}</div>
        <div className="mt-3 border-t border-stone-100 pt-3"><p className="text-xs font-semibold uppercase text-stone-500">Practice connection</p>{conn.length?conn.map(c=><p key={`${c.environment}-${c.status}`} className="mt-1 text-xs text-stone-600">{c.environment}: {c.status}{c.credential_secret_ref?" · secret reference configured":""}</p>):<p className="mt-1 text-xs text-amber-700">No practice connection configured. Execution remains blocked.</p>}</div>
      </article>})}
    </div>
  </section>
}
