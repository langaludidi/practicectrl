import { SectionHeader } from "@/components/SectionHeader";
import { PayerContractWorkspace } from "@/components/contracts/PayerContractWorkspace";
import { requireStaffContext } from "@/lib/auth/server";
import { canViewRevenue } from "@/lib/auth/roles";
import { createClient } from "@/lib/supabase/server";

export default async function PayerContractsPage(){
  const staff=await requireStaffContext();
  if(!canViewRevenue(staff.role)) return <p className="text-sm text-stone-600">Your role does not have payer-contract access.</p>;
  const supabase=await createClient();
  const [{data:contracts},{data:rules},{data:documents},{data:schemes},{data:options},{data:practitioners},{data:events}]=await Promise.all([
    supabase.from("payer_contract").select("id,practitioner_id,medical_scheme_id,medical_scheme_option_id,administrator_name,agreement_type,network_status,discipline_code,provider_number,contract_reference,version,effective_from,effective_to,source_document_id,status,payment_terms_days,approved_at,last_verified_at,created_at").eq("practice_id",staff.practiceId).order("created_at",{ascending:false}).limit(200),
    supabase.from("payer_billing_rule").select("id,contract_id,practitioner_id,medical_scheme_id,medical_scheme_option_id,rule_scope,rule_type,code_system,code,modifier_code,calculation_method,rate_percent,fixed_amount,currency,rule_value,conditions,requirements,effective_from,effective_to,version,source_document_id,status,last_verified_at").eq("practice_id",staff.practiceId).order("created_at",{ascending:false}).limit(500),
    supabase.from("payer_contract_document").select("id,contract_id,document_type,title,original_filename,mime_type,byte_size,sha256,extraction_status,proposed_terms,review_status,reviewed_at,uploaded_at").eq("practice_id",staff.practiceId).order("uploaded_at",{ascending:false}).limit(200),
    supabase.from("medical_scheme").select("id,name,cms_registration_number,regulatory_status,effective_from,effective_to").order("name").limit(500),
    supabase.from("medical_scheme_option").select("id,medical_scheme_id,benefit_year,option_name,option_code,approval_status,effective_from,effective_to,parent_option_name,is_efficiency_discounted,source_comment").eq("benefit_year",2026).eq("approval_status","approved").order("option_name").limit(1500),
    supabase.from("practitioner_profile").select("id,display_name,profession,speciality,practice_number,billing_provider_number,active").eq("practice_id",staff.practiceId).eq("active",true).order("display_name").limit(100),
    supabase.from("payer_contract_event").select("id,contract_id,document_id,rule_id,event_type,from_status,to_status,metadata,created_at").eq("practice_id",staff.practiceId).order("created_at",{ascending:false}).limit(100),
  ]);
  return <div className="space-y-6">
    <SectionHeader title="Payer Contract Operations" body="Govern practice-specific medical-scheme agreements from evidence capture through structured term review, effective-dated billing rules, simulation, approval and activation. Every operational billing decision preserves its evidence and precedence trace."/>
    <PayerContractWorkspace practiceId={staff.practiceId} role={staff.role} contracts={(contracts||[]) as any} rules={(rules||[]) as any} documents={(documents||[]) as any} schemes={(schemes||[]) as any} options={(options||[]) as any} practitioners={(practitioners||[]) as any} events={(events||[]) as any}/>
  </div>;
}
