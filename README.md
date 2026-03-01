# Sales Analytics SQL Project (SQL Server / SSMS)

SQL portfolio project: **RAW → CLEAN → STAR SCHEMA → Data Quality Checks → Analytics**.

## Stack
SQL Server (T-SQL), SSMS • Star schema modeling • Data quality validation • CTEs & window functions

## Dataset
CSV with **order line** records (1 row = 1 order line).  
Key fields include order identifiers, dates/status, product attributes, customer/location attributes, and sales/profit measures.  
Rows: **2,823**.

## Pipeline
- **RAW (staging):** `dbo.stg_sales_raw` (1:1 copy of source data)
- **CLEAN:** `dbo.sales_clean` (typed + standardized fields)
- **STAR SCHEMA:** `dim_date`, `dim_product`, `dim_customer`, `fact_sales` (grain: order line)

Fact load:
- product mapping by `ProductCode`
- customer mapping by `(CustomerName, Country, City, State, PostalCode)`
- `DateKey` derived from `OrderDate`

## Data Quality Checks (summary)
- row counts match across layers (**2823**)
- grain uniqueness enforced on `(OrderNumber, OrderLineNumber)`
- no missing rows in fact
- totals match between CLEAN and FACT (Sales/Profit)

## Analytics
Main script:
- [`sql/07_analytics.sql`](sql/07_analytics.sql)

Includes:
- product line performance (Sales/Profit)
- top products / top customers
- monthly & quarterly trends
- YoY monthly growth (window functions)
- weighted price vs MSRP and order size mix
- Pareto 80/20 customers
- RFM segmentation
- cohort retention (0–12 months)

## Structure
- `sql/` — queries
- `docs/screenshots/` — outputs (schema, checks, key analyses)
