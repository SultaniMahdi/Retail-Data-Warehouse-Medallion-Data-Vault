/*
===============================================================================
DDL-Skript: Bronze-Schicht (Olist Brazilian E-Commerce)
Zweck : Legt das Schema und alle Bronze-Tabellen an.
        Vorhandene Tabellen werden gelöscht und neu erstellt.
Achtung: Dieses Skript löscht alle Daten in den Bronze-Tabellen.
         Nur bei Strukturänderungen ausführen, danach bronze.load_bronze starten.
===============================================================================
*/

-- Schema anlegen, falls es fehlt
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'bronze')
    EXEC('CREATE SCHEMA bronze');
GO

/* ============ 1. orders ============ */
DROP TABLE IF EXISTS bronze.orders;
GO
CREATE TABLE bronze.orders (
    order_id NVARCHAR(50),
    customer_id NVARCHAR(50),
    order_status NVARCHAR(50),
    order_purchase_timestamp NVARCHAR(50),
    order_approved_at NVARCHAR(50),
    order_delivered_carrier_date NVARCHAR(50),
    order_delivered_customer_date NVARCHAR(50),
    order_estimated_delivery_date NVARCHAR(50),
    load_date DATETIME2 DEFAULT SYSDATETIME(),
    record_source NVARCHAR(50) DEFAULT 'olist_orders.csv'
);
GO

/* ============ 2. customers ============ */
DROP TABLE IF EXISTS bronze.customers;
GO
CREATE TABLE bronze.customers (
    customer_id                 NVARCHAR(50),
    customer_unique_id          NVARCHAR(50),
    customer_zip_code_prefix    NVARCHAR(50),
    customer_city               NVARCHAR(100),
    customer_state              NVARCHAR(50),
    load_date                   DATETIME2 DEFAULT SYSDATETIME(),
    record_source               NVARCHAR(50) DEFAULT 'olist_customers.csv'
);
GO

/* ============ 3. geolocation ============ */
DROP TABLE IF EXISTS bronze.geolocation;
GO
CREATE TABLE bronze.geolocation (
    geolocation_zip_code_prefix NVARCHAR(50),
    geolocation_lat             NVARCHAR(50),
    geolocation_lng             NVARCHAR(50),
    geolocation_city            NVARCHAR(100),
    geolocation_state           NVARCHAR(50),
    load_date                   DATETIME2 DEFAULT SYSDATETIME(),
    record_source               NVARCHAR(50) DEFAULT 'olist_geolocation.csv'
);
GO

/* ============ 4. order_items ============ */
DROP TABLE IF EXISTS bronze.order_items;
GO
CREATE TABLE bronze.order_items (
    order_id                NVARCHAR(50),
    order_item_id           NVARCHAR(50),
    product_id              NVARCHAR(50),
    seller_id               NVARCHAR(50),
    shipping_limit_date     NVARCHAR(50),
    price                   NVARCHAR(50),
    freight_value           NVARCHAR(50),
    load_date               DATETIME2 DEFAULT SYSDATETIME(),
    record_source           NVARCHAR(50) DEFAULT 'olist_order_items.csv'
);
GO

/* ============ 5. order_payments ============ */
DROP TABLE IF EXISTS bronze.order_payments;
GO
CREATE TABLE bronze.order_payments (
    order_id                NVARCHAR(50),
    payment_sequential      NVARCHAR(50),
    payment_type            NVARCHAR(50),
    payment_installments    NVARCHAR(50),
    payment_value           NVARCHAR(50),
    load_date               DATETIME2 DEFAULT SYSDATETIME(),
    record_source           NVARCHAR(50) DEFAULT 'olist_order_payments.csv'
);
GO

/* ============ 6. order_reviews ============ */
DROP TABLE IF EXISTS bronze.order_reviews;
GO
CREATE TABLE bronze.order_reviews (
    review_id                   NVARCHAR(50),
    order_id                    NVARCHAR(50),
    review_score                NVARCHAR(50),
    review_comment_title        NVARCHAR(MAX),
    review_comment_message      NVARCHAR(MAX),
    review_creation_date        NVARCHAR(50),
    review_answer_timestamp     NVARCHAR(50),
    load_date                   DATETIME2 DEFAULT SYSDATETIME(),
    record_source               NVARCHAR(50) DEFAULT 'olist_order_reviews.csv'
);
GO

/* ============ 7. products ============ */
-- "lenght" (Tippfehler) bewusst wie in der Quelle belassen
DROP TABLE IF EXISTS bronze.products;
GO
CREATE TABLE bronze.products (
    product_id                      NVARCHAR(50),
    product_category_name           NVARCHAR(100),
    product_name_lenght             NVARCHAR(50),
    product_description_lenght      NVARCHAR(50),
    product_photos_qty              NVARCHAR(50),
    product_weight_g                NVARCHAR(50),
    product_length_cm               NVARCHAR(50),
    product_height_cm               NVARCHAR(50),
    product_width_cm                NVARCHAR(50),
    load_date                       DATETIME2 DEFAULT SYSDATETIME(),
    record_source                   NVARCHAR(50) DEFAULT 'olist_products.csv'
);
GO

/* ============ 8. sellers ============ */
DROP TABLE IF EXISTS bronze.sellers;
GO
CREATE TABLE bronze.sellers (
    seller_id                   NVARCHAR(50),
    seller_zip_code_prefix      NVARCHAR(50),
    seller_city                 NVARCHAR(100),
    seller_state                NVARCHAR(50),
    load_date                   DATETIME2 DEFAULT SYSDATETIME(),
    record_source               NVARCHAR(50) DEFAULT 'olist_sellers.csv'
);
GO

/* ============ 9. product_category_translation ============ */
DROP TABLE IF EXISTS bronze.product_category_translation;
GO
CREATE TABLE bronze.product_category_translation (
    product_category_name           NVARCHAR(100),
    product_category_name_english   NVARCHAR(100),
    load_date                       DATETIME2 DEFAULT SYSDATETIME(),
    record_source                   NVARCHAR(50) DEFAULT 'product_category_name_translation.csv'
);
GO




