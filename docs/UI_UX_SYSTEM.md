# PracticeCtrl UI/UX System

This file is the authoritative implementation context for PracticeCtrl's interface. It applies to the existing product and workflows; it is not a request to rebuild the domain model.

## Product identity

PracticeCtrl — **Clinical Operations. Coding Intelligence. Revenue Integrity.**

Code10 is the embedded clinical coding engine. Tenant practices are operational contexts, not the product identity.

## Visual language

- Flat, professional, high-contrast clinical and financial workspace.
- No gradients, glass effects, glowing controls, floating decoration or AI-themed visual motifs.
- Deep navy is the structural colour.
- Teal is the restrained action/active-navigation accent.
- Bright blue is reserved for focus and limited selected-state emphasis.
- Main canvas is white/light neutral; panels use subtle borders with little or no shadow.
- Status colour is used only for meaningful states and is always accompanied by words.

### Brand-derived tokens

- Navy: `#051A39`
- Teal: `#029EA1`
- Accessible action teal: `#067C80`
- Focus blue: `#236CFB`
- Canvas: `#F6F8FA`
- Ink: `#12243B`
- Muted text: `#5B6B7D`
- Border: `#DCE3EA`

Approved supplied logo artwork must not be recoloured or recreated. Use the primary full-colour logo on light surfaces. Use approved white-on-navy artwork only on navy surfaces. The collapsed navigation must use approved icon artwork when the icon asset is available in the deployed repository.

## Information architecture

Primary mental model:

1. Today
2. Patients
3. Operations
4. Clinical & Code10
5. Billing
6. Claims
7. Revenue
8. Reports
9. Administration

Module links remain available within these groups and remain role-gated.

## Application shell

Desktop sidebar has three persistent states:

- **Expanded:** full labels and practice context.
- **Collapsed:** icon rail with accessible names/tooltips.
- **Hidden:** full-width work mode with an obvious navigation restore control.

The preference is stored per browser. Mobile navigation is an overlay. Sidebar changes must never reset page state or clip workbenches.

The top bar must make the active practice unmistakable and provide routes to patient/record search, attention items and account context.

## Page hierarchy

Every task page should provide:

1. One unmistakable page heading.
2. Patient/case identity and state when relevant.
3. Blocking issue or required decision.
4. Main work area.
5. Supporting evidence/history.
6. Secondary actions.

Dense tables are preferred over oversized cards where row comparison matters. Tables must remain legible and drill to source records.

## Shared workbench pattern

Use a consistent four-part model:

- Queue/list
- Main canvas
- Collapsible context/evidence panel
- Permitted action area

Disabled actions explain why they are disabled. Findings expose severity, reason, impact, source/version, affected record, resolution path and history.

## AI presentation

PracticeCtrl's intelligence is expressed through traceable findings, explanations and suggested actions. Do not use chatbot decoration, sparkle icons, glowing AI panels or anthropomorphic assistant language. AI outputs remain visibly suggestions until authorised human confirmation where required.

## Accessibility and daily-use requirements

- Strong body-text contrast; no pale-grey readability compromises.
- Visible keyboard focus.
- Status is never colour-only.
- Forms preserve entered data on validation/connectivity errors.
- Responsive layouts prioritise desktop workbenches while preserving mobile review/search/task actions.
- Consequential actions require clear confirmation and produce an auditable resulting state.

## Acceptance criteria

A representative user must be able to:

- identify their next task and why it requires attention;
- inspect a blocked claim's cause, evidence, owner and next step;
- resolve a finding and see workflow eligibility update;
- drill from payer/revenue aggregate to source transaction;
- answer a patient query from the longitudinal record and create follow-up;
- collapse/hide navigation and complete detailed work without losing context;
- switch practices deliberately without confusing tenant data.
