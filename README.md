# Tri-Party Lending & Reconciliation Engine (MySQL)

## Concept
A simple tri-party lending flow:
- Company A (Lender) disburses funds to Company B (Borrower)
- Company B passes funds to Company C (Intermediary)
- Company C repays Company A (principal + interest + penalties if applicable)

This project demonstrates:
- SQL schema design + transaction ledger
- Stored procedures (posting txns, accruing interest, rule audit)
- Reconciliation rules
- Views for investigation
- Indexing and performance awareness
- Exporting audit reports using Python

## How to run (SQL)
1. Open MySQL and run scripts in order:
   - `sql/01_schema.sql`
   - `sql/02_seed_data.sql`
   - `sql/03_procedures.sql`
   - `sql/04_views.sql`
2. Run demo:
   - `sql/05_run_demo.sql`

You should see findings in `vw_findings`.

---

## Rules implemented (Audit)
- **R001** Pass-through missing/partial: DISBURSEMENT(A->B) not fully matched by PASS_THROUGH(B->C)
- **R002** Repayment shortfall: REPAYMENT(C->A) below expected schedule amount (principal+interest)
- **R003** Late repayment but missing penalty: repayment after due_date+grace_days with no penalty posted near repayment
- **R004** Duplicate repayments: same loan/date/amount posted multiple times
- **R005** Accrual mismatch: stored monthly interest differs from expected 

---

## Investigation workflow (example)
Seeded issue examples:
- Loan LN-1002: missing PASS_THROUGH triggers **R001**
- Loan LN-1001: Jan repayment is short triggers **R002**
- Loan LN-1002: late repayment with no penalty triggers **R003**
- Loan LN-1003: duplicate repayment triggers **R004**
- Loan LN-1002: accrual interest mismatch triggers **R005**

Typical investigation steps:
1. Start with `vw_findings` to identify impacted loan and rule.
2. Use `vw_loan_cashflow_summary` to understand direction totals.
3. Use `vw_schedule_vs_paid` to compare due vs paid on schedule dates.
4. Use `vw_late_repayments` to isolate late items and confirm penalty behavior.
5. Trace raw ledger entries in `transactions` for root cause.

