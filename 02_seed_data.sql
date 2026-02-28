USE tri_party_lending;

-- Insert data into companies table
INSERT INTO companies (name, role) VALUES
('Company A', 'LENDER'),
('Company B', 'BORROWER'),
('Company C', 'INTERMEDIARY');

-- Insert data into loans table 
INSERT INTO loans (lender_company_id, borrower_company_id, intermediary_company_id,
                   principal_amount, interest_rate_annual, start_date, term_months, status, external_ref)
VALUES
(1, 2, 3, 100000.00, 0.1200, '2025-10-01', 6, 'ACTIVE', 'LN-1001'),
(1, 2, 3,  50000.00, 0.1000, '2025-10-01', 6, 'ACTIVE', 'LN-1002'),
(1, 2, 3,  75000.00, 0.1500, '2025-10-01', 6, 'ACTIVE', 'LN-1003');


-- Inserting values for 3 months (Nov, Dec, Jan)
--Data for loan_id=1 
INSERT INTO loan_schedule (loan_id, due_date, expected_principal_due, expected_interest_due, grace_days) VALUES
(1, '2025-11-05', 20000.00, 100000.00*0.1200/12, 5),
(1, '2025-12-05', 20000.00,  80000.00*0.1200/12, 5),
(1, '2026-01-05', 20000.00,  60000.00*0.1200/12, 5);

--Data for loan_id=2
INSERT INTO loan_schedule (loan_id, due_date, expected_principal_due, expected_interest_due, grace_days) VALUES
(2, '2025-11-05', 10000.00, 50000.00*0.1000/12, 5),
(2, '2025-12-05', 10000.00, 40000.00*0.1000/12, 5),
(2, '2026-01-05', 10000.00, 30000.00*0.1000/12, 5);

----Data for loan_id=3
INSERT INTO loan_schedule (loan_id, due_date, expected_principal_due, expected_interest_due, grace_days) VALUES
(3, '2025-11-05', 15000.00, 75000.00*0.1500/12, 5),
(3, '2025-12-05', 15000.00, 60000.00*0.1500/12, 5),
(3, '2026-01-05', 15000.00, 45000.00*0.1500/12, 5);

--Disbursement Data from Lender(A) to Borrower(B)
INSERT INTO transactions (loan_id, txn_date, txn_type, from_company_id, to_company_id, amount, external_ref, notes) VALUES
(1, '2025-10-01', 'DISBURSEMENT', 1, 2, 100000.00, 'TXN-D-1001', 'Initial disbursement'),
(2, '2025-10-01', 'DISBURSEMENT', 1, 2,  50000.00, 'TXN-D-1002', 'Initial disbursement'),
(3, '2025-10-01', 'DISBURSEMENT', 1, 2,  75000.00, 'TXN-D-1003', 'Initial disbursement');

--Payment from Borrower(B) to Intermediatery Company (C)
--Payment for loanid=1
INSERT INTO transactions VALUES
(NULL, 1, '2025-10-02', 'PASS_THROUGH', 2, 3, 100000.00, 'TXN-P-1001', 'Pass through to intermediary', CURRENT_TIMESTAMP);

--Payment for loanid=2 is missed

--Payment for loanid=3
INSERT INTO transactions (loan_id, txn_date, txn_type, from_company_id, to_company_id, amount, external_ref, notes) VALUES
(3, '2025-10-02', 'PASS_THROUGH', 2, 3, 70000.00, 'TXN-P-1003', 'Partial pass through (seed issue)');


--Repayments from Intermeidatory Company(C) to Lender (A)
INSERT INTO transactions (loan_id, txn_date, txn_type, from_company_id, to_company_id, amount, external_ref, notes) VALUES
(2, '2025-11-15', 'REPAYMENT', 3, 1, 10000.00 + (50000.00*0.1000/12), 'TXN-R-1002-11', 'Nov repayment late (no penalty seeded)');

-- Delibearte duplicate entry to test procedures 
INSERT INTO transactions (loan_id, txn_date, txn_type, from_company_id, to_company_id, amount, external_ref, notes) VALUES
(3, '2025-11-05', 'REPAYMENT', 3, 1, 15000.00 + (75000.00*0.1500/12), 'TXN-R-1003-11', 'Nov repayment'),
(3, '2025-11-05', 'REPAYMENT', 3, 1, 15000.00 + (75000.00*0.1500/12), 'TXN-R-1003-11-DUP', 'Duplicate repayment seeded');

--Seed accruals (including one mismatch)
INSERT INTO accruals_monthly (loan_id, accrual_month, opening_principal, interest_accrued, penalty_accrued, closing_principal) VALUES
-- LN-1001: correct interest for Nov and Dec, correct opening/closing for demo
(1, '2025-11-01', 100000.00, ROUND(100000.00*0.1200/12,2), 0.00, 80000.00),
(1, '2025-12-01',  80000.00, ROUND( 80000.00*0.1200/12,2), 0.00, 60000.00),

-- mismatch interest - should be 416.67; store 500.00
(2, '2025-11-01',  50000.00, 500.00, 0.00, 40000.00),

-- correct interest
(3, '2025-11-01',  75000.00, ROUND(75000.00*0.1500/12,2), 0.00, 60000.00);