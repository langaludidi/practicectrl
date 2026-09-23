import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { ReportTable } from "@/components/reports/ReportTable";
import { SectionHeader } from "@/components/SectionHeader";
import { requireStaffContext } from "@/lib/auth/server";
import { REPORT_DEFINITIONS } from "@/lib/reports/catalogue";
import { buildReport } from "@/lib/reports/buildReport";

export default async function ReportViewPage({ params }: { params: Promise<{ id: string }> }) {
  const staff = await requireStaffContext();
  const { id } = await params;
  const report = REPORT_DEFINITIONS.find(item => item.id === id);

  if (!report || !report.roles.includes(staff.role)) notFound();
  if (!report.detailKind) redirect(report.href);

  const built = await buildReport(staff.practiceId, report);

  return <div className="space-y-6">
    <SectionHeader
      title={built.title}
      body={built.subtitle ?? report.description}
      action={<Link href="/reports" className="inline-flex h-10 items-center border border-[#cfd8e3] bg-white px-3 text-sm font-semibold text-[#334155] hover:border-[#029ea1] hover:text-[#067c80]">← Reports</Link>}
    />
    <div className="border-l-4 border-[#029ea1] bg-[#eefafa] px-4 py-3 text-sm leading-6 text-[#23465a]">
      <strong className="text-[#051a39]">PracticeCtrl equivalent:</strong> {report.practiceCtrlName}. The legacy report name is retained for transition and recognition; calculations and row visibility follow PracticeCtrl’s governed source data and role access.
    </div>
    <ReportTable title={built.title} subtitle={built.subtitle} columns={built.columns} rows={built.rows} />
  </div>;
}
