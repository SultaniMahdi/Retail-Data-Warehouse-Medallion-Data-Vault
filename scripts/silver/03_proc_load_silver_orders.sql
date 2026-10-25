USE OlistDW;
GO

IF OBJECT_ID('silver.customers', 'U') IS NOT NULL DROP TABLE silver.customers;
GO

CREATE TABLE silver.customers (
    customer_id               VARCHAR(32)  NOT NULL PRIMARY KEY,  -- pro Bestellung
    customer_unique_id        VARCHAR(32)  NOT NULL,              -- echter Kunde
    customer_zip_code_prefix  CHAR(5)      NOT NULL,
    customer_city             VARCHAR(100) NOT NULL,
    customer_state            CHAR(2)      NOT NULL,

    -- Data-Quality-Flags
    dq_address_changes        BIT NOT NULL,  -- Kunde hat in anderen Bestellungen andere Adressdaten
    dq_no_matching_order      BIT NOT NULL,  -- customer_id kommt in silver.orders nicht vor

    source_load_date          DATETIME2    NOT NULL,
    silver_load_date          DATETIME2    NOT NULL DEFAULT SYSDATETIME()
);
GO

;WITH cleaned AS (
    SELECT
        LOWER(TRIM(customer_id))                        AS customer_id,
        LOWER(TRIM(customer_unique_id))                 AS customer_unique_id,
        NULLIF(TRIM(customer_zip_code_prefix), '')      AS zip,
        LOWER(NULLIF(TRIM(customer_city), ''))          AS city,
        UPPER(NULLIF(TRIM(customer_state), ''))         AS state,
        load_date                                       AS source_load_date
    FROM bronze.customers
),
dedup AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY customer_id
                              ORDER BY source_load_date DESC) AS rn
    FROM cleaned
    WHERE customer_id IS NOT NULL
      AND customer_unique_id IS NOT NULL
),
changes AS (
    SELECT customer_unique_id
    FROM dedup
    WHERE rn = 1
    GROUP BY customer_unique_id
    HAVING COUNT(DISTINCT zip)   > 1
        OR COUNT(DISTINCT city)  > 1
        OR COUNT(DISTINCT state) > 1
)
INSERT INTO silver.customers
    (customer_id, customer_unique_id, customer_zip_code_prefix,
     customer_city, customer_state,
     dq_address_changes, dq_no_matching_order, source_load_date)
SELECT
    d.customer_id,
    d.customer_unique_id,
    ISNULL(d.zip,   '00000'),
    ISNULL(d.city,  'unknown'),
    ISNULL(d.state, 'XX'),
    CASE WHEN ch.customer_unique_id IS NOT NULL THEN 1 ELSE 0 END,
    CASE WHEN o.customer_id IS NULL THEN 1 ELSE 0 END,
    d.source_load_date
FROM dedup AS d
LEFT JOIN changes       AS ch ON ch.customer_unique_id = d.customer_unique_id
LEFT JOIN silver.orders AS o  ON o.customer_id         = d.customer_id
WHERE d.rn = 1;
GO


--controlling
SELECT
    COUNT(*)                                        AS zeilen,                 -- erwartet 99441
    COUNT(DISTINCT customer_unique_id)              AS eindeutige_kunden,      -- erwartet 96096
    SUM(CAST(dq_no_matching_order AS INT))          AS ohne_bestellung         -- erwartet 0
FROM silver.customers;

-- erwartet 252
SELECT COUNT(DISTINCT customer_unique_id) AS kunden_mit_adresswechsel
FROM silver.customers
WHERE dq_address_changes = 1;

-- Stichprobe: so sieht ein Adresswechsel aus
SELECT TOP (10)
    c.customer_unique_id, c.customer_id,
    c.customer_zip_code_prefix, c.customer_city, c.customer_state,
    o.order_purchase_ts
FROM silver.customers AS c
JOIN silver.orders    AS o ON o.customer_id = c.customer_id
WHERE c.dq_address_changes = 1
ORDER BY c.customer_unique_id, o.order_purchase_ts;
