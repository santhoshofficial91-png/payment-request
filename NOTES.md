# Payment Request app - handover notes (for any future Claude/developer session)

Owner: Santhosh (EXPERT Corporate Solutions), replies in Tamil, IST.
Live: https://santhoshofficial91-png.github.io/payment-request/ (GitHub Pages, repo santhoshofficial91-png/payment-request, branch main)
Backend: Supabase project `ijlapetfddltbgqnwtrp` (Auth + Postgres + RLS + Edge Function `manage-users`).
App: ONE file `index.html` (vanilla JS). Other files: `supabase/schema.sql` (+ comment notes of later migrations), `supabase/functions/manage-users/index.ts`.

## Deploy workflow
Edit index.html -> `node --check` the script -> test (Playwright + mock supabase) -> `deploy.sh "msg"` (stamps `<meta name="app-build">`, commits, pushes).
Users get a full-screen "New update available - refresh" notice (checks the build id every 60s).
Never put the text `<meta name="app-build"` inside JS (deploy.sh uses sed on it).

## Roles
admin, manager (mgr), executive (exe). Sub Admin = executive with department "Sub Admin" (PO Master only, no delete). HR = department "HR" (only Expense Request, Expense Paid, Request Sent; UI restriction only).
Admin menu groups: Create (Manager/Executive/Sub Admin), Supplier Payment (Request, Paid), Expense (Request, Paid).

## Data model (arrays in memory, diff-synced to Supabase by save())
PAY row: [id,req_name,enq,req_date,po,supplier,customer,purpose(7),delivery_date,lead_time,stock_status,stock_location,amount(12),status(13),requester_remark,accounts_remark,pr_status(16),paid_at(17),'Returned'|'',n(19),priority(20),requester_id(21),sent_at(22)]
EXP row: [id,req_name,req_date,purpose,paid_to,amount,status,requester_remark,accounts_remark,pr_status(9),paid_at,'Returned'|'',n(12),requester_id(13),priority(14),enq(15),debit_to(16),department(17),sent_at(18)]
PO row: [enq,po_date,supplier,po_num,po_value,paid,balance,requester,n]
pr_status: 'Request Not Sent' | 'Request Sent' | 'With Manager'. sent_at is stamped by DB trigger `zz_stamp_sent`.

## Business rules implemented
- Cut-off 2:00-5:00 PM IST: executives cannot send to admin; their send goes to manager ('With Manager'), manager forwards (mgr_send_requests). Purpose "Sample" bypasses the cut-off.
- Purposes: Advance, Balance, Against Delivery, Sample, Outstanding. For Sample: ENQ and PO optional, PO may be blank/any text. Other purposes: PO must exist in PO Master (short entry like 928 matches PO/928/26-27), supplier/ENQ auto-fill, amount cannot exceed PO balance.
- Columns "Request Sent" (time, IST) and "Request In" (who holds the request) on all request pages.
- 10 rows/page pagination, column filters, entry row at the bottom of request pages, Import Text on Expense Request, admin delete options, PO Master Edit/Delete only.
- Full-page mode (hamburger): table min-width 1700px with horizontal scroll; Req Amt and Status always fully visible. Cut-off timer box ~3cm.
- DB: RLS + security-definer helpers my_role(), is_my_team(), pr_cutoff_over(), is_sub_admin(); triggers payments_guard, expenses_guard, zz_stamp_sent; RPCs revoke_request, revoke_expense, mgr_send_requests; table profile_secrets (admin-only passwords shown in edit forms).

## Update notice (before every deployment)
Admin dashboard has "Announce update" button -> all users get a full-screen 1-minute warning (OK) + countdown bar, then a blocking "update in progress" screen for 5 min (auto-clears; admin can press "Update done"). Do this BEFORE pushing a deployment when users are active.
