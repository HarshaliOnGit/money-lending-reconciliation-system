USE tri_party_lending;

-- Quick cashflow summary by loan
CREATE OR REPLACE VIEW vw_loan_cashflow_summary AS
SELECT
  l.loan_id,
  l.external_ref,
  SUM(CASE WHEN t.txn_type='DISBURSEMENT' THEN t.amount ELSE 0 END) AS total_disbursed,
  SUM(CASE WHEN t.txn_type='PASS_THROUGH' THEN t.amount ELSE 0 END) AS total_passed_through,
  SUM(CASE WHEN t.txn_type='REPAYMENT' THEN t.amount ELSE 0 END) AS total_repaid,
  SUM(CASE WHEN t.txn_type='PENALTY' THEN t.amount ELSE 0 END) AS total_penalties
FROM loans l
LEFT JOIN transactions t ON t.loan_id = l.loan_id
GROUP BY l.loan_id, l.external_ref;

-- Expected vs actual per schedule date
CREATE OR REPLACE VIEW vw_schedule_vs_paid AS
SELECT
  s.loan_id,
  l.external_ref,
  s.due_date,
  (s.expected_principal_due + s.expected_interest_due) AS expected_due,
  COALESCE(SUM(CASE WHEN t.txn_type='REPAYMENT' THEN t.amount END), 0.00) AS actual_paid
FROM loan_schedule s
JOIN loans l ON l.loan_id = s.loan_id
LEFT JOIN transactions t
  ON t.loan_id = s.loan_id
 AND t.txn_date = s.due_date
GROUP BY s.loan_id, l.external_ref, s.due_date, expected_due;

-- Late repayments (for investigation)
CREATE OR REPLACE VIEW vw_late_repayments AS
SELECT
  t.loan_id,
  l.external_ref,
  s.due_date,
  s.grace_days,
  t.txn_date AS repayment_date,
  DATEDIFF(t.txn_date, s.due_date) AS days_after_due,
  t.amount
FROM transactions t
JOIN loans l ON l.loan_id = t.loan_id
JOIN loan_schedule s
  ON s.loan_id = t.loan_id
 AND s.due_date <= t.txn_date
WHERE t.txn_type='REPAYMENT'
  AND t.txn_date > DATE_ADD(s.due_date, INTERVAL s.grace_days DAY);

-- Findings view 
CREATE OR REPLACE VIEW vw_findings AS
SELECT
  f.finding_id,
  l.external_ref,
  f.loan_id,
  f.rule_code,
  f.severity,
  f.expected_value,
  f.actual_value,
  f.delta_value,
  f.details,
  f.created_at
FROM audit_findings f
JOIN loans l ON l.loan_id = f.loan_id
ORDER BY f.created_at DESC, f.severity DESC;