USE tri_party_lending;

-- Post a transaction with basic validation (shows “production-minded” approach)
CREATE PROCEDURE sp_post_transaction(
  IN p_loan_id INT,
  IN p_txn_date DATE,
  IN p_txn_type ENUM('DISBURSEMENT','PASS_THROUGH','REPAYMENT','PENALTY','ADJUSTMENT'),
  IN p_from_company_id INT,
  IN p_to_company_id INT,
  IN p_amount DECIMAL(14,2),
  IN p_external_ref VARCHAR(80),
  IN p_notes VARCHAR(255)
)
BEGIN
  IF p_amount <= 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Amount must be > 0';
  END IF;

  IF (SELECT COUNT(*) FROM loans WHERE loan_id = p_loan_id) = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid loan_id';
  END IF;

  -- If external_ref is provided, prevent duplicates via unique index uq_txn_extref.
  INSERT INTO transactions (loan_id, txn_date, txn_type, from_company_id, to_company_id, amount, external_ref, notes)
  VALUES (p_loan_id, p_txn_date, p_txn_type, p_from_company_id, p_to_company_id, p_amount, p_external_ref, p_notes);
END


-- Accrue monthly interest using simple formula:
-- interest = opening_principal * rate/12
-- opening_principal is derived from last accrual closing_principal or loan principal if first month.
CREATE PROCEDURE sp_accrue_monthly(IN p_accrual_month DATE)
BEGIN
  DECLARE month_start DATE;
  SET month_start = DATE_FORMAT(p_accrual_month, '%Y-%m-01');

  -- Upsert accruals for all ACTIVE loans
  INSERT INTO accruals_monthly (loan_id, accrual_month, opening_principal, interest_accrued, penalty_accrued, closing_principal)
  SELECT
    l.loan_id,
    month_start AS accrual_month,
    COALESCE(prev.closing_principal, l.principal_amount) AS opening_principal,
    ROUND(COALESCE(prev.closing_principal, l.principal_amount) * l.interest_rate_annual / 12, 2) AS interest_accrued,
    0.00 AS penalty_accrued,
    -- For demo: closing_principal = opening - expected_principal_due of that month (if schedule exists), else keep same
    GREATEST(
      COALESCE(prev.closing_principal, l.principal_amount)
      - COALESCE(s.expected_principal_due, 0.00),
      0.00
    ) AS closing_principal
  FROM loans l
  LEFT JOIN accruals_monthly prev
    ON prev.loan_id = l.loan_id
   AND prev.accrual_month = DATE_SUB(month_start, INTERVAL 1 MONTH)
  LEFT JOIN loan_schedule s
    ON s.loan_id = l.loan_id
   AND DATE_FORMAT(s.due_date, '%Y-%m-01') = month_start
  WHERE l.status = 'ACTIVE'
  ON DUPLICATE KEY UPDATE
    opening_principal = VALUES(opening_principal),
    interest_accrued   = VALUES(interest_accrued),
    penalty_accrued    = VALUES(penalty_accrued),
    closing_principal  = VALUES(closing_principal);
END


-- Run audit rules across a date range; inserts findings into audit_findings
CREATE PROCEDURE sp_run_audit(IN p_from DATE, IN p_to DATE)
BEGIN
  -- Clear only findings in current run window to avoid infinite growth for demo
  DELETE FROM audit_findings
   WHERE created_at >= DATE_SUB(NOW(), INTERVAL 1 DAY);

  /*
    R001: Pass-through missing/partial
    Expect B->C pass-through amount >= A->B disbursement for each loan (within window)
  */
  INSERT INTO audit_findings (loan_id, rule_code, severity, expected_value, actual_value, delta_value, details)
  SELECT
    d.loan_id,
    'R001' AS rule_code,
    'HIGH' AS severity,
    d.disbursed AS expected_value,
    COALESCE(p.passed, 0.00) AS actual_value,
    (d.disbursed - COALESCE(p.passed,0.00)) AS delta_value,
    CONCAT('Pass-through shortfall. Disbursed=', d.disbursed, ', Passed=', COALESCE(p.passed,0.00))
  FROM (
    SELECT loan_id, SUM(amount) AS disbursed
    FROM transactions
    WHERE txn_type='DISBURSEMENT' AND txn_date BETWEEN p_from AND p_to
    GROUP BY loan_id
  ) d
  LEFT JOIN (
    SELECT loan_id, SUM(amount) AS passed
    FROM transactions
    WHERE txn_type='PASS_THROUGH' AND txn_date BETWEEN p_from AND p_to
    GROUP BY loan_id
  ) p ON p.loan_id = d.loan_id
  WHERE COALESCE(p.passed,0.00) < d.disbursed;

  /*
    R002: Repayment shortfall per schedule due date (principal+interest)
    Compare expected schedule vs actual repayments on that due_date (same day for demo)
  */
  INSERT INTO audit_findings (loan_id, rule_code, severity, expected_value, actual_value, delta_value, details)
  SELECT
    s.loan_id,
    'R002',
    'HIGH',
    (s.expected_principal_due + s.expected_interest_due) AS expected_value,
    COALESCE(r.paid, 0.00) AS actual_value,
    ((s.expected_principal_due + s.expected_interest_due) - COALESCE(r.paid,0.00)) AS delta_value,
    CONCAT('Repayment shortfall on ', s.due_date, '. Expected=', (s.expected_principal_due + s.expected_interest_due),
           ', Paid=', COALESCE(r.paid,0.00))
  FROM loan_schedule s
  LEFT JOIN (
    SELECT loan_id, txn_date, SUM(amount) AS paid
    FROM transactions
    WHERE txn_type='REPAYMENT' AND txn_date BETWEEN p_from AND p_to
    GROUP BY loan_id, txn_date
  ) r ON r.loan_id = s.loan_id AND r.txn_date = s.due_date
  WHERE s.due_date BETWEEN p_from AND p_to
    AND COALESCE(r.paid,0.00) + 0.01 < (s.expected_principal_due + s.expected_interest_due);

  /*
    R003: Late repayment but missing penalty
    If repayment occurs after due_date+grace_days and no PENALTY txn within 3 days of repayment.
  */
  INSERT INTO audit_findings (loan_id, rule_code, severity, expected_value, actual_value, delta_value, details)
  SELECT
    r.loan_id,
    'R003',
    'MEDIUM',
    NULL,
    NULL,
    NULL,
    CONCAT('Late repayment on ', r.txn_date, ' for due ', s.due_date,
           ' (grace ', s.grace_days, 'd) but no penalty posted near repayment.')
  FROM (
    SELECT loan_id, txn_date
    FROM transactions
    WHERE txn_type='REPAYMENT' AND txn_date BETWEEN p_from AND p_to
    GROUP BY loan_id, txn_date
  ) r
  JOIN loan_schedule s
    ON s.loan_id = r.loan_id
   AND s.due_date BETWEEN DATE_SUB(r.txn_date, INTERVAL 45 DAY) AND r.txn_date
  LEFT JOIN (
    SELECT loan_id, txn_date
    FROM transactions
    WHERE txn_type='PENALTY'
  ) p ON p.loan_id = r.loan_id
    AND p.txn_date BETWEEN r.txn_date AND DATE_ADD(r.txn_date, INTERVAL 3 DAY)
  WHERE r.txn_date > DATE_ADD(s.due_date, INTERVAL s.grace_days DAY)
    AND p.txn_date IS NULL;

  /*
    R004: Potential duplicate repayments
    Same loan, same date, same amount occurs more than once.
  */
  INSERT INTO audit_findings (loan_id, rule_code, severity, expected_value, actual_value, delta_value, details)
  SELECT
    loan_id,
    'R004',
    'MEDIUM',
    NULL, NULL, NULL,
    CONCAT('Duplicate repayment detected on ', txn_date, ' amount=', amount, ' count=', cnt)
  FROM (
    SELECT loan_id, txn_date, amount, COUNT(*) AS cnt
    FROM transactions
    WHERE txn_type='REPAYMENT' AND txn_date BETWEEN p_from AND p_to
    GROUP BY loan_id, txn_date, amount
    HAVING COUNT(*) > 1
  ) x;

  /*
    R005: Accrual mismatch vs expected interest (opening_principal*rate/12)
    Tolerance: 0.50
  */
  INSERT INTO audit_findings (loan_id, rule_code, severity, expected_value, actual_value, delta_value, details)
  SELECT
    a.loan_id,
    'R005',
    'LOW',
    expected_interest,
    a.interest_accrued,
    (expected_interest - a.interest_accrued) AS delta_value,
    CONCAT('Interest accrual mismatch for ', a.accrual_month,
           '. Expected=', expected_interest, ', Actual=', a.interest_accrued)
  FROM (
    SELECT
      am.loan_id,
      am.accrual_month,
      am.interest_accrued,
      ROUND(am.opening_principal * l.interest_rate_annual / 12, 2) AS expected_interest
    FROM accruals_monthly am
    JOIN loans l ON l.loan_id = am.loan_id
    WHERE am.accrual_month BETWEEN DATE_FORMAT(p_from, '%Y-%m-01') AND DATE_FORMAT(p_to, '%Y-%m-01')
  ) a
  WHERE ABS(a.expected_interest - a.interest_accrued) > 0.50;

END

DELIMITER ;