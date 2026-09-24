# First administrator recovery

PracticeCtrl works with Supabase's default Reset Password email. Custom SMTP and a custom email template are not required.

The recovery request uses a separate Supabase JS client configured for the implicit flow. It sends the existing allowlisted `/auth/callback?next=/auth/set-password?...` redirect. When the user opens the emailed link, Supabase places the access and refresh tokens in the URL fragment, which never reaches the server. The callback redirects to `/auth/finish`; the browser carries the fragment through that redirect. The finish page removes the fragment before creating the SSR client, validates the tokens with `setSession`, and then moves to the password form. This permits an email link to open in another browser without a PKCE verifier from the request browser.

## Verification sequence

1. Request one recovery email for the invited administrator at `/auth/recover?invite=<invitation-id>`.
2. Open the latest Reset Password link, including from another browser. Confirm `/auth/finish` reaches `/auth/set-password` without exposing tokens in the URL.
3. Set a unique password of at least 12 characters. Accept the invitation and complete MFA enrolment.
4. Confirm the invitation becomes accepted and the staff membership is active; then perform a fresh sign-in.

Supabase's built-in SMTP provider has a shared project email quota. If the request returns 429, wait for the limit to clear instead of retrying repeatedly. Do not record reset links, passwords, tokens, or OTPs as evidence. A successful build or delivered email alone does not prove account activation.
