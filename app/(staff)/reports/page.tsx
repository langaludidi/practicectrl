import { SectionHeader } from "@/components/SectionHeader";
import { ReportsWorkspace } from "@/components/reports/ReportsWorkspace";
import { requireStaffContext } from "@/lib/auth/server";

export default async function ReportsPage() {
  const staff = await requireStaffContext();

  return <div className="space-y-6">
    <SectionHeader
      title="Reports"
      body="A single governed catalogue for operational, clinical, coding, billing and financial reporting. Legacy report names are retained as a transition aid, while the underlying information is delivered through current PracticeCtrl workspaces and drill-downs."
    />
    <ReportsWorkspace role={staff.role} />
  </div>;
}
