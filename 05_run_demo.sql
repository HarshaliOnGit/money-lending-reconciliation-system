USE tri_party_lending;

-- Run audit for Oct 2025 - Jan 2026 window
CALL sp_run_audit('2025-10-01','2026-01-31');

-- View findings
SELECT * FROM vw_findings;

-- Helpful investigation queries
SELECT * FROM vw_loan_cashflow_summary;
SELECT * FROM vw_schedule_vs_paid ORDER BY loan_id, due_date;
SELECT * FROM vw_late_repayments ORDER BY loan_id, repayment_date;