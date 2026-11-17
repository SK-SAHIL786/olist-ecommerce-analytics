

/*
============================================================
 PROJECT NAME : OLIST E-COMMERCE ANALYTICS
 FILE NAME    : queries.sql
 DATABASE     : SQLite
 PURPOSE      : Business Intelligence and Data Analysis
============================================================

 ANALYSIS COVERAGE:
 01. Executive Business KPIs
 02. Monthly Revenue and Order Trends
 03. Product Category Performance
 04. State-wise Customer and Revenue Analysis
 05. Customer Retention Analysis
 06. Delivery Performance Analysis
 07. Late Delivery and Customer Satisfaction
 08. Payment Method Analysis
 09. Customer Purchasing Behaviour
 10. Product Category Review Analysis
 11. Seller Performance Analysis
 12. Seller State Performance

 IMPORTANT:
 Revenue in these queries uses product price only.
 Freight charges are excluded unless stated otherwise.

============================================================
*/


-- ==========================================================
-- QUERY 01: EXECUTIVE BUSINESS PERFORMANCE
-- Purpose: Calculate important business KPIs.
-- ==========================================================

SELECT
    COUNT(DISTINCT o.order_id) AS total_orders,

    COUNT(DISTINCT CASE
        WHEN o.order_status = 'delivered'
        THEN o.order_id
    END) AS delivered_orders,

    ROUND(
        SUM(CASE
            WHEN o.order_status = 'delivered'
            THEN oi.price
            ELSE 0
        END), 2
    ) AS delivered_revenue,

    ROUND(
        AVG(CASE
            WHEN o.order_status = 'delivered'
            THEN julianday(o.order_delivered_customer_date)
                 - julianday(o.order_purchase_timestamp)
        END), 2
    ) AS average_delivery_days

FROM orders AS o

LEFT JOIN order_items AS oi
    ON o.order_id = oi.order_id;


-- ==========================================================
-- QUERY 02: MONTHLY REVENUE AND ORDER TRENDS
-- Purpose: Identify monthly sales performance.
-- ==========================================================

SELECT
    strftime('%Y-%m', o.order_purchase_timestamp) AS order_month,

    COUNT(DISTINCT o.order_id) AS total_orders,

    ROUND(SUM(oi.price), 2) AS monthly_revenue,

    ROUND(AVG(oi.price), 2) AS average_item_price

FROM orders AS o

JOIN order_items AS oi
    ON o.order_id = oi.order_id

WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp IS NOT NULL

GROUP BY strftime('%Y-%m', o.order_purchase_timestamp)

ORDER BY order_month;


-- ==========================================================
-- QUERY 03: TOP 10 PRODUCT CATEGORIES BY REVENUE
-- Purpose: Find the most profitable product categories.
-- ==========================================================

SELECT
    COALESCE(
        t.product_category_name_english,
        p.product_category_name,
        'Unknown'
    ) AS product_category,

    COUNT(DISTINCT oi.order_id) AS total_orders,

    COUNT(oi.order_item_id) AS total_items_sold,

    ROUND(SUM(oi.price), 2) AS total_revenue,

    ROUND(AVG(oi.price), 2) AS average_item_price

FROM order_items AS oi

JOIN orders AS o
    ON oi.order_id = o.order_id

JOIN products AS p
    ON oi.product_id = p.product_id

LEFT JOIN category_translation AS t
    ON p.product_category_name = t.product_category_name

WHERE o.order_status = 'delivered'

GROUP BY product_category

ORDER BY total_revenue DESC

LIMIT 10;


-- ==========================================================
-- QUERY 04: STATE-WISE CUSTOMER AND REVENUE ANALYSIS
-- Purpose: Identify the strongest customer markets.
-- ==========================================================

SELECT
    c.customer_state AS state,

    COUNT(DISTINCT c.customer_unique_id) AS total_customers,

    COUNT(DISTINCT o.order_id) AS total_orders,

    ROUND(SUM(oi.price), 2) AS total_revenue,

    ROUND(
        SUM(oi.price) * 1.0 /
        NULLIF(COUNT(DISTINCT o.order_id), 0), 2
    ) AS revenue_per_order

FROM customers AS c

JOIN orders AS o
    ON c.customer_id = o.customer_id

JOIN order_items AS oi
    ON o.order_id = oi.order_id

WHERE o.order_status = 'delivered'

GROUP BY c.customer_state

ORDER BY total_revenue DESC;


-- ==========================================================
-- QUERY 05: CUSTOMER RETENTION AND REPEAT PURCHASE ANALYSIS
-- Purpose: Measure customer loyalty and repeat purchasing.
-- ==========================================================

WITH customer_orders AS (

    SELECT
        c.customer_unique_id,

        COUNT(DISTINCT o.order_id) AS total_orders

    FROM customers AS c

    JOIN orders AS o
        ON c.customer_id = o.customer_id

    WHERE o.order_status = 'delivered'

    GROUP BY c.customer_unique_id
)

SELECT
    COUNT(*) AS total_unique_customers,

    SUM(CASE
        WHEN total_orders = 1 THEN 1
        ELSE 0
    END) AS one_time_customers,

    SUM(CASE
        WHEN total_orders > 1 THEN 1
        ELSE 0
    END) AS repeat_customers,

    ROUND(
        100.0 * SUM(CASE
            WHEN total_orders > 1 THEN 1
            ELSE 0
        END) / NULLIF(COUNT(*), 0), 2
    ) AS repeat_customer_percentage

FROM customer_orders;


-- ==========================================================
-- QUERY 06: DELIVERY PERFORMANCE ANALYSIS
-- Purpose: Calculate average delivery time by state.
-- ==========================================================

WITH delivery_data AS (

    SELECT
        o.order_id,

        c.customer_state AS state,

        julianday(o.order_delivered_customer_date)
        - julianday(o.order_purchase_timestamp)
        AS delivery_days

    FROM orders AS o

    JOIN customers AS c
        ON o.customer_id = c.customer_id

    WHERE o.order_status = 'delivered'

      AND o.order_delivered_customer_date IS NOT NULL

      AND o.order_purchase_timestamp IS NOT NULL
)

SELECT
    state,

    COUNT(DISTINCT order_id) AS delivered_orders,

    ROUND(AVG(delivery_days), 2) AS average_delivery_days,

    ROUND(MIN(delivery_days), 2) AS minimum_delivery_days,

    ROUND(MAX(delivery_days), 2) AS maximum_delivery_days

FROM delivery_data

GROUP BY state

ORDER BY average_delivery_days DESC;


-- ==========================================================
-- QUERY 07: ON-TIME VS LATE DELIVERY ANALYSIS
-- Purpose: Measure delivery reliability.
-- ==========================================================

SELECT
    CASE
        WHEN o.order_delivered_customer_date >
             o.order_estimated_delivery_date
        THEN 'Late Delivery'

        ELSE 'On-Time Delivery'
    END AS delivery_status,

    COUNT(DISTINCT o.order_id) AS total_orders,

    ROUND(
        100.0 * COUNT(DISTINCT o.order_id) /
        SUM(COUNT(DISTINCT o.order_id)) OVER (), 2
    ) AS order_percentage

FROM orders AS o

WHERE o.order_status = 'delivered'

  AND o.order_delivered_customer_date IS NOT NULL

  AND o.order_estimated_delivery_date IS NOT NULL

GROUP BY delivery_status

ORDER BY total_orders DESC;


-- ==========================================================
-- QUERY 08: LATE DELIVERY VS CUSTOMER REVIEW ANALYSIS
-- Purpose: Understand the relationship between delivery
--          performance and customer satisfaction.
-- ==========================================================

WITH review_per_order AS (

    SELECT
        order_id,

        AVG(review_score) AS average_review_score

    FROM order_reviews

    WHERE review_score IS NOT NULL

    GROUP BY order_id
)

SELECT
    CASE
        WHEN o.order_delivered_customer_date >
             o.order_estimated_delivery_date
        THEN 'Late Delivery'

        ELSE 'On-Time Delivery'
    END AS delivery_status,

    COUNT(DISTINCT o.order_id) AS total_orders,

    ROUND(AVG(r.average_review_score), 2)
        AS average_review_score

FROM orders AS o

JOIN review_per_order AS r
    ON o.order_id = r.order_id

WHERE o.order_status = 'delivered'

  AND o.order_delivered_customer_date IS NOT NULL

  AND o.order_estimated_delivery_date IS NOT NULL

GROUP BY delivery_status

ORDER BY average_review_score DESC;


-- ==========================================================
-- QUERY 09: PAYMENT METHOD AND INSTALLMENT ANALYSIS
-- Purpose: Understand customer payment preferences.
-- ==========================================================

SELECT
    payment_type,

    COUNT(DISTINCT order_id) AS total_orders,

    SUM(payment_installments) AS total_installments,

    ROUND(SUM(payment_value), 2) AS total_payment_value,

    ROUND(AVG(payment_value), 2) AS average_payment_value

FROM order_payments

GROUP BY payment_type

ORDER BY total_payment_value DESC;


-- ==========================================================
-- QUERY 10: CUSTOMER PURCHASING BEHAVIOUR
-- Purpose: Identify popular purchase days and hours.
-- ==========================================================

SELECT
    CASE strftime('%w', order_purchase_timestamp)

        WHEN '0' THEN 'Sunday'
        WHEN '1' THEN 'Monday'
        WHEN '2' THEN 'Tuesday'
        WHEN '3' THEN 'Wednesday'
        WHEN '4' THEN 'Thursday'
        WHEN '5' THEN 'Friday'
        WHEN '6' THEN 'Saturday'

    END AS order_weekday,

    CAST(
        strftime('%w', order_purchase_timestamp)
        AS INTEGER
    ) AS weekday_number,

    CAST(
        strftime('%H', order_purchase_timestamp)
        AS INTEGER
    ) AS order_hour,

    COUNT(DISTINCT order_id) AS total_orders

FROM orders

WHERE order_purchase_timestamp IS NOT NULL

GROUP BY weekday_number, order_hour

ORDER BY weekday_number, order_hour;


-- ==========================================================
-- QUERY 11: CUSTOMER REVIEW SCORE BY PRODUCT CATEGORY
-- Purpose: Identify categories with better customer ratings.
-- ==========================================================

WITH review_per_order AS (

    SELECT
        order_id,

        AVG(review_score) AS average_review_score

    FROM order_reviews

    WHERE review_score IS NOT NULL

    GROUP BY order_id
),

order_category AS (

    SELECT DISTINCT
        oi.order_id,

        COALESCE(
            t.product_category_name_english,
            p.product_category_name,
            'Unknown'
        ) AS product_category

    FROM order_items AS oi

    JOIN products AS p
        ON oi.product_id = p.product_id

    LEFT JOIN category_translation AS t
        ON p.product_category_name =
           t.product_category_name
)

SELECT
    oc.product_category,

    COUNT(DISTINCT oc.order_id) AS total_orders,

    ROUND(
        AVG(r.average_review_score), 2
    ) AS average_review_score

FROM order_category AS oc

JOIN review_per_order AS r
    ON oc.order_id = r.order_id

GROUP BY oc.product_category

ORDER BY average_review_score DESC;


-- ==========================================================
-- QUERY 12: TOP 10 SELLERS BY DELIVERED REVENUE
-- Purpose: Identify high-performing sellers.
-- ==========================================================

SELECT
    s.seller_id,

    s.seller_state,

    COUNT(DISTINCT o.order_id) AS total_orders,

    COUNT(oi.order_item_id) AS total_items_sold,

    ROUND(SUM(oi.price), 2) AS total_revenue,

    ROUND(AVG(oi.price), 2) AS average_item_price

FROM sellers AS s

JOIN order_items AS oi
    ON s.seller_id = oi.seller_id

JOIN orders AS o
    ON oi.order_id = o.order_id

WHERE o.order_status = 'delivered'

GROUP BY
    s.seller_id,
    s.seller_state

ORDER BY total_revenue DESC

LIMIT 10;


-- ==========================================================
-- QUERY 13: SELLER STATE PERFORMANCE
-- Purpose: Compare seller performance by state.
-- ==========================================================

SELECT
    s.seller_state AS state,

    COUNT(DISTINCT s.seller_id) AS total_sellers,

    COUNT(DISTINCT o.order_id) AS total_orders,

    COUNT(oi.order_item_id) AS total_items_sold,

    ROUND(SUM(oi.price), 2) AS total_revenue

FROM sellers AS s

JOIN order_items AS oi
    ON s.seller_id = oi.seller_id

JOIN orders AS o
    ON oi.order_id = o.order_id

WHERE o.order_status = 'delivered'

GROUP BY s.seller_state

ORDER BY total_revenue DESC;


-- ==========================================================
-- END OF OLIST E-COMMERCE ANALYTICS SQL QUERIES
-- ==========================================================
