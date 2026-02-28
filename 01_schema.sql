-- This file contains the scripts to create the schema required to demonstrate this project.

-- tri_party_database to crate and store all relavant tables and data
DROP DATABASE IF EXISTS tri_party_lending;
CREATE DATABASE tri_party_lending;
USE tri_party_lending;


-- Create tables to store the companies data involved in the business
CREATE TABLE companies (
  company_id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  role ENUM('LENDER','BORROWER','INTERMEDIARY') NOT NULL,
  UNIQUE KEY uq_company_name (name)
);

--Create table to store the loan related data 
CREATE TABLE loans (
  loan_id INT AUTO_INCREMENT PRIMARY KEY,
  lender_company_id INT NOT NULL,
  borrower_company_id INT NOT NULL,
  intermediary_company_id INT NOT NULL,
  principal_amount DECIMAL(14,2) NOT NULL,
  interest_rate_annual DECIMAL(7,4) NOT NULL, -- e.g., 0.1200 = 12% annual
  start_date DATE NOT NULL,
  term_months INT NOT NULL,
  status ENUM('ACTIVE','CLOSED','DEFAULT') NOT NULL DEFAULT 'ACTIVE',
  external_ref VARCHAR(50) NULL,

--Using keys for better performance and mapping
  CONSTRAINT fk_loans_lender FOREIGN KEY (lender_company_id) REFERENCES companies(company_id),
  CONSTRAINT fk_loans_borrower FOREIGN KEY (borrower_company_id) REFERENCES companies(company_id),
  CONSTRAINT fk_loans_intermediary FOREIGN KEY (intermediary_company_id) REFERENCES companies(company_id),
  KEY idx_loans_status (status),
  KEY idx_loans_start (start_date),
  UNIQUE KEY uq_loan_external_ref (external_ref)
);

-- Create table to store expected loan repayments schedule
CREATE TABLE loan_schedule (
  schedule_id INT AUTO_INCREMENT PRIMARY KEY,
  loan_id INT NOT NULL,
  due_date DATE NOT NULL,
  expected_principal_due DECIMAL(14,2) NOT NULL,
  expected_interest_due DECIMAL(14,2) NOT NULL,
  grace_days INT NOT NULL DEFAULT 5,
  UNIQUE KEY uq_schedule_loan_due (loan_id, due_date),
  KEY idx_schedule_due (due_date),
  CONSTRAINT fk_schedule_loan FOREIGN KEY (loan_id) REFERENCES loans(loan_id)
);

--Create table to store transactions
CREATE TABLE transactions (
  txn_id BIGINT AUTO_INCREMENT PRIMARY KEY,
  loan_id INT NOT NULL,
  txn_date DATE NOT NULL,
  txn_type ENUM('DISBURSEMENT','PASS_THROUGH','REPAYMENT','PENALTY','ADJUSTMENT') NOT NULL,
  from_company_id INT NOT NULL,
  to_company_id INT NOT NULL,
  amount DECIMAL(14,2) NOT NULL,
  external_ref VARCHAR(80) NULL,
  notes VARCHAR(255) NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT fk_txn_loan FOREIGN KEY (loan_id) REFERENCES loans(loan_id),
  CONSTRAINT fk_txn_from FOREIGN KEY (from_company_id) REFERENCES companies(company_id),
  CONSTRAINT fk_txn_to FOREIGN KEY (to_company_id) REFERENCES companies(company_id),

  KEY idx_txn_loan_date (loan_id, txn_date),
  KEY idx_txn_type_date (txn_type, txn_date),
  KEY idx_txn_from_to_date (from_company_id, to_company_id, txn_date),
  KEY idx_txn_external_ref (external_ref)
);
-- Create unique key to avoid duplication
CREATE UNIQUE INDEX uq_txn_extref ON transactions (loan_id, txn_type, external_ref);

-- Monthly accruals (simple interest)
CREATE TABLE accruals_monthly (
  accrual_id BIGINT AUTO_INCREMENT PRIMARY KEY,
  loan_id INT NOT NULL,
  accrual_month DATE NOT NULL, -- store as first day of month
  opening_principal DECIMAL(14,2) NOT NULL,
  interest_accrued DECIMAL(14,2) NOT NULL,
  penalty_accrued DECIMAL(14,2) NOT NULL DEFAULT 0.00,
  closing_principal DECIMAL(14,2) NOT NULL,

  UNIQUE KEY uq_accrual_loan_month (loan_id, accrual_month),
  KEY idx_accrual_month (accrual_month),
  CONSTRAINT fk_accrual_loan FOREIGN KEY (loan_id) REFERENCES loans(loan_id)
);

-- Findings produced by the audit
CREATE TABLE audit_findings (
  finding_id BIGINT AUTO_INCREMENT PRIMARY KEY,
  loan_id INT NOT NULL,
  rule_code VARCHAR(10) NOT NULL,
  severity ENUM('LOW','MEDIUM','HIGH') NOT NULL,
  expected_value DECIMAL(14,2) NULL,
  actual_value DECIMAL(14,2) NULL,
  delta_value DECIMAL(14,2) NULL,
  details VARCHAR(500) NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

  KEY idx_findings_rule_date (rule_code, created_at),
  KEY idx_findings_loan_date (loan_id, created_at),
  CONSTRAINT fk_findings_loan FOREIGN KEY (loan_id) REFERENCES loans(loan_id)
);