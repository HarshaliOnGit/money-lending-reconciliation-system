import csv
import os
from datetime import date
import mysql.connector

DB_HOST = os.getenv("DB_HOST", "127.0.0.1")
DB_PORT = int(os.getenv("DB_PORT", "3306"))
DB_USER = os.getenv("DB_USER", "root")
DB_PASS = os.getenv("DB_PASS", "")
DB_NAME = os.getenv("DB_NAME", "tri_party_lending")

REPORT_DIR = os.getenv("REPORT_DIR", "reports")
FROM_DATE = os.getenv("FROM_DATE", "2025-10-01")
TO_DATE = os.getenv("TO_DATE", "2026-01-31")

def ensure_dir(path: str) -> None:
    os.makedirs(path, exist_ok=True)

def export_query(cur, query: str, filepath: str) -> None:
    cur.execute(query)
    cols = [d[0] for d in cur.description]
    rows = cur.fetchall()
    with open(filepath, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(cols)
        w.writerows(rows)

def main():
    ensure_dir(REPORT_DIR)

    conn = mysql.connector.connect(
        host=DB_HOST,
        port=DB_PORT,
        user=DB_USER,
        password=DB_PASS,
        database=DB_NAME,
    )
    try:
        cur = conn.cursor()

        # Run audit
        cur.callproc("sp_run_audit", [FROM_DATE, TO_DATE])
        conn.commit()

        # Export findings and summaries
        export_query(cur, "SELECT * FROM vw_findings", os.path.join(REPORT_DIR, "audit_findings.csv"))
        export_query(cur, "SELECT * FROM vw_loan_cashflow_summary", os.path.join(REPORT_DIR, "cashflow_summary.csv"))
        export_query(cur, "SELECT * FROM vw_schedule_vs_paid ORDER BY loan_id, due_date",
                     os.path.join(REPORT_DIR, "schedule_vs_paid.csv"))
        export_query(cur, "SELECT * FROM vw_late_repayments ORDER BY loan_id, repayment_date",
                     os.path.join(REPORT_DIR, "late_repayments.csv"))

        print("Reports generated in:", REPORT_DIR)

    finally:
        conn.close()

if __name__ == "__main__":
    main()