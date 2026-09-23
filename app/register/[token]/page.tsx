import type { Metadata } from "next";
import { PatientRegistrationForm } from "@/components/intake/PatientRegistrationForm";
export const metadata:Metadata={title:"Patient Registration | PracticeCtrl",robots:{index:false,follow:false},referrer:"no-referrer"};
export default async function RegistrationPage({params}:{params:Promise<{token:string}>}){const {token}=await params;return <PatientRegistrationForm token={token}/>}
