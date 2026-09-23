import { createClient } from "@/lib/supabase/server";
import { money, shortDate } from "@/lib/format";
import type { ReportDefinition } from "@/lib/reports/catalogue";

export type ReportColumn = { key: string; label: string; align?: "left" | "right" };
export type ReportRow = Record<string, string | number | null>;
export type BuiltReport = { title: string; subtitle?: string; columns: ReportColumn[]; rows: ReportRow[] };

const amount = (value: unknown) => money(Number(value || 0));
const text = (value: unknown) => value == null || value === "" ? "—" : String(value);
const unique = (values: Array<string | null | undefined>) => [...new Set(values.filter((value): value is string => Boolean(value)))];

async function lookupMap(supabase: any, table: string, ids: string[], labelColumn: string) {
  if (!ids.length) return new Map<string,string>();
  const { data, error } = await supabase.from(table).select(`id,${labelColumn}`).in("id", ids);
  if (error) throw error;
  return new Map((data || []).map((row: any) => [String(row.id), String(row[labelColumn] || row.id)]));
}

export async function buildReport(practiceId: string, report: ReportDefinition): Promise<BuiltReport> {
  const supabase = await createClient();

  if (report.detailKind === "ageing") {
    const { data, error } = await supabase
      .from("revenue_account_snapshot")
      .select("id,patient_name_snapshot,account_ref,file_ref,scheme_name_snapshot,current_amount,days_30,days_60,days_90,days_120_plus,total_amount,liability_status,collection_suppressed,snapshot_at")
      .eq("practice_id", practiceId)
      .eq("source_freshness_status", "current")
      .limit(1500);
    if (error) throw error;
    let rows = [...(data || [])] as any[];

    if (report.id === "accounts-credit" || report.id === "age-combined-credit") {
      rows = rows.filter(row => row.liability_status === "credit" || Number(row.total_amount) < 0);
    } else if (report.id === "age-combined-debit") {
      rows = rows.filter(row => row.liability_status !== "credit" && Number(row.total_amount) > 0);
    } else if (report.id === "age-patient-liable") {
      rows = rows.filter(row => ["patient_verified","split_verified"].includes(row.liability_status));
    } else if (report.id === "age-scheme-liable") {
      rows = rows.filter(row => ["scheme_verified","split_verified"].includes(row.liability_status));
    }

    if (report.id === "age-summary") {
      const sums = [
        ["Current", "current_amount"],
        ["30 days", "days_30"],
        ["60 days", "days_60"],
        ["90 days", "days_90"],
        ["120+ days", "days_120_plus"],
        ["Total", "total_amount"],
      ] as const;
      return {
        title: report.legacyName,
        subtitle: "Current promoted age-analysis snapshot, separated from live PracticeCtrl transactions and preserving source provenance.",
        columns: [{key:"bucket",label:"Age bucket"},{key:"amount",label:"Amount",align:"right"}],
        rows: sums.map(([bucket,key]) => ({ bucket, amount: amount(rows.reduce((sum,row) => sum + Number(row[key] || 0), 0)) })),
      };
    }

    if (report.id === "age-by-account") rows.sort((a,b) => text(a.account_ref).localeCompare(text(b.account_ref)));
    else if (report.id === "age-by-file") rows.sort((a,b) => text(a.file_ref).localeCompare(text(b.file_ref)));
    else rows.sort((a,b) => Math.abs(Number(b.total_amount || 0)) - Math.abs(Number(a.total_amount || 0)));

    return {
      title: report.legacyName,
      subtitle: "Current promoted age-analysis snapshot. Liability is shown only at the verification state actually recorded in PracticeCtrl.",
      columns: [
        {key:"patient",label:"Patient"},{key:"account",label:"Account"},{key:"file",label:"File"},
        {key:"scheme",label:"Scheme"},{key:"current",label:"Current",align:"right"},{key:"d30",label:"30",align:"right"},
        {key:"d60",label:"60",align:"right"},{key:"d90",label:"90",align:"right"},{key:"d120",label:"120+",align:"right"},
        {key:"total",label:"Total",align:"right"},{key:"liability",label:"Liability"}
      ],
      rows: rows.map(row => ({
        patient:text(row.patient_name_snapshot),account:text(row.account_ref),file:text(row.file_ref),scheme:text(row.scheme_name_snapshot),
        current:amount(row.current_amount),d30:amount(row.days_30),d60:amount(row.days_60),d90:amount(row.days_90),
        d120:amount(row.days_120_plus),total:amount(row.total_amount),liability:text(row.liability_status).replaceAll("_"," ")
      })),
    };
  }

  if (report.detailKind === "invoices") {
    const { data, error } = await supabase
      .from("billing_invoice")
      .select("id,patient_id,medical_scheme_id,medical_scheme_option_id,invoice_number,invoice_date,invoice_kind,status,total_amount,scheme_portion,patient_portion,received_amount,balance_amount,tax_amount,credited_amount,tax_invoice,source_system,reference")
      .eq("practice_id", practiceId)
      .order("invoice_date", { ascending:false })
      .limit(1000);
    if (error) throw error;
    let invoices=[...(data || [])] as any[];
    if (report.id === "outstanding-invoices") invoices=invoices.filter(row => Number(row.balance_amount)>0 && row.status!=="void");

    const [patients,schemes,options]=await Promise.all([
      lookupMap(supabase,"crm_patient",unique(invoices.map(row=>row.patient_id)),"display_name"),
      lookupMap(supabase,"medical_scheme",unique(invoices.map(row=>row.medical_scheme_id)),"name"),
      lookupMap(supabase,"medical_scheme_option",unique(invoices.map(row=>row.medical_scheme_option_id)),"option_name")
    ]);

    if(report.id==="invoice-activity-schemes") invoices.sort((a,b)=>text(schemes.get(a.medical_scheme_id)).localeCompare(text(schemes.get(b.medical_scheme_id))) || String(b.invoice_date).localeCompare(String(a.invoice_date)));

    return {
      title: report.legacyName,
      subtitle: report.id==="outstanding-invoices"
        ? "PracticeCtrl invoices with a positive outstanding balance; void invoices are excluded."
        : "PracticeCtrl invoice activity with payer, patient, status and financial outcome retained at source transaction level.",
      columns: report.id==="invoice-activity-schemes" ? [
        {key:"scheme",label:"Scheme"},{key:"plan",label:"Plan"},{key:"invoice",label:"Invoice"},{key:"date",label:"Date"},
        {key:"status",label:"Status"},{key:"total",label:"Total",align:"right"},{key:"received",label:"Received",align:"right"},{key:"balance",label:"Balance",align:"right"}
      ] : [
        {key:"invoice",label:"Invoice"},{key:"date",label:"Date"},{key:"patient",label:"Patient"},{key:"kind",label:"Kind"},
        {key:"status",label:"Status"},{key:"total",label:"Total",align:"right"},{key:"received",label:"Received",align:"right"},
        {key:"balance",label:"Balance",align:"right"},{key:"source",label:"Source"}
      ],
      rows: invoices.map(row => report.id==="invoice-activity-schemes" ? ({
        scheme:text(schemes.get(row.medical_scheme_id)),plan:text(options.get(row.medical_scheme_option_id)),invoice:text(row.invoice_number),
        date:shortDate(row.invoice_date),status:text(row.status).replaceAll("_"," "),total:amount(row.total_amount),
        received:amount(row.received_amount),balance:amount(row.balance_amount)
      }) : ({
        invoice:text(row.invoice_number),date:shortDate(row.invoice_date),patient:text(patients.get(row.patient_id)),kind:text(row.invoice_kind),
        status:text(row.status).replaceAll("_"," "),total:amount(row.total_amount),received:amount(row.received_amount),
        balance:amount(row.balance_amount),source:text(row.source_system)
      })),
    };
  }

  if (report.detailKind === "invoice-lines") {
    const { data: invoices, error: invoiceError } = await supabase
      .from("billing_invoice").select("id,invoice_number,invoice_date,status").eq("practice_id",practiceId).order("invoice_date",{ascending:false}).limit(750);
    if (invoiceError) throw invoiceError;
    const ids=(invoices||[]).map((row:any)=>row.id);
    if(!ids.length) return {title:report.legacyName,subtitle:"Claim-line and invoice-line detail.",columns:[{key:"invoice",label:"Invoice"}],rows:[]};
    const { data: lines, error } = await supabase
      .from("billing_invoice_line")
      .select("invoice_id,line_no,service_date,code_system,code,description_snapshot,modifier_codes,diagnosis_codes,quantity,line_amount,expected_contractual_amount,expected_scheme_amount,expected_patient_liability")
      .in("invoice_id",ids)
      .order("service_date",{ascending:false})
      .limit(2500);
    if(error) throw error;
    const invoiceMap=new Map((invoices||[]).map((row:any)=>[row.id,row]));
    return {
      title:report.legacyName,
      subtitle:"Line-level billing evidence, including procedure/coding context and expected reimbursement fields where they have been resolved.",
      columns:[
        {key:"invoice",label:"Invoice"},{key:"serviceDate",label:"Service date"},{key:"code",label:"Code"},{key:"description",label:"Description"},
        {key:"modifiers",label:"Modifiers"},{key:"diagnoses",label:"ICD-10"},{key:"qty",label:"Qty",align:"right"},
        {key:"lineAmount",label:"Line amount",align:"right"},{key:"expected",label:"Expected",align:"right"},{key:"patient",label:"Patient liability",align:"right"}
      ],
      rows:(lines||[]).map((row:any)=>({
        invoice:text(invoiceMap.get(row.invoice_id)?.invoice_number),serviceDate:shortDate(row.service_date),code:`${text(row.code_system)} · ${text(row.code)}`,
        description:text(row.description_snapshot),modifiers:(row.modifier_codes||[]).join(", ")||"—",diagnoses:(row.diagnosis_codes||[]).join(", ")||"—",
        qty:Number(row.quantity||0),lineAmount:amount(row.line_amount),expected:amount(row.expected_contractual_amount),patient:amount(row.expected_patient_liability)
      }))
    };
  }

  if (report.detailKind === "credit-notes") {
    const { data, error } = await supabase
      .from("billing_credit_note")
      .select("id,invoice_id,credit_note_number,credit_note_date,status,subtotal_amount,tax_amount,total_amount,reason,created_at")
      .eq("practice_id",practiceId)
      .order("credit_note_date",{ascending:false})
      .limit(1000);
    if(error) throw error;
    let notes=[...(data||[])] as any[];
    if(report.id==="credit-not-reinvoiced") notes=notes.filter(row=>row.status==="final");
    const invoiceIds=unique(notes.map(row=>row.invoice_id));
    const { data: invoices, error: invError } = invoiceIds.length
      ? await supabase.from("billing_invoice").select("id,invoice_number,patient_id,invoice_date,status").in("id",invoiceIds)
      : {data:[],error:null};
    if(invError) throw invError;
    const invoiceMap=new Map((invoices||[]).map((row:any)=>[row.id,row]));
    return {
      title:report.legacyName,
      subtitle: report.id==="credit-not-reinvoiced"
        ? "Final credit notes requiring replacement-invoice review. PracticeCtrl does not infer a replacement invoice from similarity; users must verify the subsequent billing trail."
        : "Credit-note register linked to the originating invoice, reason and tax amounts.",
      columns:[
        {key:"credit",label:"Credit note"},{key:"date",label:"Date"},{key:"invoice",label:"Source invoice"},
        {key:"status",label:"Status"},{key:"reason",label:"Reason"},{key:"subtotal",label:"Subtotal",align:"right"},
        {key:"tax",label:"Tax",align:"right"},{key:"total",label:"Total",align:"right"}
      ],
      rows:notes.map(row=>({
        credit:text(row.credit_note_number),date:shortDate(row.credit_note_date),invoice:text(invoiceMap.get(row.invoice_id)?.invoice_number),
        status:text(row.status),reason:text(row.reason),subtotal:amount(row.subtotal_amount),tax:amount(row.tax_amount),total:amount(row.total_amount)
      }))
    };
  }

  if (report.detailKind === "ledger") {
    const { data, error } = await supabase
      .from("billing_ledger_entry")
      .select("transaction_date,entry_type,document_number,description,signed_amount,source_key,invoice_id,credit_note_id,receipt_id,created_at")
      .eq("practice_id",practiceId)
      .order("transaction_date",{ascending:false})
      .limit(1500);
    if(error) throw error;
    return {
      title:report.legacyName,
      subtitle:"PracticeCtrl financial ledger activity. Reversals, adjustments and write-offs remain distinct entry types rather than being collapsed into an unexplained journal amount.",
      columns:[
        {key:"date",label:"Date"},{key:"type",label:"Entry type"},{key:"document",label:"Document"},
        {key:"description",label:"Description"},{key:"amount",label:"Signed amount",align:"right"},{key:"source",label:"Source"}
      ],
      rows:(data||[]).map((row:any)=>({
        date:shortDate(row.transaction_date),type:text(row.entry_type).replaceAll("_"," "),document:text(row.document_number),
        description:text(row.description),amount:amount(row.signed_amount),source:text(row.source_key)
      }))
    };
  }

  if (report.detailKind === "quotes") {
    const { data: quotes, error } = await supabase
      .from("billing_quote")
      .select("id,quote_number,quote_date,valid_until,status,total_amount,tax_amount,reference,converted_invoice_id,created_at")
      .eq("practice_id",practiceId)
      .order("quote_date",{ascending:false})
      .limit(1000);
    if(error) throw error;
    let selected=[...(quotes||[])] as any[];
    if(report.id==="proforma-uncommitted") selected=selected.filter(row=>!row.converted_invoice_id && !["void","rejected"].includes(row.status));
    if(report.id==="proforma-line"){
      const ids=selected.map(row=>row.id);
      const {data:lines,error:lineError}=ids.length
        ? await supabase.from("billing_quote_line").select("quote_id,line_no,code_system,code,description,quantity,unit_amount,tax_amount,line_amount").in("quote_id",ids).limit(2500)
        : {data:[],error:null};
      if(lineError) throw lineError;
      const qmap=new Map(selected.map(row=>[row.id,row]));
      return {
        title:report.legacyName,
        subtitle:"Quote/pro forma line detail. PracticeCtrl uses governed quotes and conversion state rather than a separate ambiguous pro-forma ledger.",
        columns:[
          {key:"quote",label:"Quote / pro forma"},{key:"date",label:"Date"},{key:"status",label:"Status"},{key:"code",label:"Code"},
          {key:"description",label:"Description"},{key:"qty",label:"Qty",align:"right"},{key:"tax",label:"Tax",align:"right"},{key:"amount",label:"Line amount",align:"right"}
        ],
        rows:(lines||[]).map((row:any)=>({
          quote:text(qmap.get(row.quote_id)?.quote_number),date:shortDate(qmap.get(row.quote_id)?.quote_date),
          status:text(qmap.get(row.quote_id)?.status),code:`${text(row.code_system)} · ${text(row.code)}`,
          description:text(row.description),qty:Number(row.quantity||0),tax:amount(row.tax_amount),amount:amount(row.line_amount)
        }))
      };
    }
    return {
      title:report.legacyName,
      subtitle: report.id==="proforma-uncommitted"
        ? "Quotes/pro formas that have not been converted to an invoice and have not been voided or rejected."
        : "Quote/pro forma activity with explicit conversion state into a final invoice.",
      columns:[
        {key:"quote",label:"Quote / pro forma"},{key:"date",label:"Date"},{key:"valid",label:"Valid until"},
        {key:"status",label:"Status"},{key:"reference",label:"Reference"},{key:"tax",label:"Tax",align:"right"},
        {key:"total",label:"Total",align:"right"},{key:"converted",label:"Converted"}
      ],
      rows:selected.map(row=>({
        quote:text(row.quote_number),date:shortDate(row.quote_date),valid:shortDate(row.valid_until),status:text(row.status),
        reference:text(row.reference),tax:amount(row.tax_amount),total:amount(row.total_amount),converted:row.converted_invoice_id?"Yes":"No"
      }))
    };
  }

  if (report.detailKind === "scheme-credits") {
    const { data, error } = await supabase
      .from("vericlaim_scheme_credit_snapshot")
      .select("scheme_name,account_ref,file_ref,invoice_number,scheme_credit_amount,created_at")
      .eq("practice_id",practiceId)
      .order("scheme_credit_amount",{ascending:false})
      .limit(1000);
    if(error) throw error;
    return {
      title:report.legacyName,
      subtitle:"Imported VeriClaim scheme-credit evidence retained separately from PracticeCtrl transactional billing.",
      columns:[
        {key:"scheme",label:"Scheme"},{key:"account",label:"Account"},{key:"file",label:"File"},
        {key:"invoice",label:"Invoice"},{key:"credit",label:"Scheme credit",align:"right"}
      ],
      rows:(data||[]).map((row:any)=>({
        scheme:text(row.scheme_name),account:text(row.account_ref),file:text(row.file_ref),invoice:text(row.invoice_number),credit:amount(row.scheme_credit_amount)
      }))
    };
  }

  if (report.detailKind === "receipts") {
    if(report.id==="financial-refunds"){
      const [{data:receipts,error:receiptError},{data:ledger,error:ledgerError}]=await Promise.all([
        supabase.from("billing_payment_receipt").select("receipt_date,receipt_number,payer_type,amount,payment_method,external_reference,source_system").eq("practice_id",practiceId).lt("amount",0).order("receipt_date",{ascending:false}).limit(500),
        supabase.from("billing_ledger_entry").select("transaction_date,entry_type,document_number,description,signed_amount,source_key").eq("practice_id",practiceId).in("entry_type",["allocation_reversal","adjustment"]).lt("signed_amount",0).order("transaction_date",{ascending:false}).limit(500)
      ]);
      if(receiptError) throw receiptError; if(ledgerError) throw ledgerError;
      const rows:ReportRow[]=[
        ...(receipts||[]).map((row:any)=>({date:shortDate(row.receipt_date),reference:text(row.receipt_number),type:"negative receipt / refund",payer:text(row.payer_type),amount:amount(row.amount),source:text(row.source_system)})),
        ...(ledger||[]).map((row:any)=>({date:shortDate(row.transaction_date),reference:text(row.document_number),type:text(row.entry_type).replaceAll("_"," "),payer:"—",amount:amount(row.signed_amount),source:text(row.source_key)}))
      ];
      return {
        title:report.legacyName,
        subtitle:"Refund/reversal evidence. PracticeCtrl distinguishes negative receipts from allocation reversals and adjustments instead of treating them as one opaque payment category.",
        columns:[{key:"date",label:"Date"},{key:"reference",label:"Reference"},{key:"type",label:"Type"},{key:"payer",label:"Payer"},{key:"amount",label:"Amount",align:"right"},{key:"source",label:"Source"}],
        rows:rows.sort((a,b)=>String(b.date).localeCompare(String(a.date)))
      };
    }
    const [{data:receipts,error:receiptError},{data:imports,error:importError}]=await Promise.all([
      supabase.from("billing_payment_receipt").select("receipt_date,receipt_number,payer_type,amount,payment_method,external_reference,source_system").eq("practice_id",practiceId).order("receipt_date",{ascending:false}).limit(750),
      supabase.from("vericlaim_funder_receipt").select("receipt_date,receipt_number,medical_scheme,receipt_amount,capture_date").eq("practice_id",practiceId).order("receipt_date",{ascending:false}).limit(750)
    ]);
    if(receiptError) throw receiptError; if(importError) throw importError;
    const rows:ReportRow[]=[
      ...(receipts||[]).map((row:any)=>({date:shortDate(row.receipt_date),receipt:text(row.receipt_number),payer:text(row.payer_type),scheme:"—",method:text(row.payment_method),amount:amount(row.amount),source:text(row.source_system)})),
      ...(imports||[]).map((row:any)=>({date:shortDate(row.receipt_date),receipt:text(row.receipt_number),payer:"scheme",scheme:text(row.medical_scheme),method:"—",amount:amount(row.receipt_amount),source:"VeriClaim import"}))
    ];
    return {
      title:report.legacyName,
      subtitle:"PracticeCtrl receipts plus imported funder-receipt evidence. Source-system identity is preserved.",
      columns:[{key:"date",label:"Date"},{key:"receipt",label:"Receipt"},{key:"payer",label:"Payer type"},{key:"scheme",label:"Scheme"},{key:"method",label:"Method"},{key:"amount",label:"Amount",align:"right"},{key:"source",label:"Source"}],
      rows:rows.sort((a,b)=>String(b.date).localeCompare(String(a.date)))
    };
  }

  if (report.detailKind === "vat") {
    const [{data:invoices,error:invoiceError},{data:credits,error:creditError}]=await Promise.all([
      supabase.from("billing_invoice").select("invoice_number,invoice_date,status,subtotal_amount,tax_amount,total_amount,tax_invoice,source_system").eq("practice_id",practiceId).or("tax_invoice.eq.true,tax_amount.gt.0").order("invoice_date",{ascending:false}).limit(1000),
      supabase.from("billing_credit_note").select("credit_note_number,credit_note_date,status,subtotal_amount,tax_amount,total_amount,reason").eq("practice_id",practiceId).gt("tax_amount",0).order("credit_note_date",{ascending:false}).limit(500)
    ]);
    if(invoiceError) throw invoiceError; if(creditError) throw creditError;
    const rows:ReportRow[]=[
      ...(invoices||[]).map((row:any)=>({date:shortDate(row.invoice_date),document:text(row.invoice_number),type:row.tax_invoice?"Tax invoice":"Invoice with tax",status:text(row.status),subtotal:amount(row.subtotal_amount),tax:amount(row.tax_amount),total:amount(row.total_amount)})),
      ...(credits||[]).map((row:any)=>({date:shortDate(row.credit_note_date),document:text(row.credit_note_number),type:"Credit note",status:text(row.status),subtotal:amount(row.subtotal_amount),tax:amount(row.tax_amount),total:amount(row.total_amount)}))
    ];
    return {
      title:report.legacyName,
      subtitle:"VAT/tax activity from final billing documents and credit notes. Whether the practice is VAT-registered remains a governed billing-profile setting.",
      columns:[{key:"date",label:"Date"},{key:"document",label:"Document"},{key:"type",label:"Type"},{key:"status",label:"Status"},{key:"subtotal",label:"Subtotal",align:"right"},{key:"tax",label:"Tax",align:"right"},{key:"total",label:"Total",align:"right"}],
      rows:rows.sort((a,b)=>String(b.date).localeCompare(String(a.date)))
    };
  }

  if (report.detailKind === "referrals") {
    const { data: referrals, error } = await supabase
      .from("crm_patient_referral")
      .select("id,patient_id,referral_source_id,referral_date,referral_reference")
      .eq("practice_id",practiceId)
      .order("referral_date",{ascending:false})
      .limit(1000);
    if(error) throw error;
    const patientIds=unique((referrals||[]).map((row:any)=>row.patient_id));
    const sourceIds=unique((referrals||[]).map((row:any)=>row.referral_source_id));
    const [patients,sources,{data:invoices,error:invoiceError}]=await Promise.all([
      lookupMap(supabase,"crm_patient",patientIds,"display_name"),
      lookupMap(supabase,"crm_referral_source",sourceIds,"name"),
      patientIds.length ? supabase.from("billing_invoice").select("patient_id,invoice_date,total_amount,status").eq("practice_id",practiceId).in("patient_id",patientIds).neq("status","void").limit(2500) : Promise.resolve({data:[],error:null})
    ]);
    if(invoiceError) throw invoiceError;
    return {
      title:report.legacyName,
      subtitle:"Referring-provider report derived from explicit referral records and subsequent non-void invoice activity for the referred patient. It does not infer a referrer where none was recorded.",
      columns:[{key:"date",label:"Referral date"},{key:"provider",label:"Referring provider"},{key:"patient",label:"Patient"},{key:"reference",label:"Referral reference"},{key:"invoices",label:"Invoices",align:"right"},{key:"value",label:"Invoice value",align:"right"}],
      rows:(referrals||[]).map((row:any)=>{
        const inv=(invoices||[]).filter((i:any)=>i.patient_id===row.patient_id && (!row.referral_date || String(i.invoice_date)>=String(row.referral_date)));
        return {date:shortDate(row.referral_date),provider:text(sources.get(row.referral_source_id)),patient:text(patients.get(row.patient_id)),reference:text(row.referral_reference),invoices:inv.length,value:amount(inv.reduce((sum:number,i:any)=>sum+Number(i.total_amount||0),0))};
      })
    };
  }

  throw new Error(`Unsupported report detail kind: ${report.detailKind || "none"}`);
}
