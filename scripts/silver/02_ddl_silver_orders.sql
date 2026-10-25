USE OlistDW;
GO

IF OBJECT_ID('silver.orders', 'U') IS NOT NULL DROP TABLE silver.orders;
GO

CREATE TABLE silver.orders (
    order_id                      VARCHAR(32)  NOT NULL PRIMARY KEY,
    customer_id                   VARCHAR(32)  NOT NULL,
    order_status                  VARCHAR(20)  NOT NULL,
    order_purchase_ts             DATETIME2(0) NULL,
    order_approved_ts             DATETIME2(0) NULL,
    order_delivered_carrier_ts    DATETIME2(0) NULL,
    order_delivered_customer_ts   DATETIME2(0) NULL,
    order_estimated_delivery_ts   DATETIME2(0) NULL,

    -- Data-Quality-Flags (1 = Auffälligkeit)
    dq_delivered_without_date     BIT NOT NULL,  -- Status delivered, aber kein Lieferdatum
    dq_delivery_before_carrier    BIT NOT NULL,  -- Kundenlieferung vor Carrier-Übergabe
    dq_carrier_before_approval    BIT NOT NULL,  -- Info: Carrier vor Genehmigung
    dq_status_date_mismatch       BIT NOT NULL,  -- Lieferdatum, aber Status nicht delivered

    source_load_date              DATETIME2    NOT NULL,
    silver_load_date              DATETIME2    NOT NULL DEFAULT SYSDATETIME()
);
GO

;WITH cleaned AS (
    SELECT
        LOWER(TRIM(order_id))                  AS order_id,
        LOWER(TRIM(customer_id))               AS customer_id,
        LOWER(NULLIF(TRIM(order_status), ''))  AS order_status,
        TRY_CONVERT(DATETIME2(0), NULLIF(TRIM(order_purchase_timestamp), ''), 120)      AS purchase_ts,
        TRY_CONVERT(DATETIME2(0), NULLIF(TRIM(order_approved_at), ''), 120)             AS approved_ts,
        TRY_CONVERT(DATETIME2(0), NULLIF(TRIM(order_delivered_carrier_date), ''), 120)  AS carrier_ts,
        TRY_CONVERT(DATETIME2(0), NULLIF(TRIM(order_delivered_customer_date), ''), 120) AS customer_ts,
        TRY_CONVERT(DATETIME2(0), NULLIF(TRIM(order_estimated_delivery_date), ''), 120) AS estimated_ts,
        load_date AS source_load_date
    FROM bronze.orders
),
dedup AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY source_load_date DESC) AS rn
    FROM cleaned
    WHERE order_id IS NOT NULL AND customer_id IS NOT NULL
)
INSERT INTO silver.orders
    (order_id, customer_id, order_status,
     order_purchase_ts, order_approved_ts, order_delivered_carrier_ts,
     order_delivered_customer_ts, order_estimated_delivery_ts,
     dq_delivered_without_date, dq_delivery_before_carrier,
     dq_carrier_before_approval, dq_status_date_mismatch,
     source_load_date)
SELECT
    order_id,
    customer_id,
    ISNULL(order_status, 'unknown'),
    purchase_ts, approved_ts, carrier_ts, customer_ts, estimated_ts,

    CASE WHEN order_status = 'delivered' AND customer_ts IS NULL
         THEN 1 ELSE 0 END,
    CASE WHEN customer_ts IS NOT NULL AND carrier_ts IS NOT NULL
              AND customer_ts < carrier_ts
         THEN 1 ELSE 0 END,
    CASE WHEN carrier_ts IS NOT NULL AND approved_ts IS NOT NULL
              AND carrier_ts < approved_ts
         THEN 1 ELSE 0 END,
    CASE WHEN customer_ts IS NOT NULL
              AND order_status NOT IN ('delivered','canceled','unavailable')
         THEN 1 ELSE 0 END,

    source_load_date
FROM dedup
WHERE rn = 1;
GO

-- Kontrolle
SELECT
    COUNT(*)                         AS zeilen,
    SUM(CAST(dq_delivered_without_date  AS INT)) AS delivered_ohne_datum,   -- erwartet 8
    SUM(CAST(dq_delivery_before_carrier AS INT)) AS lieferung_vor_carrier,  -- erwartet 23
    SUM(CAST(dq_carrier_before_approval AS INT)) AS carrier_vor_genehmigung,-- erwartet 1359
    SUM(CAST(dq_status_date_mismatch    AS INT)) AS status_datum_konflikt   -- erwartet 6
FROM silver.orders;


UPDATE silver.orders
SET dq_status_date_mismatch = 1
WHERE order_delivered_customer_ts IS NOT NULL
  AND order_status <> 'delivered';

-- Kontrolle: erwartet 6
SELECT order_status, COUNT(*) AS anzahl
FROM silver.orders
WHERE dq_status_date_mismatch = 1
GROUP BY order_status;

CASE WHEN customer_ts IS NOT NULL AND order_status <> 'delivered'
     THEN 1 ELSE 0 END,
