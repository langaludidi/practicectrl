import Link from "next/link";
import { requireStaffContext } from "@/lib/auth/server";
import { createClient } from "@/lib/supabase/server";
import { PracticeConfigurationWorkspace } from "@/components/admin/PracticeConfigurationWorkspace";
import { PayerRuleSimulator } from "@/components/contracts/PayerRuleSimulator";

export default async function PracticeConfigurationPage() {
  const staff = await requireStaffContext();
  if (!["practice_manager", "system_admin", "auditor"].includes(staff.role)) {
    return <p role="alert">Practice Configuration requires an administrator or auditor role.</p>;
  }
  const db = await createClient();
  const id = staff.practiceId;
  const [profile, billing, operating, locations, practitioners, appointmentTypes, relationships, policies, events, schemes, options] = await Promise.all([
    db.from("practice").select("id,name,legal_name,timezone,branding").eq("id", id).single(),
    db.from("practice_billing_profile").select("trading_name,registration_number,vat_registered,vat_registration_number,email,phone,invoice_footer,statement_footer").eq("practice_id", id).maybeSingle(),
    db.from("practice_operating_config").select("practice_id,appointment_source,default_appointment_minutes,cancellation_notice_hours,require_patient_contact,require_scheme_membership,require_identity_review,default_currency").eq("practice_id", id).maybeSingle(),
    db.from("practice_location").select("id,name,location_type,address,timezone,active").eq("practice_id", id).order("name"),
    db.from("practitioner_profile").select("id,display_name,profession,speciality,hpcsa_number,practice_number,billing_provider_number,default_location_id,active").eq("practice_id", id).order("display_name"),
    db.from("appointment_type").select("id,name,duration_minutes,requires_authorisation,active").eq("practice_id", id).order("name"),
    db.from("practice_payer_relationship").select("id,medical_scheme_id,status,relationship_type,accepted,network_status,effective_from,effective_to,version").eq("practice_id", id).order("created_at", { ascending: false }),
    db.from("practice_policy").select("id,policy_key,title,category,sop,status,version,effective_from,effective_to,owner_role,blocking").eq("practice_id", id).order("created_at", { ascending: false }),
    db.from("practice_configuration_event").select("id,entity_type,action,actor_user_id,created_at,before_value,after_value").eq("practice_id", id).order("created_at", { ascending: false }).limit(30),
    db.from("medical_scheme").select("id,name").order("name").limit(500),
    db.from("medical_scheme_option").select("id,medical_scheme_id,benefit_year,option_name").eq("approval_status","approved").order("benefit_year",{ascending:false}).limit(1500),
  ]);
  const failures = [profile, billing, operating, locations, practitioners, appointmentTypes, relationships, policies, events, schemes, options].filter(x => x.error);
  if (failures.length) return <div role="alert" className="border border-rose-300 bg-rose-50 p-4 text-rose-900">Practice Configuration is unavailable until its development migration and tenant permissions are applied. {failures.map(x => x.error?.message).join("; ")}</div>;
  if (!profile.data) return <p role="alert">Active practice could not be found.</p>;
  return <div className="space-y-5">
    <div><p className="text-xs font-bold uppercase tracking-widest text-teal-700">System / Practice Configuration</p><h1 className="mt-1 text-3xl font-semibold text-[#10223c]">Practice Configuration</h1><p className="mt-2 max-w-3xl text-sm text-slate-600">Define how this practice works. Changes to payer agreements and policies are governed and effective dated.</p></div>
    <PracticeConfigurationWorkspace practiceId={id} role={staff.role} profile={profile.data} billing={billing.data} operating={operating.data} locations={locations.data || []} practitioners={practitioners.data || []} appointmentTypes={appointmentTypes.data || []} relationships={relationships.data || []} policies={policies.data || []} events={events.data || []} schemes={schemes.data || []}/>
    <section id="rule-simulator"><h2 className="mb-3 text-xl font-semibold text-[#10223c]">Effective rule simulator</h2><PayerRuleSimulator practiceId={id} schemes={schemes.data || []} options={options.data || []} practitioners={practitioners.data || []}/></section>
    <p className="text-sm text-slate-600">Agreements and financial rules remain in <Link href="/contracts" className="font-medium text-teal-800 underline">Payer Contract Operations</Link>. Simulation there is read only and evaluates the service date.</p>
  </div>;
}
