-- Create a Base Table
CREATE VIEW vw_Cleaned_Orders AS
SELECT 
    c.customer_unique_id,
    o.order_id,
    o.order_purchase_timestamp, -- Keep the full timestamp for precision
    CAST(o.order_purchase_timestamp AS DATE) AS order_date, -- Good for grouping
    p.total_order_value
FROM orders o
JOIN customers c 
    ON o.customer_id = c.customer_id
JOIN (
    SELECT 
        order_id, 
        SUM(payment_value) AS total_order_value
    FROM order_payments
    GROUP BY order_id
) p 
    ON o.order_id = p.order_id
WHERE o.order_status = 'delivered'
AND o.order_purchase_timestamp IS NOT NULL;


-- Find the Reference Date
SELECT MAX(order_date) AS max_date
FROM vw_Cleaned_Orders;



-- Create RFM Base Table
CREATE VIEW vw_RFM_Base AS
SELECT 
    customer_unique_id,
    
    COUNT(DISTINCT order_id) AS frequency,
    
    SUM(total_order_value) AS monetary,
    
    MAX(order_date) AS last_purchase_date,
    
    DATEDIFF(
        DAY, 
        MAX(order_date), 
        (SELECT MAX(order_date) FROM vw_Cleaned_Orders)
    ) AS recency

FROM vw_Cleaned_Orders
GROUP BY customer_unique_id;

-- Validate
SELECT TOP 10 * FROM vw_RFM_Base;



-- Create RFM Scoring View
CREATE VIEW vw_RFM_Scores AS
SELECT *,
    
    -- Recency Score (lower recency = better -> DESC)
    NTILE(5) OVER (ORDER BY recency DESC) AS R_score,
    
    -- Frequency Score (higher = better)
    NTILE(5) OVER (ORDER BY frequency ASC) AS F_score,
    
    -- Monetary Score (higher = better)
    NTILE(5) OVER (ORDER BY monetary ASC) AS M_score

FROM vw_RFM_Base;

-- Validate Scores
SELECT 
    MIN(R_score), MAX(R_score),
    MIN(F_score), MAX(F_score),
    MIN(M_score), MAX(M_score)
FROM vw_RFM_Scores;

-- Preview
SELECT TOP 20 * 
FROM vw_RFM_Scores
ORDER BY R_score DESC, F_score DESC, M_score DESC;



-- Create Customer Segmentation
CREATE  VIEW vw_RFM_Segments AS
SELECT 
    *,

    -- RFM Cell (for heatmap / matrix)
    CONCAT(R_score, F_score, M_score) AS rfm_cell,

    -- Retention Flag (behavior insight)
    CASE 
        WHEN frequency > 1 THEN 1 
        ELSE 0 
    END AS is_repeat_customer,

    -- Churn Indicator (business KPI)
    CASE 
        WHEN recency > 365 THEN 1 
        ELSE 0 
    END AS is_churned,

    -- Customer Segmentation
CASE 
    -- Best Customers
    WHEN R_score = 5 AND F_score = 5 THEN 'Champions'
    WHEN R_score >= 4 AND F_score >= 4 THEN 'Loyal Customers'
    
    -- Potential and Growth
    WHEN R_score >= 4 AND F_score >= 2 THEN 'Potential Loyalists'
    WHEN R_score = 5 AND F_score = 1 THEN 'New Customers'
    WHEN R_score = 4 AND F_score = 1 THEN 'Promising'
    WHEN R_score = 3 AND F_score >= 3 THEN 'Needs Attention'
    
    -- At Risk
    WHEN R_score = 3 AND F_score BETWEEN 1 AND 2 THEN 'About to Sleep'
    WHEN R_score <= 2 AND F_score >= 4 THEN 'Cannot Lose Them'
    WHEN R_score <= 2 AND F_score = 3 THEN 'At Risk'
    
    -- Lost
    WHEN R_score = 2 AND F_score <= 2 THEN 'Hibernating'
    WHEN R_score = 1 AND F_score <= 2 THEN 'Lost'
    
    ELSE 'Hibernating'
END AS customer_segment,

    -- Value Tier (monetary importance)
    CASE 
        WHEN M_score >= 4 THEN 'High Value'
        WHEN M_score = 3 THEN 'Mid Value'
        ELSE 'Low Value'
    END AS value_tier

FROM vw_RFM_Scores;


--Validate Segments
SELECT 
    customer_segment, 
    COUNT(*) AS customers
FROM vw_RFM_Segments
GROUP BY customer_segment
ORDER BY customers DESC;

SELECT 
    customer_segment, 
    SUM(monetary) AS revenue
FROM vw_RFM_Segments
GROUP BY customer_segment
ORDER BY revenue DESC;




