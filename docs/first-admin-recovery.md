# First administrator recovery

PracticeCtrl uses a six-digit Supabase recovery OTP to set the first administrator's password. The OTP is entered on `/auth/recover?invite=<invitation-id>`. This works when an email app opens in a browser that does not share the session or PKCE verifier from the request browser.

## Hosted Supabase setting

In Authentication → Email Templates → Reset Password, replace the default recovery link template with the contents of [`supabase/templates/recovery.html`](../supabase/templates/recovery.html), then save it. The `{{ .Token }}` variable must remain exactly as written. The user requests one new email after this setting is saved; an email already sent retains its old content. Do not put setup codes or passwords in support chats or logs.

Supabase's built-in SMTP provider applies a shared project email rate limit. A 429 response requires waiting for that limit to clear. Do not repeatedly request emails. A custom SMTP provider is a separate later operational decision.

## Expected path

1. Request a code for the invited administrator's email on the URL carrying the invitation ID.
2. Enter the six digits from the newest recovery email on the same page. Supabase `verifyOtp` creates a browser session.
3. Choose and confirm a unique password of at least 12 characters on `/auth/set-password`.
4. Accept the pending invitation on `/onboarding/accept`. The app then sends the user to practice selection and MFA enrolment.

Verify each step using the resulting UI and the invitation status. Do not record the password, OTP, or auth tokens as evidence. A successfully delivered email alone does not prove that account setup or invitation acceptance succeeded.
