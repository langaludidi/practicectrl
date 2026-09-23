"use client";

import { type ChangeEvent, type FormEvent, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

type Mode = "loading" | "enroll" | "challenge" | "ready";

type Enrolment = {
  factorId: string;
  qrCode: string;
  secret: string;
};

export function MfaGate({ email }: { email: string | null }) {
  const router = useRouter();
  const [mode, setMode] = useState<Mode>("loading");
  const [enrolment, setEnrolment] = useState<Enrolment | null>(null);
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function inspectAal() {
    const supabase = createClient();
    const { data, error } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
    if (error) throw error;

    if (data.currentLevel === "aal2") {
      setMode("ready");
      router.replace("/dashboard");
      router.refresh();
      return;
    }

    if (data.nextLevel === "aal2") {
      setMode("challenge");
      return;
    }

    setMode("enroll");
  }

  useEffect(() => {
    inspectAal().catch(() => {
      setError("Unable to check multi-factor authentication status.");
      setMode("enroll");
    });
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function startEnrollment() {
    setBusy(true);
    setError(null);
    try {
      const supabase = createClient();
      const { data, error } = await supabase.auth.mfa.enroll({
        factorType: "totp",
        friendlyName: "PracticeCtrl",
      });
      if (error) throw error;
      setEnrolment({
        factorId: data.id,
        qrCode: data.totp.qr_code,
        secret: data.totp.secret,
      });
    } catch {
      setError("Could not start authenticator setup. Please try again.");
    } finally {
      setBusy(false);
    }
  }

  async function verifyEnrollment(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!enrolment) return;
    await verifyTotp(enrolment.factorId);
  }

  async function verifyExistingFactor(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const supabase = createClient();
      const factors = await supabase.auth.mfa.listFactors();
      if (factors.error) throw factors.error;
      const factor = factors.data.totp.find((item: { status: string; id: string }) => item.status === "verified");
      if (!factor) {
        setMode("enroll");
        setError("No verified authenticator factor was found. Set up MFA again.");
        return;
      }
      await verifyTotp(factor.id, false);
    } catch {
      setError("The authenticator code could not be verified.");
    } finally {
      setBusy(false);
    }
  }

  async function verifyTotp(factorId: string, manageBusy = true) {
    if (manageBusy) setBusy(true);
    setError(null);
    try {
      const supabase = createClient();
      const challenge = await supabase.auth.mfa.challenge({ factorId });
      if (challenge.error) throw challenge.error;
      const verify = await supabase.auth.mfa.verify({
        factorId,
        challengeId: challenge.data.id,
        code: code.trim(),
      });
      if (verify.error) throw verify.error;
      await supabase.auth.refreshSession();
      setMode("ready");
      router.replace("/dashboard");
      router.refresh();
    } catch {
      setError("That code was not accepted. Check your authenticator app and try again.");
    } finally {
      if (manageBusy) setBusy(false);
    }
  }

  if (mode === "loading" || mode === "ready") {
    return <p className="text-sm text-stone-600">Checking security status…</p>;
  }

  if (mode === "challenge") {
    return (
      <form onSubmit={verifyExistingFactor} className="space-y-4">
        <div>
          <p className="text-sm text-stone-700">
            Enter the six-digit code from your authenticator app to continue to PracticeCtrl.
          </p>
          {email && <p className="mt-1 text-xs text-stone-500">Signed in as {email}</p>}
        </div>
        <label className="block text-sm font-medium">
          Authenticator code
          <input
            value={code}
            onChange={(e: ChangeEvent<HTMLInputElement>) => setCode(e.target.value.replace(/\D/g, "").slice(0, 8))}
            inputMode="numeric"
            autoComplete="one-time-code"
            required
            className="mt-1 w-full rounded-xl border border-stone-300 bg-white px-3 py-2.5 tracking-[.25em]"
          />
        </label>
        {error && <p role="alert" className="rounded-lg bg-red-50 p-3 text-sm text-red-800">{error}</p>}
        <button disabled={busy || code.length < 6} className="w-full rounded-xl bg-[#4a1f3e] px-4 py-3 font-semibold text-white disabled:opacity-60">
          {busy ? "Verifying…" : "Verify and continue"}
        </button>
      </form>
    );
  }

  return (
    <div className="space-y-5">
      <div>
        <p className="text-sm text-stone-700">
          Multi-factor authentication is mandatory for practice staff before clinical or patient information can be changed.
        </p>
        {email && <p className="mt-1 text-xs text-stone-500">Signed in as {email}</p>}
      </div>

      {!enrolment ? (
        <button onClick={startEnrollment} disabled={busy} className="w-full rounded-xl bg-[#4a1f3e] px-4 py-3 font-semibold text-white disabled:opacity-60">
          {busy ? "Starting setup…" : "Set up authenticator app"}
        </button>
      ) : (
        <form onSubmit={verifyEnrollment} className="space-y-4">
          <div className="rounded-2xl border border-stone-200 bg-stone-50 p-4">
            <p className="mb-3 text-sm font-semibold text-[#4a1f3e]">1. Scan this QR code</p>
            <img src={enrolment.qrCode} alt="Authenticator enrollment QR code" className="mx-auto max-w-[220px] rounded-lg bg-white p-2" />
            <details className="mt-3 text-xs text-stone-600">
              <summary className="cursor-pointer font-medium">Can’t scan the QR code?</summary>
              <p className="mt-2 break-all font-mono">{enrolment.secret}</p>
            </details>
          </div>
          <label className="block text-sm font-medium">
            2. Enter the code from your authenticator app
            <input
              value={code}
              onChange={(e: ChangeEvent<HTMLInputElement>) => setCode(e.target.value.replace(/\D/g, "").slice(0, 8))}
              inputMode="numeric"
              autoComplete="one-time-code"
              required
              className="mt-1 w-full rounded-xl border border-stone-300 bg-white px-3 py-2.5 tracking-[.25em]"
            />
          </label>
          {error && <p role="alert" className="rounded-lg bg-red-50 p-3 text-sm text-red-800">{error}</p>}
          <button disabled={busy || code.length < 6} className="w-full rounded-xl bg-[#4a1f3e] px-4 py-3 font-semibold text-white disabled:opacity-60">
            {busy ? "Enabling MFA…" : "Enable MFA and continue"}
          </button>
        </form>
      )}

      {!enrolment && error && <p role="alert" className="rounded-lg bg-red-50 p-3 text-sm text-red-800">{error}</p>}
      <p className="text-xs leading-5 text-stone-500">
        Use a TOTP-compatible authenticator such as 1Password, Google Authenticator, Microsoft Authenticator or Apple Passwords. Supabase does not issue recovery codes, so a backup factor should be enrolled after initial setup.
      </p>
    </div>
  );
}
