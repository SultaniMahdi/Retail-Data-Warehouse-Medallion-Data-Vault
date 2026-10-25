/*
===============================================================================
Profiling: bronze.orders  (Silver step 2, part 1)
Purpose : Find problems BEFORE cleaning. Read-only, changes nothing.
Usage   : Run block by block and check the results.
          The findings decide which rules go into 03_proc_load_silver_orders.sql.
===============================================================================
*/

/* ---------- 1. Overview: rows vs. distinct order_id ---------- */
SELECT COUNT(*)                                AS rows_total,
       COUNT(DISTINCT order_id)                AS distinct_order_id,
       COUNT(*) - COUNT(DISTINCT order_id)     AS surplus_rows
FROM   bronze.orders;

/* ---------- 2. Duplicate order_id (if any) ---------- */
SELECT order_id, COUNT(*) AS cnt
FROM   bronze.orders
GROUP  BY order_id
HAVING COUNT(*) > 1
ORDER  BY cnt DESC;

/* ---------- 3. Status values ---------- */
SELECT order_status, COUNT(*) AS cnt
FROM   bronze.orders
GROUP  BY order_status
ORDER  BY cnt DESC;

/* ---------- 4. Min / max of all timestamps (sanity check) ---------- */
SELECT MIN(TRY_CONVERT(DATETIME2(0), NULLIF(LTRIM(RTRIM(order_purchase_timestamp)), ''), 120))      AS purchase_min,
       MAX(TRY_CONVERT(DATETIME2(0), NULLIF(LTRIM(RTRIM(order_purchase_timestamp)), ''), 120))      AS purchase_max,
       MIN(TRY_CONVERT(DATETIME2(0), NULLIF(LTRIM(RTRIM(order_delivered_customer_date)), ''), 120)) AS delivered_min,
       MAX(TRY_CONVERT(DATETIME2(0), NULLIF(LTRIM(RTRIM(order_delivered_customer_date)), ''), 120)) AS delivered_max,
       MIN(TRY_CONVERT(DATETIME2(0), NULLIF(LTRIM(RTRIM(order_estimated_delivery_date)), ''), 120)) AS estimated_min,
       MAX(TRY_CONVERT(DATETIME2(0), NULLIF(LTRIM(RTRIM(order_estimated_delivery_date)), ''), 120)) AS estimated_max
FROM   bronze.orders;

/* ---------- 5. Check list: how many rows are affected per problem? ---------- */
;WITH t AS (
    SELECT order_id, customer_id, order_status,
           order_purchase_timestamp, order_approved_at, order_delivered_carrier_date,
           order_delivered_customer_date, order_estimated_delivery_date,
           TRY_CONVERT(DATETIME2(0), NULLIF(LTRIM(RTRIM(order_purchase_timestamp)), ''), 120)      AS purchase_ts,
           TRY_CONVERT(DATETIME2(0), NULLIF(LTRIM(RTRIM(order_approved_at)), ''), 120)             AS approved_ts,
           TRY_CONVERT(DATETIME2(0), NULLIF(LTRIM(RTRIM(order_delivered_carrier_date)), ''), 120)  AS carrier_ts,
           TRY_CONVERT(DATETIME2(0), NULLIF(LTRIM(RTRIM(order_delivered_customer_date)), ''), 120) AS customer_ts,
           TRY_CONVERT(DATETIME2(0), NULLIF(LTRIM(RTRIM(order_estimated_delivery_date)), ''), 120) AS estimated_ts
    FROM   bronze.orders
)
SELECT 'order_id empty/NULL'                    AS check_name, COUNT(*) AS affected_rows FROM t WHERE NULLIF(LTRIM(RTRIM(order_id)), '') IS NULL
UNION ALL SELECT 'order_id length <> 32',          COUNT(*) FROM t WHERE LEN(LTRIM(RTRIM(order_id))) <> 32
UNION ALL SELECT 'customer_id empty/NULL',         COUNT(*) FROM t WHERE NULLIF(LTRIM(RTRIM(customer_id)), '') IS NULL
UNION ALL SELECT 'order_status empty/NULL',        COUNT(*) FROM t WHERE NULLIF(LTRIM(RTRIM(order_status)), '') IS NULL
UNION ALL SELECT 'leading/trailing spaces (any text column)', COUNT(*) FROM t
          WHERE order_id <> LTRIM(RTRIM(order_id)) OR customer_id <> LTRIM(RTRIM(customer_id)) OR order_status <> LTRIM(RTRIM(order_status))
UNION ALL SELECT 'status not in known list',       COUNT(*) FROM t
          WHERE LOWER(LTRIM(RTRIM(order_status))) NOT IN ('created','approved','invoiced','processing','shipped','delivered','unavailable','canceled')
UNION ALL SELECT 'purchase_ts empty',              COUNT(*) FROM t WHERE NULLIF(LTRIM(RTRIM(order_purchase_timestamp)), '') IS NULL
UNION ALL SELECT 'purchase_ts not convertible',    COUNT(*) FROM t WHERE NULLIF(LTRIM(RTRIM(order_purchase_timestamp)), '') IS NOT NULL AND purchase_ts IS NULL
UNION ALL SELECT 'approved_ts not convertible',    COUNT(*) FROM t WHERE NULLIF(LTRIM(RTRIM(order_approved_at)), '') IS NOT NULL AND approved_ts IS NULL
UNION ALL SELECT 'carrier_ts not convertible',     COUNT(*) FROM t WHERE NULLIF(LTRIM(RTRIM(order_delivered_carrier_date)), '') IS NOT NULL AND carrier_ts IS NULL
UNION ALL SELECT 'customer_ts not convertible',    COUNT(*) FROM t WHERE NULLIF(LTRIM(RTRIM(order_delivered_customer_date)), '') IS NOT NULL AND customer_ts IS NULL
UNION ALL SELECT 'estimated_ts not convertible',   COUNT(*) FROM t WHERE NULLIF(LTRIM(RTRIM(order_estimated_delivery_date)), '') IS NOT NULL AND estimated_ts IS NULL
UNION ALL SELECT 'approved before purchase',       COUNT(*) FROM t WHERE approved_ts < purchase_ts
UNION ALL SELECT 'carrier before approved',        COUNT(*) FROM t WHERE carrier_ts < approved_ts
UNION ALL SELECT 'customer delivery before carrier', COUNT(*) FROM t WHERE customer_ts < carrier_ts
UNION ALL SELECT 'delivered but no delivery date', COUNT(*) FROM t WHERE LOWER(LTRIM(RTRIM(order_status))) = 'delivered' AND customer_ts IS NULL
UNION ALL SELECT 'delivery date but status not delivered', COUNT(*) FROM t WHERE LOWER(LTRIM(RTRIM(order_status))) <> 'delivered' AND customer_ts IS NOT NULL
UNION ALL SELECT 'customer_id not found in bronze.customers', COUNT(*) FROM t
          WHERE NOT EXISTS (SELECT 1 FROM bronze.customers c WHERE c.customer_id = t.customer_id);

/* ---------- 6. Examples for the interesting cases (adjust the WHERE as needed) ---------- */
SELECT TOP (20) *
FROM   bronze.orders
WHERE  LOWER(LTRIM(RTRIM(order_status))) = 'delivered'
  AND  NULLIF(LTRIM(RTRIM(order_delivered_customer_date)), '') IS NULL;
