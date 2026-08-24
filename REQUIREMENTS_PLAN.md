# CB Employee Hub — Functional and Non-Functional Requirements Plan

**Document status:** Implemented baseline and acceptance plan
**Product:** CB Employee Hub employee operations platform
**Backend:** InsForge project `CB Employee Hub`
**Clients:** Native iOS app first; native Android app later; no production web application
**Primary timezone:** Configurable per branch, default Asia/Karachi
**Cost constraint:** IP and GPS attendance validation must not require a paid maps or geolocation API

## 1. Purpose

CB Employee Hub will provide one controlled system for employee records, attendance, leave management, salary management, biometric enrollment, location validation, reporting, and administration.

The system must support multiple restaurant branches. Employees must mark attendance only through an authorized branch attendance device or while physically near an approved branch. It must remain operable during common Wi-Fi or GPS problems through controlled, fully audited remote manager overrides.

This document defines what the system must do, how well it must do it, the proposed InsForge architecture, delivery phases, and acceptance criteria. It does not claim that the requirements are already implemented.

## 2. Current Baseline

The current application includes:

- Node.js, Express, EJS, and SQLite web application.
- Admin login and optional kiosk PIN login.
- Employee create, update, activate, deactivate, and delete operations.
- Daily attendance with `present`, `absent`, and `leave` states.
- Manual and face-based attendance marking.
- Leave request, approval, and rejection workflows.
- A salary date field on employee records, but no salary calculation, payroll, payslip, or payment-tracking workflow.
- Face enrollment, verification, identification, and biometric logs.
- A partially implemented SwiftUI iOS client with iOS 26 Liquid Glass and older-iOS fallbacks.

The linked InsForge project now contains the versioned PostgreSQL schema, RLS policies, private document buckets, trusted attendance function, and imported SQLite business records. The native SwiftUI app uses this backend directly. The existing web application remains only a source-data and historical-flow reference; it is not the target production client.

## 3. Product Goals

1. Prevent ordinary attendance marking from outside an approved branch location.
2. Preserve a practical fallback when branch Wi-Fi, GPS, or a device is unavailable.
3. Make every attendance decision traceable to its actor, device, location evidence, and reason.
4. Keep iOS and the future Android app consistent through one server-authoritative backend contract.
5. Protect employee identity, CNIC, location, and biometric data.
6. Remove the operational dependency on a single local SQLite file.
7. Use built-in device location and local distance calculations without paid location APIs.
8. Calculate monthly salary from versioned compensation rules and approved attendance/leave inputs.
9. Produce reviewable payroll, payslips, payment status, and a complete salary audit trail.
10. Support any number of branches with branch-scoped employees, managers, attendance rules, leave rules, schedules, and reports.
11. Configure operational values in the mobile app instead of hardcoding coordinates, public IPs, schedules, or payroll dates.

## 4. Actors and Permissions

### 4.1 Owner/super administrator

- Has cross-branch access to employees, attendance, leave, salary, biometric profiles, locations, settings, reports, and audit logs.
- Can create and revoke manager access.
- Can create branches and configure coordinates, allowed public IPs, schedules, and attendance policy from the iOS app.
- Can perform audited manual attendance corrections and emergency overrides.
- Can configure compensation and payroll rules when also granted the payroll permission.

### 4.2 Manager

- Is assigned to one or more branches and can view only authorized branch operations.
- Can review leave requests if granted that permission.
- Can perform a remote emergency attendance override only for an assigned branch, with recent re-authentication, reason, and audit evidence.
- Cannot view or change employee salary unless separately granted payroll access.
- Cannot change security, retention, restaurant-location, or administrator settings unless separately authorized.

### 4.3 Payroll administrator

- Can manage compensation, salary components, pay periods, payroll drafts, approvals, payslips, and payment records.
- Can view the attendance and leave inputs required for payroll.
- Cannot change biometric or restaurant-location security settings unless separately authorized.
- Cannot erase approved payroll history.

### 4.4 Payroll approver

- Reviews payroll prepared by the payroll administrator.
- Can approve, reject, reopen, or void payroll according to policy.
- Recommended assignment: the owner/super administrator or a separately trusted finance approver.
- Should not prepare the same payroll run that they approve when staffing permits.

### 4.5 Branch attendance device

- Runs the iOS app in a locked, branch-scoped attendance mode after device registration.
- Can capture face, request location permission, and submit attendance evidence.
- Cannot access employee personal details, reports, settings, or biometric templates.
- Cannot manually select an employee to bypass biometric identification.

### 4.6 Employee

- Can have an InsForge Auth account for personal attendance, leave requests, attendance history, and payslips.
- Can mark attendance through the registered branch device or the authorized personal iOS flow.
- Can be identified only from an active, consented biometric profile.
- Can receive a generated payslip through an administrator-approved delivery method.

### 4.7 Auditor/read-only user (recommended)

- Can view reports, attendance history, configuration history, and audit events. Salary amounts require a separate payroll-auditor permission.
- Cannot modify operational or personal data.

## 5. Scope

### 5.1 Included

- InsForge authentication, Postgres database, row-level security, server-side attendance validation, and audit records.
- Multiple independently configurable restaurant branches.
- One native iOS app with role-based owner, manager, payroll, employee, and branch-device experiences.
- Employee management.
- Attendance check-in, check-out, absence, and leave states.
- Restaurant public-IP validation.
- GPS geofence validation using device location and a local Haversine calculation.
- Face enrollment and matching.
- Leave workflow.
- Compensation profiles and effective-dated salary history.
- Monthly payroll calculation using approved attendance and leave data.
- Allowances, bonuses, overtime, deductions, loans/advances, and manual adjustments.
- Payroll review, approval, locking, payslips, and payment-status tracking.
- Reports and CSV export.
- Manager emergency override.
- Data migration from SQLite to InsForge.

### 5.2 Excluded from the first production release

- Direct bank transfers, payment-gateway disbursement, or automatic bank-file submission.
- Government tax filing or automatic statutory reporting without separately approved legal rules.
- Full accounting/ERP integration.
- Shift rostering beyond basic attendance windows.
- Paid Google Maps, Apple Maps server APIs, reverse geocoding, or address lookup.
- Guaranteed detection of sophisticated GPS spoofing or presentation attacks.
- Fully offline employee attendance that synchronizes later without manager review.
- Public employee self-registration.
- Production web admin portal or browser kiosk.
- Android application in the first release; the backend contract must remain Android-ready.

### 5.3 Confirmed product decisions

- Branch coordinates are configured dynamically per branch in the app.
- Approved public IP addresses/ranges are configured dynamically per branch in the app.
- The initial geofence radius is 50 metres for every branch.
- The attendance location policy is `IP_OR_GPS`.
- Check-in, check-out, break, lateness, and overtime schedules are dynamic rather than hardcoded.
- Initial leave types are Sick Leave, Urgent Leave, and Normal Leave; their paid/unpaid treatment and entitlements remain configurable.
- Salary currency is PKR.
- Each employee has an individual joining date and first/last-period salary must be prorated from eligible employment days.
- Attendance, overtime, lateness, allowances, bonuses, loans, advances, and deduction rules are configurable.
- Payroll cutoff and payment schedule can vary by employee through assigned pay schedules.
- Managers may perform remote attendance overrides with branch permission, recent re-authentication, a reason, and a complete audit trail.
- Payroll uses maker-checker control: a Payroll Administrator prepares and an Owner/Super Administrator or separate Payroll Approver approves.
- PostgreSQL on InsForge is the system of record.
- iOS is the only production client in the first release; Android follows later and web is not a production target.

## 6. Functional Requirements

Priorities use **Must**, **Should**, and **Could**.

### 6.1 Authentication and access control

**FR-AUTH-001 — Administrator authentication — Must**
Administrators and managers must authenticate through InsForge Auth. Passwords must never be stored by the application.

Acceptance criteria:

- Valid active users can sign in and receive the correct role.
- Invalid credentials return a generic error that does not reveal whether an email exists.
- Disabled users cannot create new sessions.
- Logout invalidates the local session and clears sensitive cached data.

**FR-AUTH-002 — Role-based authorization — Must**
Every protected screen, API operation, database table, and realtime channel must enforce role permissions on the server and through InsForge RLS. Hiding a button in the client is not authorization.

**FR-AUTH-003 — Branch-device authentication — Must**
Branch-device mode must use a revocable, branch-scoped device registration. A shared PIN may be used only during transition and must be rate-limited, hashed, rotated, and restricted to attendance operations.

**FR-AUTH-004 — Session management — Must**
Sessions must expire after a configurable period, support explicit logout, and be revoked when the account or registered attendance device is disabled.

**FR-AUTH-005 — Account recovery — Should**
Administrators must be able to use InsForge's verified password-reset flow. Recovery must not depend on a default production password.

**FR-AUTH-006 — Employee authentication — Must**
Employees using the personal mobile flow must sign in through InsForge Auth. Public sign-up is disabled; accounts are invited or created through an authorized employee-onboarding workflow.

### 6.2 Multi-branch management

**FR-BR-001 — Branch lifecycle — Must**
The owner/super administrator must be able to create, edit, activate, and deactivate branches from the iOS app without a code deployment.

**FR-BR-002 — Branch configuration — Must**
Each branch must store a unique code, name, address, latitude, longitude, 50-metre geofence radius, timezone, public IP rules, schedules, attendance policy, and operational status.

**FR-BR-003 — Dynamic location setup — Must**
An authorized administrator must be able to set branch coordinates using the iPhone's current location or manually entered coordinates and verify them in a diagnostic flow before activation.

**FR-BR-004 — Dynamic public IP setup — Must**
The app must show the public IP observed by the trusted server and allow an authorized administrator to approve it for a selected branch. A detected IP must never become trusted automatically merely because a user is connected through it.

**FR-BR-005 — Branch-scoped access — Must**
Managers, payroll users, employees, and attendance devices must access only their assigned branches unless explicitly granted cross-branch permission. This must be enforced by InsForge RLS.

**FR-BR-006 — Employee branch assignment — Must**
Employees must have effective-dated branch assignments so transfers preserve historical attendance, leave, and payroll ownership.

**FR-BR-007 — Multi-branch assignment — Should**
An employee may be authorized for more than one branch with a primary branch and effective dates. Attendance must always record the branch at which it was accepted.

**FR-BR-008 — Branch dashboard and reports — Must**
Authorized users must switch between assigned branches and an allowed consolidated view. Every dashboard, report, approval queue, and export must respect the active branch scope.

**FR-BR-009 — Branch-specific policies — Must**
Schedules, leave policies, attendance windows, salary components, and approval assignments may use organization defaults with branch-specific overrides.

### 6.3 Employee management

**FR-EMP-001 — Employee record — Must**
The system must store a unique employee code, full name, role, position, employment status, phone, CNIC, address, joining date, salary date, and creation/update metadata.

**FR-EMP-002 — Create and update — Must**
Authorized administrators must be able to create and edit employees with server-side validation.

**FR-EMP-003 — Active/inactive lifecycle — Must**
Administrators must be able to deactivate an employee without deleting historical attendance, leave, audit, or biometric activity. Inactive employees cannot mark attendance.

**FR-EMP-004 — Uniqueness — Must**
Employee code must be unique. A supplied CNIC must be normalized and unique, while remaining optional if business policy permits.

**FR-EMP-005 — Search and filtering — Should**
The directory must support search by name, employee code, position, role, and status, with pagination for larger datasets.

**FR-EMP-006 — Destructive deletion — Should**
Normal operations should use deactivation. Permanent deletion must require administrator confirmation and follow retention rules.

### 6.4 Branch location configuration

**FR-LOC-001 — Branch locations — Must**
Administrators must be able to configure each branch with:

- Name and internal location code.
- Latitude and longitude.
- A 50-metre geofence radius.
- Maximum accepted GPS accuracy in metres.
- One or more approved public IPv4/IPv6 addresses or CIDR ranges.
- Timezone.
- Active/inactive status.

**FR-LOC-002 — Validation mode — Must**
The production default for each branch is `IP_OR_GPS`: an approved branch IP or valid in-radius GPS is sufficient. The policy model may also support administrator-controlled stricter modes:

- `IP_ONLY`
- `GPS_ONLY`
- `IP_OR_GPS` — confirmed production default
- `IP_AND_GPS` — optional strict mode

**FR-LOC-003 — Public IP validation — Must**
The server must determine the request IP through a correctly configured trusted proxy chain and compare its normalized value with the location allowlist. It must not trust an arbitrary client-supplied IP field.

**FR-LOC-004 — GPS validation — Must**
The iOS app must use Core Location. The server must calculate the distance to the selected branch using the Haversine formula. No maps or reverse-geocoding API is required.

**FR-LOC-005 — Location evidence quality — Must**
GPS evidence must include latitude, longitude, horizontal accuracy, capture time, and permission state. By default, evidence is valid only when:

- It is no older than 60 seconds.
- Horizontal accuracy is 50 metres or better.
- Calculated distance is within the branch's 50-metre radius.

The final thresholds must be calibrated at the actual restaurant before launch.

**FR-LOC-006 — Server-authoritative result — Must**
The client may collect evidence but cannot decide whether the employee is on-site. The server must return the final result and reason code.

**FR-LOC-007 — Configuration history — Must**
Every change to coordinates, radius, public IP, policy, or accuracy threshold must record the old value, new value, administrator, and timestamp.

**FR-LOC-008 — Location diagnostic — Should**
An administrator-only branch diagnostic must show the public IP detected by the server, GPS accuracy, calculated distance, active policy, and pass/fail reason without creating attendance. It must support an audited “approve this IP for this branch” action.

### 6.5 Attendance capture and decision flow

**FR-ATT-001 — Server-issued attendance attempt — Must**
Every attendance operation must start with a short-lived server-issued attempt ID tied to the employee, selected branch, app/device session, and creation time.

**FR-ATT-002 — Face identification — Must**
The iOS attendance flow must capture exactly one face, validate basic lighting and liveness signals, and submit a normalized descriptor for server-side matching against active enrolled employees authorized for the selected branch.

**FR-ATT-003 — Verification proof — Must**
After a successful face match, the server must issue a single-use, signed or server-stored verification proof bound to:

- Attendance attempt ID.
- Employee ID.
- App/device session and selected branch.
- Face-match result.
- Location decision.
- Short expiry, recommended two minutes.

Attendance confirmation must reject a plain employee ID without this proof. Reusing an already consumed or expired proof must fail.

**FR-ATT-004 — Location decision — Must**
The attendance attempt must evaluate the configured location policy before the attendance record is written.

For the recommended `IP_OR_GPS` policy:

1. If the request comes from an approved public IP for the selected branch, accept the location as `ip_verified`.
2. Otherwise request current GPS evidence.
3. If GPS passes freshness, accuracy, and distance checks, accept as `gps_verified`.
4. Otherwise reject ordinary attendance and offer the manager-override workflow.

**FR-ATT-005 — Atomic attendance write — Must**
The server must consume the verification proof, create/update attendance, and create audit evidence in one database transaction. Partial writes are not acceptable.

**FR-ATT-006 — Check-in and check-out — Must**
The first valid mark of the business day records check-in. A later valid mark records check-out. The response must clearly state which action occurred.

**FR-ATT-007 — Duplicate protection — Must**
Repeated submissions caused by double taps, retries, or network timeouts must not create duplicate events. The request must use an idempotency key or unique proof.

**FR-ATT-008 — Attendance states — Must**
The system must support `present`, `absent`, and `leave`, while preserving separate check-in/check-out event history. Manual corrections must not erase original events.

**FR-ATT-009 — Business date — Must**
The server must calculate the attendance date using the configured restaurant timezone, not the device clock. Cross-midnight shifts must have an explicit business-day rule.

**FR-ATT-010 — Employee eligibility — Must**
Only active employees with a valid biometric profile can use face attendance. Approved leave and employment status must be evaluated before writing the mark.

**FR-ATT-011 — Clear rejection reasons — Must**
The client must receive safe reason codes such as `IP_NOT_ALLOWED`, `GPS_PERMISSION_DENIED`, `GPS_TOO_OLD`, `GPS_INACCURATE`, `OUTSIDE_RADIUS`, `FACE_NOT_RECOGNIZED`, `PROOF_EXPIRED`, or `EMPLOYEE_INACTIVE`.

**FR-ATT-012 — Today log — Must**
Branch-device mode must show a privacy-minimized list of recent successful marks for its branch and current day without exposing CNIC, address, salary information, or biometric data.

**FR-ATT-013 — Dynamic schedules — Must**
Authorized users must configure branch schedule templates containing check-in, check-out, breaks, grace periods, late thresholds, early-departure rules, overtime windows, working days, holidays, and cross-midnight behavior.

**FR-ATT-014 — Employee schedule assignment — Must**
Each employee must be assigned an effective-dated schedule. An authorized employee-specific override may replace the branch template without changing historical calculations.

**FR-ATT-015 — Branch attribution — Must**
Every attendance attempt, event, daily summary, correction, and override must store the branch ID and policy/schedule versions used.

**FR-ATT-016 — Nearest authorized branch — Should**
For an employee assigned to multiple branches, the iOS app should suggest the nearest authorized branch, while requiring the server to validate the final selected branch.

### 6.6 Wi-Fi, GPS, and emergency fallback

**FR-FBK-001 — GPS fallback — Must**
When branch Wi-Fi is unavailable or the public IP has changed, an employee may mark attendance using mobile data only if GPS validation succeeds and the location policy permits GPS.

**FR-FBK-002 — Manager override — Must**
An authorized manager or administrator may record attendance remotely when both IP and GPS validation fail for a legitimate operational reason. The manager does not need to pass the employee geofence but must be authorized for that branch.

The override must require:

- Employee selection.
- Check-in/check-out action.
- Standard reason code, such as Wi-Fi outage, GPS failure, device failure, or approved correction.
- Mandatory written note.
- Re-authentication or a recent privileged session.
- Actor identity, timestamp, device, observed IP, and available GPS evidence.
- Selected branch, manager's assigned-branch permission, and a notification visible to the owner/super administrator.

**FR-FBK-003 — Time-limited emergency mode — Should**
An administrator may enable an emergency mode for one restaurant for a maximum configurable period, recommended 30 minutes. It must expire automatically and produce a prominent audit event.

**FR-FBK-004 — No silent offline synchronization — Must**
Attendance captured without server validation must not silently become official later. Offline entries must remain pending and require manager review, or the client must direct the user to the override process.

### 6.7 Biometric management

**FR-BIO-001 — Consent before enrollment — Must**
Face enrollment must require recorded employee consent or another approved lawful basis defined by the business.

**FR-BIO-002 — Controlled enrollment — Must**
Only administrators can enroll, replace, or remove a face profile. Enrollment must capture one employee at a time and reject invalid descriptor shapes.

**FR-BIO-003 — Match threshold — Must**
The matching threshold must be centrally configured, versioned, and tested against representative staff conditions. Clients cannot choose the threshold.

**FR-BIO-004 — Liveness — Must**
The client must perform the supported local liveness challenge, such as blink or controlled head movement, and the server must require a positive result. The plan must acknowledge that basic client-side liveness reduces casual photo attacks but does not guarantee advanced anti-spoofing.

**FR-BIO-005 — Biometric minimization — Must**
Store only the face descriptor/template required for matching, not routine attendance photos or video. Any diagnostic image retention must be separately approved, time-limited, and access-controlled.

**FR-BIO-006 — Removal and retention — Must**
Biometric profiles must be removable when employment ends, consent is withdrawn, or retention expires, without deleting historical attendance audit records.

**FR-BIO-007 — Biometric audit log — Must**
Enrollment, replacement, deletion, successful match, failed match, and threshold/configuration changes must be logged without writing raw descriptors into logs.

### 6.8 Manual attendance administration

**FR-MAN-001 — Manual marking — Must**
Authorized administrators can mark or correct attendance from the admin portal without being at the restaurant, if business policy permits. Every manual change must include a reason and audit record.

**FR-MAN-002 — Correction history — Must**
Corrections must append a new revision/event and preserve the original value, actor, reason, and timestamp.

**FR-MAN-003 — Bulk absence — Should**
The system may mark unrecorded active employees absent after a configurable cutoff. This must be previewed and confirmed, and must not override approved leave.

### 6.9 Leave management

**FR-LEV-001 — Leave request — Must**
Employees and authorized managers must be able to create a leave request containing branch, leave type, start/end date, full-day or partial-day duration, reason, requester, and status.

**FR-LEV-002 — Review — Must**
Authorized reviewers must approve or reject pending leave. The system must record reviewer and review time.

**FR-LEV-003 — Date validation — Must**
End date cannot precede start date. Overlapping pending or approved requests must be prevented or explicitly resolved.

**FR-LEV-004 — Attendance integration — Must**
Approved leave must appear in daily attendance and cannot be silently overwritten by an automated absence process.

**FR-LEV-005 — Review history — Should**
Changes to a leave decision must retain the previous decision and reason.

**FR-LEV-006 — Initial leave types — Must**
The system must initially provide Sick Leave, Urgent Leave, and Normal Leave. Authorized administrators may add, deactivate, or version additional leave types without a code deployment.

**FR-LEV-007 — Paid/unpaid policy — Must**
Each leave type must have configurable paid, unpaid, or partially paid treatment, entitlement, evidence requirement, notice period, approval chain, and branch applicability. No type's salary treatment may be assumed in code.

**FR-LEV-008 — Leave balances — Must**
Where entitlement applies, the system must calculate opening, accrued, used, adjusted, and remaining balances and preserve an auditable ledger.

**FR-LEV-009 — Branch approval — Must**
Leave requests must route to an authorized manager for the employee's effective branch, with escalation to an owner/super administrator when configured.

**FR-LEV-010 — Payroll cutoff handling — Must**
A leave decision completed after the relevant employee payroll cutoff must create a visible payroll exception or future adjustment rather than silently changing approved payroll.

### 6.10 Salary and payroll management

**FR-SAL-001 — Compensation profile — Must**
Authorized payroll administrators must be able to assign each employee a salary profile containing PKR currency, pay frequency, base salary, effective date, joining date reference, assigned pay schedule, and active status.

**FR-SAL-002 — Effective-dated salary history — Must**
Salary changes must create a new effective-dated version. Previous salary values, dates, actor, approval, and reason must remain available for audit and historical payroll reproduction.

**FR-SAL-003 — Salary components — Must**
The system must support configurable earning and deduction components, including recurring allowances, bonuses, overtime, unpaid absence, unpaid leave, lateness, tax/manual deductions, loans, advances, and other approved adjustments.

**FR-SAL-004 — Pay periods — Must**
Payroll administrators must manage reusable pay schedules and pay periods with start date, end date, attendance cutoff rule, payment-day rule, and lifecycle status. Employees may have different assigned schedules/cutoffs.

**FR-SAL-005 — Attendance integration — Must**
Payroll calculation must use the approved attendance snapshot for the pay period, including payable days, absences, lateness, overtime, and manual attendance corrections according to configured rules.

**FR-SAL-006 — Leave integration — Must**
Approved leave must be classified as paid or unpaid according to policy. Pending, rejected, or overlapping leave must not silently change salary.

**FR-SAL-007 — Configurable salary formula — Must**
The server must calculate salary using versioned business rules. The baseline formula is:

`gross earnings = base salary + recurring allowances + variable earnings + overtime + bonuses`

`net salary = gross earnings - attendance/leave deductions - loans/advances - tax/other deductions`

The precise day-rate, overtime, lateness, rounding, and deduction rules require owner approval and must not be hardcoded into clients.

**FR-SAL-008 — Payroll draft generation — Must**
An authorized payroll administrator must be able to generate a payroll draft for all eligible employees or a selected branch/employee group.

**FR-SAL-009 — Calculation breakdown — Must**
Every payroll item must show base salary, attendance inputs, leave inputs, each earning, each deduction, gross salary, total deductions, and net salary.

**FR-SAL-010 — Preview and validation — Must**
Before approval, the system must highlight missing salary profiles, incomplete attendance, pending leave, negative net pay, duplicate components, and other calculation exceptions.

**FR-SAL-011 — Payroll input snapshot — Must**
Generating or submitting a payroll run for approval must preserve the exact compensation, attendance, leave, and policy versions used. Later source changes must not silently alter an approved result.

**FR-SAL-012 — Review and approval — Must**
Payroll must follow `draft`, `under_review`, `approved`, `paid`, and `void` or equivalent controlled states. Only authorized approvers can approve a run.

**FR-SAL-013 — Locking and correction — Must**
Approved payroll is locked. Reopening or voiding it requires elevated permission, a reason, and an audit event. Changes after locking must use an approved adjustment or controlled reopen workflow.

**FR-SAL-014 — Payslip generation — Must**
The system must generate a clear payslip for each approved payroll item showing the employee, period, earnings, deductions, net salary, payment status, and employer details. Payslips must be private.

**FR-SAL-015 — Payment tracking — Must**
Authorized users must record `unpaid`, `processing`, `paid`, `partially_paid`, `failed`, or `void` status, payment date, method, amount, and reference. Recording status does not itself transfer money.

**FR-SAL-016 — Partial and carried adjustments — Should**
The system should support partial payments and approved adjustments carried into the next open pay period.

**FR-SAL-017 — Salary reports — Must**
Authorized payroll users must be able to report by pay period, employee, branch, department/role, payment status, earning type, deduction type, and net amount.

**FR-SAL-018 — Payroll export — Should**
Payroll summaries and payment lists should export to CSV. Detailed salary exports require payroll permission and must be audited.

**FR-SAL-019 — Salary confidentiality and audit — Must**
Salary views, changes, calculations, approvals, exports, payslips, and payment updates must be protected by dedicated permissions and recorded in the audit trail.

**FR-SAL-020 — Joining-date proration — Must**
An employee's first payroll period must begin on their individual joining date. The recommended calculation uses eligible scheduled working days from joining date through period end divided by scheduled working days in the full period. Final day-rate policy remains configurable and versioned.

**FR-SAL-021 — Dynamic calculation rules — Must**
Overtime, lateness, early departure, absence, allowances, bonuses, loans, advances, tax/manual deductions, rounding, and minimum/maximum rules must be configurable by organization or branch with approved employee-specific overrides.

**FR-SAL-022 — Maker-checker approval — Must**
A Payroll Administrator prepares payroll. An Owner/Super Administrator or separate Payroll Approver approves it. The same user must not prepare and approve the same run unless an explicitly audited small-business exception is enabled.

**FR-SAL-023 — Branch payroll — Must**
Payroll runs must support one branch, selected branches, or an authorized consolidated group while keeping every payroll item attributed to the employee's effective branch and pay schedule.

### 6.11 Dashboard, reporting, and export

**FR-RPT-001 — Daily dashboard — Must**
The dashboard must show active employees, present, absent, on leave, not yet marked, pending leave requests, biometric enrollment coverage, and recent failures. Payroll-authorized users must also see open pay periods, payroll exceptions, approvals awaiting action, and payment status.

**FR-RPT-002 — Attendance report — Must**
Authorized users must filter attendance by date range, employee, role, branch, status, mark method, and override status.

**FR-RPT-003 — Export — Should**
Reports must export to CSV with applied filters and export metadata. Exports containing CNIC or sensitive location details require elevated permission.

**FR-RPT-004 — Location and override report — Must**
The system must report IP-verified marks, GPS-verified marks, overrides, rejected attempts, and common rejection reasons.

**FR-RPT-005 — Audit search — Must**
Administrators and auditors must search audit events by actor, employee, action, location, device, date, and outcome.

### 6.12 iOS branch-device mode requirements

**FR-DEV-001 — Camera and location permissions — Must**
Branch-device mode must explain why camera and location are needed before triggering iOS permission prompts.

**FR-DEV-002 — Device-mode reset — Must**
After each attendance attempt, branch-device mode must clear employee-specific state and return to a neutral screen within a short configurable period.

**FR-DEV-003 — Locked operational state — Must**
The active capture controls and status must remain usable without exposing admin navigation. Leaving branch-device mode requires an authorized manager or device credential.

**FR-DEV-004 — Network recovery — Must**
Branch-device mode must distinguish offline, timeout, location rejection, and biometric rejection. It may retry safely using the same idempotency key.

**FR-DEV-005 — Branch binding — Must**
Each attendance device must be registered to one active branch. Reassignment requires an authorized user and an audit event.

**FR-DEV-006 — Guided Access readiness — Should**
Branch-device mode should work correctly with iOS Guided Access and prevent sensitive notifications or admin content from appearing during employee use.

### 6.13 Native iOS requirements

**FR-IOS-001 — Shared backend contract — Must**
The iOS app must use the same InsForge-backed rules planned for the future Android app. It must not contain a separate attendance or payroll decision engine.

**FR-IOS-002 — Core Location — Must**
The iOS app must request when-in-use location permission only when needed, display permission guidance, and submit accuracy and timestamp with coordinates.

**FR-IOS-003 — Secure session storage — Must**
Authentication tokens must be stored in Keychain, not `UserDefaults`, source code, logs, or screenshots.

**FR-IOS-004 — Liquid Glass compatibility — Must**
Use native Liquid Glass only behind `#available(iOS 26, *)`, with accessible material-based fallbacks on iOS 17–25.

**FR-IOS-005 — Environment configuration — Must**
The InsForge URL and anon key must come from build configuration. The project admin API key must never be bundled in the app.

**FR-IOS-006 — Error and retry behavior — Must**
The app must show actionable authentication, network, permission, location, and server errors and prevent duplicate attendance during retry.

**FR-IOS-007 — Salary privacy — Must**
Salary screens and payslips must appear only for payroll-authorized sessions, hide sensitive amounts from app-switcher snapshots where practical, and clear cached salary data on logout.

**FR-IOS-008 — Role-based application — Must**
One iOS application must present owner, manager, payroll, employee, and branch-device experiences based on server-issued permissions rather than separate hardcoded applications.

**FR-IOS-009 — Dynamic configuration — Must**
Authorized users must manage branches, coordinates, public IP rules, 50-metre geofences, schedules, leave types, employee pay schedules, and payroll rules from the iOS app.

### 6.14 Audit and administration

**FR-AUD-001 — Append-only audit trail — Must**
Security and business-critical events must be append-only for normal application roles. Events include login, logout, failed login, employee changes, biometric actions, attendance attempts, attendance corrections, leave decisions, compensation changes, payroll generation/approval/reopen/void, payslip access, payment updates, location configuration changes, exports, emergency mode, and permission changes.

**FR-AUD-002 — Evidence fields — Must**
Attendance audit evidence must include:

- Attempt and attendance IDs.
- Employee and actor IDs.
- Branch and policy version.
- Observed public IP, normalized for comparison.
- GPS coordinates when used, accuracy, age, and calculated distance.
- Location method and reason code.
- Device/session identifier.
- Biometric outcome and model/threshold version, but not raw descriptor.
- Server timestamp and business date.

**FR-AUD-003 — Sensitive-field redaction — Must**
Logs and standard audit views must redact credentials, session tokens, raw biometric descriptors, and unnecessary personal data.

**FR-AUD-004 — Configuration management — Must**
Administrators must manage restaurant settings, attendance windows, location policy, override permissions, biometric threshold, payroll rules, and retention periods through authorized, audited operations.

## 7. Core Business Rules

1. Server time and the selected branch timezone are authoritative.
2. Inactive employees cannot mark attendance.
3. A successful face match is not sufficient by itself; valid location evidence and a single-use proof are also required.
4. A client-supplied employee ID, IP, distance, or `locationPassed` flag is never trusted by itself.
5. One daily attendance summary may exist per employee per business date, but all check-in, check-out, correction, and override events are preserved.
6. Approved leave takes precedence over automated absence.
7. Manual and emergency overrides are never hidden or relabeled as biometric marks.
8. Branch-device mode cannot read biometric templates or sensitive employee fields.
9. Admin/API keys remain server-only. The iOS app and future Android app use only the InsForge anon key and user-scoped sessions.
10. All writes must respect database constraints, SQL privileges, and RLS policies.
11. Salary changes are effective-dated; historical payroll must continue to use the compensation version that applied to its pay period.
12. Attendance and leave inputs are snapshotted when payroll is submitted for approval. Later corrections create an adjustment or require an audited reopen.
13. Approved payroll cannot be edited directly, and only approved payroll can be marked paid.
14. All monetary values use a fixed-precision representation and an explicit currency; binary floating-point is prohibited for stored or calculated salary amounts.
15. Salary payment status records what occurred outside the system and does not claim that the application transferred funds.
16. Every operational record is branch-scoped or explicitly organization-wide; missing branch scope must fail closed.
17. Branch coordinates, IP rules, schedules, and payroll settings are dynamic configuration with versioned audit history.
18. The accepted attendance location policy is branch IP or GPS within 50 metres; remote manager override is a separately labeled exception.

## 8. Proposed InsForge Data Model

The precise SQL will be defined in migrations, but the minimum logical entities are:

- `profiles` — application identity and organization-level role/status linked to `auth.users(id)`.
- `branches` — branch code, name, address, coordinates, 50-metre radius, timezone, and operational status.
- `branch_memberships` — branch-scoped roles and permissions for users.
- `employees` — employee identity and employment information.
- `employee_branch_assignments` — effective-dated primary and secondary branch assignments.
- `branch_policy_versions` — versioned attendance, leave, payroll, and approval configuration.
- `location_ip_rules` — approved IPv4/IPv6 addresses or CIDR ranges.
- `attendance_devices` — branch-scoped, revocable iOS device registrations.
- `schedule_templates` — versioned branch working days, check-in/out, breaks, grace, overtime, and holidays.
- `employee_schedule_assignments` — effective-dated schedule assignment and employee overrides.
- `attendance_attempts` — short-lived capture, biometric, and location decision state.
- `attendance_events` — immutable check-in, check-out, correction, and override events.
- `attendance_daily` — one derived/current daily summary per employee and date.
- `leave_requests` — leave lifecycle.
- `leave_type_versions` — Sick, Urgent, Normal, and future leave rules including paid/unpaid treatment.
- `leave_balance_ledger` — employee entitlement, accrual, usage, and adjustments.
- `compensation_versions` — effective-dated base salary, currency, frequency, and approval history.
- `salary_component_definitions` — versioned earning and deduction types with calculation rules.
- `employee_salary_components` — recurring employee-specific allowances, deductions, loans, or advances.
- `pay_schedules` — reusable employee-specific cutoff and payment-day rules.
- `pay_periods` — payroll date range, cutoff, payment date, and lifecycle.
- `payroll_runs` — grouped draft, review, approval, lock, payment, and void state.
- `payroll_items` — employee-level salary calculation and frozen input snapshot.
- `payroll_item_components` — itemized earnings, deductions, formulas, quantities, and rates.
- `payroll_adjustments` — approved corrections carried into a current or future period.
- `salary_payments` — payment status, amount, method, reference, and reconciliation data.
- `payslip_documents` — private payslip metadata and storage key when files are persisted.
- `face_profiles` — protected biometric descriptor and algorithm version.
- `audit_events` — append-only security and configuration history.
- `emergency_windows` — time-limited override state.
- `app_settings` or versioned policy tables — server-owned business configuration.

Required relationships and constraints include:

- Application user profiles reference `auth.users(id)`.
- Employee code and non-null normalized CNIC are unique.
- All branch-owned tables include a non-null `branch_id` and indexes that begin with branch scope for common queries.
- Branch and schedule assignments are effective-dated and cannot have ambiguous overlaps.
- Face profile is unique per employee.
- Daily attendance is unique per employee, location, and business date as required by policy.
- Compensation versions for one employee cannot have ambiguous overlapping effective periods.
- A payroll item is unique per employee and payroll run.
- Payroll component and total values use fixed-precision database types with explicit currency.
- Approved/paid payroll records and payment history cannot be modified through ordinary client roles.
- Event and audit tables retain history when an employee is deactivated.
- Foreign keys, check constraints, indexes, grants, and RLS are created in migrations.

### 8.1 Selected technical architecture

The recommended production stack is:

- **Database and backend platform:** InsForge managed PostgreSQL as the sole system of record.
- **Authentication and authorization:** InsForge Auth, SQL grants, and branch-aware PostgreSQL RLS.
- **iOS client:** Native SwiftUI targeting iOS 17+, using Swift concurrency, Observation, Keychain, Core Location, AVFoundation, Vision/Core ML where approved, and native Liquid Glass guarded for iOS 26.
- **iOS backend client:** The official InsForge Swift SDK, pinned to a tested release. Use typed `Codable` models, direct RLS-protected reads for safe data, and RPC/functions for sensitive writes.
- **Privileged business logic:** PostgreSQL functions for atomic attendance/payroll transactions and InsForge TypeScript/Deno edge functions for request-IP inspection, orchestration, proof issuance, payslip generation, and other server-only work.
- **Documents:** Private InsForge Storage for generated payslips, storing both the private object key and metadata. No public salary-document URLs.
- **Updates:** Targeted InsForge Realtime events for branch dashboards and approval status; no unbounded polling.
- **Local mobile data:** Keychain for credentials and minimal ephemeral caching. Attendance and payroll never become official from an offline-only local record.
- **Future Android client:** Native Kotlin/Jetpack Compose using the same versioned backend contracts, RLS, RPCs, and functions; Android implementation is deferred.
- **Legacy runtime:** Node/Express/EJS/SQLite is retained temporarily only for source-data export, migration verification, and flow comparison, then removed from the production path.

The app should use a feature-oriented architecture with separate modules for authentication, branches, employees, attendance, leave, payroll, reports, and settings. Business decisions remain on the server; SwiftUI views render state and collect permitted evidence.

## 9. Server-Side Attendance Transaction

The recommended no-paid-API flow is:

1. The employee or registered branch device authenticates and requests an attendance attempt for an authorized branch.
2. The server records the trusted request IP, selected branch, user, and device.
3. Client captures camera and, when required, GPS evidence.
4. Server validates face, liveness signal, employee status, IP, GPS freshness, GPS accuracy, and Haversine distance.
5. Server issues a short-lived single-use verification proof only when all configured checks pass.
6. Client confirms the action.
7. A protected InsForge database function or server endpoint atomically consumes the proof, writes the attendance event, updates the daily summary, and appends audit evidence.
8. Realtime may notify the branch device and authorized branch dashboards of the successful mark.

This design incurs no maps or geolocation API cost. Core Location, request-IP inspection, and Haversine calculations do not require a paid API.

## 10. Non-Functional Requirements

### 10.1 Security

**NFR-SEC-001 — Defense in depth — Must**
Authentication, server authorization, SQL grants, RLS, validation, constraints, rate limits, and audit controls must all be applied. No single client-side control is sufficient.

**NFR-SEC-002 — Secret handling — Must**
InsForge admin/API keys, attendance-device secrets, and signing secrets must remain in server-side secrets. They must never be committed, bundled into iOS, exposed through public environment variables, or written to logs.

**NFR-SEC-003 — Transport security — Must**
Production traffic must use HTTPS. Authentication tokens must be held by the official InsForge Swift SDK and protected with Keychain-backed storage; no production cookie-based web session is required.

**NFR-SEC-004 — Rate limits — Must**
Apply rate limits to login, branch-device registration/unlock, face identification, attendance confirmation, password reset, location diagnostics, remote overrides, and payroll actions. Initial targets:

- Admin login: 5 failed attempts per account/IP per 15 minutes before cooldown.
- Branch-device unlock: 10 failed attempts per device/IP per 15 minutes.
- Face attempts: configurable per device and employee, with escalating cooldown.

**NFR-SEC-005 — Input protection — Must**
All inputs must be schema-validated. The server must reject untrusted branch, role, IP, distance, salary total, or approval fields and avoid returning detailed internal errors.

**NFR-SEC-006 — Abuse resistance — Must**
Attendance proofs must be short-lived, single-use, non-predictable, and bound to session/device. Replay and employee-ID substitution must fail.

**NFR-SEC-007 — Privileged changes — Must**
Location, biometric, role, salary, payroll approval, payment status, retention, export, and emergency-mode changes require an authorized role and an audit record. High-risk changes should require recent re-authentication.

### 10.2 Privacy and data protection

**NFR-PRV-001 — Data minimization — Must**
Collect only fields required for employment, attendance, leave, and salary operations. Do not continuously track employee location; collect it only during an attendance attempt or diagnostic explicitly initiated by an administrator.

**NFR-PRV-002 — Purpose limitation — Must**
GPS and biometric evidence must be used only for attendance/security purposes disclosed to employees.

**NFR-PRV-003 — Retention — Must**
The owner must approve retention periods for attendance, location evidence, failed attempts, audit logs, and biometric templates before production launch. Automated cleanup must preserve legally or operationally required audit history.

**NFR-PRV-004 — Restricted sensitive fields — Must**
CNIC, address, biometric profiles, detailed GPS evidence, compensation, payroll, payslips, and payment references must have narrower access than normal attendance summaries.

**NFR-PRV-005 — Consent and policy — Must**
The business must provide a clear employee notice and obtain appropriate consent or another valid basis for biometric and location processing. Local legal review is an owner responsibility before launch.

### 10.3 Data integrity and consistency

**NFR-DAT-001 — Transactionality — Must**
Attendance proof consumption, event creation, daily summary update, and audit creation must succeed or fail together. Payroll approval, item locking, totals, and audit creation must also be transactional.

**NFR-DAT-002 — Idempotency — Must**
Retries must produce the same result without duplicate attendance events.

**NFR-DAT-003 — Server-owned fields — Must**
Actor, timestamps, normalized request IP, distance, verification result, payroll totals, approval state, and audit metadata must be generated or verified by the server.

**NFR-DAT-004 — Migration reconciliation — Must**
SQLite-to-InsForge migration must compare row counts and key business totals for employees, attendance, leaves, salary-date fields, face profiles, and biometric logs before cutover. The current source has no payroll history, so the first compensation opening balances require explicit approval.

### 10.4 Financial accuracy and payroll controls

**NFR-FIN-001 — Monetary precision — Must**
Salary amounts must use integer minor units or fixed-precision decimal database types, with consistent rounding rules. Binary floating-point must not be used for payroll money.

**NFR-FIN-002 — Deterministic calculation — Must**
The same employee inputs, compensation version, attendance/leave snapshot, component rules, and policy version must always produce the same salary result.

**NFR-FIN-003 — Reproducibility — Must**
An authorized auditor must be able to reproduce every approved payroll item from its frozen input snapshot and calculation breakdown.

**NFR-FIN-004 — Period immutability — Must**
Approved and paid payroll periods must be immutable to ordinary application roles. Corrections require a controlled reopen, void, or adjustment process.

**NFR-FIN-005 — Segregation of duties — Should**
The system should support separate payroll preparer and approver permissions so one user cannot both prepare and approve payroll when the business has enough staff.

**NFR-FIN-006 — Policy and legal review — Must**
Tax, overtime, minimum wage, paid-leave, deduction, final-settlement, and payslip rules must be approved by the business and reviewed for applicable local requirements before production use. The software must not invent statutory formulas.

**NFR-FIN-007 — Payroll reconciliation — Must**
Each approved pay period must reconcile gross earnings, deductions, net payable, recorded payments, outstanding balance, and any carried adjustments.

### 10.5 Availability and resilience

**NFR-AVL-001 — Availability target — Should**
Target 99.5% monthly application availability, excluding approved maintenance and upstream platform outages. This is a product target, not a claim about an InsForge service guarantee.

**NFR-AVL-002 — Graceful failure — Must**
Network, camera, GPS, permission, and backend failures must produce distinct guidance. The UI must never report attendance as successful before server confirmation.

**NFR-AVL-003 — Operational fallback — Must**
Wi-Fi failure must be recoverable through validated GPS on mobile data or an audited manager override. A public-IP change must be diagnosable without editing source code.

**NFR-AVL-004 — Backup and recovery — Must**
Production must have verified backups and a documented restore procedure. Initial business targets should be RPO 24 hours and RTO 4 hours, subject to owner approval and available InsForge plan capabilities.

### 10.6 Performance

**NFR-PER-001 — API latency — Should**
Under normal operating load, 95% of standard authenticated API requests should complete within 2 seconds, excluding camera capture and external network conditions.

**NFR-PER-002 — Attendance completion — Should**
After evidence capture is complete, 95% of valid attendance decisions should return within 5 seconds.

**NFR-PER-003 — Dashboard efficiency — Must**
Queries must select needed columns, use indexes, pagination, and bounded result sets. Clients must not repeatedly poll unbounded tables.

**NFR-PER-004 — Realtime efficiency — Should**
Use InsForge realtime for small attendance-status updates where useful instead of frequent full-dashboard reloads.

**NFR-PER-005 — Payroll calculation performance — Should**
A payroll draft for 500 employees should calculate within 60 seconds under normal production conditions and provide progress or a safe retry if processing continues asynchronously.

### 10.7 Scalability

**NFR-SCL-001 — Initial capacity — Must**
The first release must support at least 500 employees, 20 branches, 100 registered attendance devices, 100,000 attendance events, and 60 months of itemized payroll without architectural change.

**NFR-SCL-002 — Horizontal client support — Must**
Multiple branch devices and personal/admin iOS sessions must safely operate concurrently without duplicate marks or stale overwrites.

### 10.8 Usability and accessibility

**NFR-UX-001 — Attendance clarity — Must**
The iOS attendance experience must provide clear states: ready, capturing, checking location, verifying face, success, rejection, and retry.

**NFR-UX-002 — Completion feedback — Must**
Successful attendance must show employee name, check-in/check-out action, and server time long enough to be understood, then clear personal data.

**NFR-UX-003 — Accessibility — Should**
The iOS app should follow Apple's accessibility guidance with sufficient contrast, Dynamic Type, VoiceOver labels, Switch Control support where applicable, accessible tap targets, and reduced-motion support.

**NFR-UX-004 — Permission education — Must**
Camera and GPS permission prompts must be preceded by plain-language explanations and recovery steps for denied permissions.

### 10.9 Compatibility

**NFR-CMP-001 — Native-only first release — Must**
The first production release must not depend on a browser or web portal for routine owner, manager, employee, attendance-device, leave, or payroll workflows.

**NFR-CMP-002 — iOS support — Must**
Support iOS 17 and newer. Liquid Glass is enhanced on iOS 26 while earlier versions receive a functional material fallback.

**NFR-CMP-003 — iPhone and iPad layout — Must**
Owner, manager, employee, payroll, and branch-device screens must work on supported iPhones and iPads without loss of essential controls.

**NFR-CMP-004 — Android-ready contract — Must**
Database contracts, RPCs, functions, reason codes, pagination, and authorization rules must remain platform-neutral so a later native Android app can reuse them without redesigning the backend.

### 10.10 Maintainability

**NFR-MNT-001 — One business contract — Must**
The iOS app and future Android app must share server-side rules and versioned request/response contracts.

**NFR-MNT-002 — Migration discipline — Must**
Schema, grants, RLS, functions, constraints, and indexes must be versioned in InsForge migrations. Risky backend work must be tested in an InsForge branch before merging to production.

**NFR-MNT-003 — Separation of concerns — Must**
Location validation, biometric matching, attendance policy, leave policy, payroll calculation, data access, and UI presentation must be independently testable modules.

**NFR-MNT-004 — Configuration over code — Must**
Branch IPs, coordinates, 50-metre radius, thresholds, attendance schedules, leave types, pay schedules, salary components, payroll formulas, approval rules, and retention must be configurable without a source deployment.

### 10.11 Observability and auditability

**NFR-OBS-001 — Structured logging — Must**
Server logs must use structured event names and correlation/attempt IDs without secrets or raw biometric templates.

**NFR-OBS-002 — Health monitoring — Must**
Monitor authentication errors, database failures, attendance rejection rates, GPS accuracy failures, biometric failures, override volume, payroll calculation failures, approval exceptions, reconciliation mismatches, and backup status.

**NFR-OBS-003 — Alerting — Should**
Alert administrators when failure or override rates exceed configured thresholds, a restaurant public IP repeatedly fails, or backups are unhealthy.

**NFR-OBS-004 — Traceability — Must**
An authorized auditor must be able to reconstruct why an attendance mark was accepted, rejected, or overridden and how an approved salary was calculated, without access to a raw face descriptor.

### 10.12 Quality and testing

**NFR-TST-001 — Automated tests — Must**
Unit tests must cover Haversine distance, IP normalization/matching, timezone/business-date logic, biometric threshold behavior, policy modes, proof expiry, proof replay, salary formulas, day rates, rounding, component ordering, and role permissions.

**NFR-TST-002 — Integration tests — Must**
Integration tests must cover cross-branch RLS isolation, attendance transactions, duplicate requests, effective-dated branch/schedule assignments, leave/absence interaction, payroll snapshots, employee pay schedules, payroll locking, salary adjustments, payment reconciliation, deactivated users, remote manager overrides, and audit creation.

**NFR-TST-003 — Device tests — Must**
Test actual branch Wi-Fi and mobile data on representative iPhones/iPads in personal and branch-device modes, including denied permissions, poor indoor GPS, low light, multiple faces, network timeout, and router public-IP changes.

**NFR-TST-004 — Security tests — Must**
Verify that employee-ID substitution, branch-ID substitution, proof replay, spoofed client IP fields, direct table inserts, branch-device access to admin/salary data, cross-branch access, unauthorized payroll approval, and unauthorized audit access are rejected.

**NFR-TST-005 — Release gate — Must**
No production cutover until migrations, rollback/restore, all iOS role/device flows, branch isolation, 50-metre location calibration, biometric consent, salary-policy approval, payroll reconciliation, and acceptance tests have been verified.

### 10.13 Cost control

**NFR-CST-001 — No paid location API — Must**
Location control must use request IP, Core Location, and server-side Haversine distance calculation only.

**NFR-CST-002 — Bandwidth control — Must**
Use bounded queries, selected columns, pagination, compression where appropriate, private payslip storage, and targeted realtime events to avoid unnecessary InsForge egress.

**NFR-CST-003 — Cost visibility — Should**
Review InsForge usage periodically and before increasing retention, image storage, or realtime activity.

## 11. Delivery Plan

### Phase 0 — Business configuration and consent

- Confirm the remaining policy decisions in Section 14; branch coordinates, public IPs, schedules, and employee pay schedules will be configured dynamically after the app supports them.
- Confirm the employee account and branch-device operating model.
- Confirm retention and biometric/location notice/consent.
- Confirm paid/unpaid treatment for Sick, Urgent, and Normal Leave.
- Confirm the recommended scheduled-working-day salary proration and maker-checker payroll approval.
- Approve the acceptance criteria in this document.

Exit criteria: all owner decisions in Section 14 are resolved.

### Phase 1 — InsForge foundation

- Create a schema-only InsForge backend branch.
- Define PostgreSQL migrations for organizations, branches, memberships, employees, schedules, attendance, leave, compensation, payroll, payment, audit, constraints, indexes, grants, and RLS.
- Configure InsForge Auth for owner, manager, payroll preparer, payroll approver, employee, auditor, and registered-device access.
- Create server-owned database functions/edge endpoints for privileged attendance and payroll operations.
- Add secure iOS environment configuration and official InsForge Swift SDK integration.
- Add automated RLS and migration tests.

Exit criteria: cross-branch and unauthorized direct reads/writes fail; authorized test roles pass only for their permitted branches.

### Phase 2 — Data migration

- Export the SQLite database safely.
- Transform identifiers, timestamps, statuses, and relationships.
- Import employees, users/profile mappings, attendance, leaves, face profiles, and audit-compatible biometric logs.
- Import the existing salary-date field and create separately approved opening compensation versions; do not invent historical salary data.
- Reconcile row counts, daily totals, and sampled records.
- Keep the source database read-only during final cutover.
- Retire Node/Express/EJS/SQLite from the production path after reconciliation; keep only controlled migration artifacts if required.

Exit criteria: reconciliation report is approved and restore/rollback is tested.

### Phase 3 — Native iOS foundation and multi-branch administration

- Repair and build-verify the existing SwiftUI scaffold before extending it.
- Replace the legacy Express session client with the official InsForge Swift SDK and Keychain-backed session handling.
- Implement role-based navigation for owner, manager, payroll, employee, and branch-device modes.
- Implement branch lifecycle, branch memberships, effective-dated employee assignments, “Use Current Location,” observed-public-IP diagnostics, and audited IP approval.
- Implement dynamic schedule, leave-type, pay-schedule, and policy configuration.
- Preserve iOS 26 Liquid Glass guards and accessible iOS 17–25 fallbacks.

Exit criteria: the app builds and runs on simulator and physical device; branch isolation and dynamic setup work end to end against the InsForge branch.

### Phase 4 — Secure attendance engine and iOS flow

- Implement branch location and IP rule administration with the confirmed 50-metre geofence and `IP_OR_GPS` policy.
- Implement trusted request-IP resolution and matching.
- Implement GPS evidence validation and Haversine distance.
- Implement attendance attempts and single-use verification proofs.
- Bind biometric, location, device, and employee results.
- Implement atomic check-in/check-out and audit creation.
- Implement employee attendance, registered branch-device mode, remote manager override, and optional emergency window.

Exit criteria: abuse, fallback, idempotency, branch isolation, device, and location-policy suites pass on branch Wi-Fi and mobile data.

### Phase 5 — Leave management

- Implement Sick Leave, Urgent Leave, and Normal Leave as configurable versioned types.
- Implement paid/unpaid rules, entitlements, balances, requests, evidence, branch approval, escalation, and attendance integration.
- Implement employee and manager iOS leave flows and payroll-cutoff exceptions.

Exit criteria: leave balances reconcile, branch approvals are isolated, and approved paid/unpaid leave affects attendance and payroll inputs correctly.

### Phase 6 — Salary and payroll management

- Implement employee-specific pay schedules/cutoffs and joining-date proration in PKR.
- Implement effective-dated compensation and salary components.
- Implement payroll draft generation from frozen attendance and leave inputs.
- Implement calculation breakdowns, validation exceptions, review, approval, locking, reopen/void, and adjustments.
- Implement private payslips and payment-status reconciliation.
- Implement iOS payroll preparer and owner/approver workflows with branch and consolidated views.
- Add payroll RLS, segregation of duties, audit, precision, and reproducibility tests.

Exit criteria: an approved sample payroll reconciles exactly from source inputs to net pay and payment balance; unauthorized salary access is denied.

### Phase 7 — Production readiness and cutover

- Run security, privacy, payroll-reconciliation, backup, performance, and recovery checks.
- Calibrate each branch geofence on-site.
- Train administrators and managers on Wi-Fi outage and override procedures.
- Train payroll preparers and approvers on cutoffs, exceptions, locking, adjustments, payslips, and payment reconciliation.
- Merge the tested InsForge branch after reviewing migration SQL.
- Release the iOS app with production configuration; do not deploy a web application.
- Monitor rejection and override rates closely during rollout.

Exit criteria: production smoke tests pass, backup is verified, and there are no unresolved critical security or data-integrity findings.

## 12. Minimum End-to-End Acceptance Scenarios

1. Approved IP for Branch A + valid face for an employee assigned to Branch A → attendance succeeds and records Branch A plus `ip_verified`.
2. Unapproved IP + GPS within 50 metres of the selected authorized branch + valid face → succeeds as `gps_verified` under `IP_OR_GPS`.
3. Unapproved IP + GPS outside the branch's 50-metre radius → rejected with no attendance row.
4. GPS denied while IP is approved → succeeds under `IP_OR_GPS` and records that GPS was not used.
5. Restaurant Wi-Fi outage + mobile data + in-radius GPS → succeeds.
6. Wi-Fi outage + unusable GPS → ordinary mark fails; authorized manager override succeeds with a mandatory reason.
7. Face match followed by employee-ID substitution → rejected.
8. Replayed or expired verification proof → rejected with no duplicate.
9. Double tap/network retry → one attendance event only.
10. Inactive employee with valid old face profile → rejected.
11. Approved leave employee → no automated absence; attempted present mark follows approved business rule.
12. Branch-device identity tries to query CNIC, salary, or face profile → denied by RLS/API authorization.
13. Admin changes a branch coordinate/IP/policy → old/new values, branch, and actor appear in audit history.
14. Public IP changes after router/ISP change → diagnostic identifies the observed IP; update requires admin and audit.
15. iOS location permission denied → actionable guidance, no false success.
16. Database or network timeout after submission → safe retry returns the original result.
17. Restore test recovers attendance, leave, settings, and audit data within the approved recovery target.
18. Employee salary changes mid-year → payroll before and after the effective date uses the correct compensation version.
19. Approved paid leave → payroll applies no unpaid-leave deduction; approved unpaid leave applies the configured deduction.
20. Attendance is incomplete at payroll cutoff → payroll draft flags the employee instead of silently calculating an unreliable amount.
21. Payroll draft is generated twice from identical inputs → calculation and totals are identical without duplicate items.
22. Attendance is corrected after payroll approval → approved salary does not silently change; an audited adjustment or controlled reopen is required.
23. Unauthorized manager or branch device requests salary data → denied by API authorization and RLS.
24. Payroll preparer attempts approval without approver permission → rejected and audited.
25. Approved payroll item → payslip components reconcile exactly to gross, deductions, and net salary.
26. Partial payment is recorded → paid and outstanding amounts reconcile without changing approved net salary.
27. Payroll is reopened or voided → elevated permission, reason, previous state, actor, and time are retained.
28. Restore test recovers compensation versions, payroll, payments, payslips, and salary audit data within the approved recovery target.
29. Branch A manager queries Branch B employees, attendance, leave, or payroll → denied unless explicitly assigned to Branch B.
30. Owner creates a new branch in iOS, captures coordinates and observed public IP, configures schedules, and activates it without a code deployment.
31. Employee transfers from Branch A to Branch B → historical records remain with Branch A and new records use Branch B after the effective date.
32. Employee with multiple branch assignments selects the wrong distant branch → the server rejects it and the app suggests the nearest authorized branch.
33. Employee joins mid-period → salary is prorated from the employee's individual joining date using the approved scheduled-day rule.
34. Two employees have different payroll cutoffs/payment schedules → each is included in the correct pay schedule and input snapshot.
35. Payroll Administrator prepares a run and the Owner/Payroll Approver approves it → maker-checker identities and timestamps are retained.
36. Manager performs a remote attendance override → branch scope, recent re-authentication, reason, evidence, and owner-visible notification are recorded.

## 13. Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Dynamic restaurant public IP | Valid Wi-Fi attendance may fail | Use GPS fallback, diagnostics, audited IP updates, and request static IP from ISP if practical |
| Indoor GPS inaccuracy | Employees near the branch may be rejected | Calibrate accuracy on-site; prefer approved branch IP; use manager override |
| GPS spoofing | Remote employee may imitate location | Combine face, registered-device identity, IP/GPS evidence, anomaly monitoring, and audit; do not claim GPS is tamper-proof |
| Photo/video face spoofing | False biometric acceptance | Local liveness challenge, controlled branch-device placement, threshold testing, rate limits, and failure monitoring |
| Shared branch-device PIN | Unauthorized attendance-device access | Use revocable device registration, Guided Access readiness, rate limits, and manager-only unlock |
| Sensitive biometric/CNIC exposure | Privacy and security harm | Field-level restrictions, RLS, server-only access, encryption/platform controls, minimal retention, and redacted logs |
| SQLite migration mismatch | Lost or incorrect history | Test migration, reconciliation totals, backup, read-only cutover, and rollback plan |
| Wi-Fi and GPS unavailable together | Attendance cannot be validated | Audited manager override and time-limited emergency mode |
| Client/server rule drift | Inconsistent iOS and future Android decisions | One server-authoritative attendance/payroll engine and versioned contract |
| Missing branch filter | Cross-branch privacy or payroll exposure | Non-null branch ownership, branch-first indexes, narrow grants, RLS, and explicit cross-branch tests |
| Incorrect salary formula or rounding | Employees are underpaid/overpaid | Approved versioned rules, fixed-precision arithmetic, deterministic tests, preview, approval, and reconciliation |
| Attendance correction after payroll lock | Approved salary no longer matches current attendance | Freeze payroll input snapshot; use controlled reopen or a future-period adjustment |
| Unauthorized salary disclosure | Serious employee privacy harm | Dedicated payroll roles, narrow RLS/GRANTs, private payslips, session protection, redacted logs, and audited exports |
| One user prepares and approves payroll | Fraud or accidental payment error | Separate preparer/approver permissions where staffing permits and require recent authentication |
| Unapproved tax or deduction assumptions | Incorrect or non-compliant payroll | Owner-approved policies and local professional review; do not invent statutory formulas |
| Payment status differs from actual payment | Incorrect outstanding balance | Record amount, method, reference, actor, and reconciliation; no automatic claim that money was transferred |

## 14. Remaining Owner Decisions

These do not block creation of the dynamic multi-branch schema. They must be configured and approved before production payroll or biometric attendance is activated:

1. Paid, unpaid, or partially paid treatment and entitlement for Sick Leave, Urgent Leave, and Normal Leave.
2. Branch leave approvers, escalation rules, and whether supporting evidence is required.
3. Whether checking in cancels approved leave or creates a manager exception.
4. Confirm the recommended salary day-rate: scheduled working days in the employee's assigned schedule, with first/last periods prorated from joining/ending date.
5. Actual absence, lateness, early-departure, overtime, holiday, and rest-day rates; these will remain dynamic settings.
6. Required recurring allowances/deductions and bonus, commission, loan, advance, tax, and final-settlement rules.
7. PKR rounding rule and whether net salary may be negative or must carry excess deductions forward.
8. Payroll reopen/void permissions and whether the same-user prepare/approve exception is ever allowed. Recommendation: disabled.
9. Payslip branding, content, delivery, and retention.
10. Payment methods/references to track and whether partial payments are needed at launch.
11. Retention periods for attendance, precise GPS evidence, failures, audit, payslips, and face profiles.
12. Whether the first release needs a read-only auditor role and whether exports may contain CNIC or precise location evidence.
13. Approved employee biometric/location notice and consent process.
14. The selected native face-embedding/liveness approach and its on-site accuracy acceptance threshold.
15. Locally reviewed wage, overtime, deduction, payslip, tax, and record-retention obligations.

## 15. Definition of Done

The system is functionally complete only when:

- All **Must** requirements are implemented and tested.
- The iOS personal, manager, payroll, owner, and branch-device modes use the same InsForge-backed rules, and those contracts are Android-ready.
- IP and GPS decisions are server-authoritative and require no paid API.
- Face results are bound to a short-lived, single-use attendance proof.
- Manager fallback is operational and fully audited.
- Attendance, leave, and salary rules are integrated through frozen, reproducible payroll inputs.
- Compensation changes are effective-dated and approved payroll is immutable outside controlled correction workflows.
- Every payslip and payroll run reconciles gross earnings, deductions, net salary, payments, and outstanding balance.
- Salary access is protected by dedicated permissions and RLS.
- RLS prevents unauthorized access even when clients call InsForge directly.
- SQLite migration and reconciliation are approved.
- Physical on-site tests pass at every activated branch on branch Wi-Fi and mobile data within the 50-metre geofence.
- Backup and restore are verified.
- Privacy/consent, payroll-policy, legal-review, and retention decisions are documented.
- No critical security, privacy, or data-integrity issue remains open.
