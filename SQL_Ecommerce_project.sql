-- Query 01: Calculate total visit, pageview, transaction for Jan, Feb and March 2017 (order by month)
SELECT 
  FORMAT_DATE('%Y%m',PARSE_DATE('%Y%m%d', date)) AS month
  ,SUM(totals.visits) AS visits
  ,SUM(totals.pageviews) AS pageviews
  ,SUM(totals.transactions) AS transactions
FROM `bigquery-public-data.google_analytics_sample.ga_sessions_2017*`
WHERE FORMAT_DATE('%Y%m',PARSE_DATE('%Y%m%d', date)) IN ('201701','201702','201703')
GROUP BY 1
ORDER BY month;

-- Query 02: Bounce rate per traffic source in July 2017 (Bounce_rate = num_bounce/total_visit) (order by total_visit DESC)
SELECT 
  trafficSource.source
  ,SUM(totals.visits) AS total_visits
  ,SUM(totals.bounces) AS total_bounces
  ,SUM(totals.bounces)*100/SUM(totals.visits) AS bounce_rate
FROM `bigquery-public-data.google_analytics_sample.ga_sessions_201707*`
GROUP BY 1
ORDER BY 2 DESC;

-- Query 3: Revenue by traffic source by week, by month in June 2017
WITH 
month AS (
  SELECT  
    'Month' AS time_type
    ,CONCAT(FORMAT_DATE('%Y%m',PARSE_DATE('%Y%m%d', date)),'-M') AS time_
    ,trafficSource.source AS traffic_source
    ,SUM(productRevenue)/1000000 AS revenue
  FROM `bigquery-public-data.google_analytics_sample.ga_sessions_201706*`
  ,UNNEST (hits) AS hits
  ,UNNEST (hits.product) AS product
  GROUP BY 1,2,3
)
,week AS (
  SELECT  
    'Week' AS time_type
    ,CONCAT(FORMAT_DATE('%Y%W',PARSE_DATE('%Y%m%d', date)),'-W') AS time_
    ,trafficSource.source AS traffic_source
    ,SUM(productRevenue)/1000000 AS revenue
  FROM `bigquery-public-data.google_analytics_sample.ga_sessions_201706*`
  ,UNNEST (hits) AS hits
  ,UNNEST (hits.product) AS product
  GROUP BY 1,2,3
)

SELECT * FROM month WHERE revenue IS NOT NULL
UNION ALL 
SELECT * FROM week WHERE revenue IS NOT NULL
ORDER BY traffic_source, time_;

-- Query 04: Average number of pageviews by purchaser type (purchasers vs non-purchasers) in June, July 2017.
WITH purchasers AS(
  SELECT
    FORMAT_DATE('%Y-%m', PARSE_DATE('%Y%m%d', date)) AS month
    ,SUM(totals.pageviews)/COUNT(DISTINCT fullVisitorId) AS avg_pageviews_purchase
  FROM `bigquery-public-data.google_analytics_sample.ga_sessions_2017*`
  ,UNNEST (hits) AS hits
  ,UNNEST (hits.product) AS product
  WHERE _table_suffix BETWEEN '0601' AND '0731'
  AND totals.transactions IS NOT NULL AND productRevenue IS NOT NULL
  GROUP BY 1
)
,non_purchasers AS(
  SELECT
    FORMAT_DATE('%Y-%m', PARSE_DATE('%Y%m%d', date)) AS month
    ,SUM(totals.pageviews)/COUNT(DISTINCT fullVisitorId) AS avg_pageviews_non_purchase
  FROM `bigquery-public-data.google_analytics_sample.ga_sessions_2017*`
  ,UNNEST (hits) AS hits
  ,UNNEST (hits.product) AS product
  WHERE _table_suffix BETWEEN '0601' AND '0731'
  AND totals.transactions IS NULL AND productRevenue IS NULL
  GROUP BY 1
)
SELECT
  p.month
  ,avg_pageviews_purchase
  ,avg_pageviews_non_purchase
FROM purchasers AS p 
FULL JOIN non_purchasers AS np USING (month)
ORDER BY p.month;

-- Query 05: Average number of transactions per user that made a purchase in July 2017
SELECT 
  FORMAT_DATE('%Y-%m', PARSE_DATE('%Y%m%d',date)) AS month
  ,SUM(totals.transactions)/COUNT(DISTINCT fullVisitorId) AS Avg_total_transactions_per_user
FROM `bigquery-public-data.google_analytics_sample.ga_sessions_201707*`
,UNNEST (hits) AS hits
,UNNEST (hits.product) AS product
WHERE totals.transactions IS NOT NULL 
  AND productRevenue IS NOT NULL
GROUP BY 1;

-- Query 06: Average amount of money spent per session. Only include purchaser data in July 2017
SELECT 
  FORMAT_DATE('%Y-%m', PARSE_DATE('%Y%m%d',date)) AS month
  ,(SUM(productRevenue)/1000000)/COUNT(totals.visits) avg_revenue_by_user_per_visit
FROM `bigquery-public-data.google_analytics_sample.ga_sessions_201707*`
,UNNEST (hits) AS hits
,UNNEST (hits.product) AS product
WHERE totals.transactions IS NOT NULL
  AND productRevenue IS NOT NULL
GROUP BY 1;

-- Query 07: Other products purchased by customers who purchased product "YouTube Men's Vintage Henley" in July 2017. Output should show product name and the quantity was ordered.
WITH user_id AS (
  SELECT DISTINCT fullVisitorId
  FROM `bigquery-public-data.google_analytics_sample.ga_sessions_201707*`
  ,UNNEST (hits) AS hits
  ,UNNEST (hits.product) AS product
  WHERE productRevenue IS NOT NULL
    AND v2ProductName IN ("YouTube Men's Vintage Henley")
)
SELECT
  v2ProductName AS other_purchased_products
  ,SUM(productQuantity) AS quantity
FROM `bigquery-public-data.google_analytics_sample.ga_sessions_201707*`
INNER JOIN user_id USING(fullVisitorId)
,UNNEST (hits) AS hits
,UNNEST (hits.product) AS product
WHERE productRevenue IS NOT NULL
  AND v2ProductName NOT IN ("YouTube Men's Vintage Henley")
GROUP BY 1
ORDER BY 2 DESC;

--Query 08: Calculate cohort map from product view to addtocart to purchase in Jan, Feb and March 2017. 
-- For example, 100% product view then 40% add_to_cart and 10% purchase.
-- Add_to_cart_rate = number product  add to cart/number product view. 
-- Purchase_rate = number product purchase/number product view. 
-- The output should be calculated in product level.

-- Option1:
WITH product_data AS(
  SELECT 
    FORMAT_DATE('%Y%m', PARSE_DATE('%Y%m%d', date)) AS month
    ,SUM(CASE WHEN eCommerceAction.action_type = '2' THEN 1 ELSE 0 END) AS num_product_view
    ,SUM(CASE WHEN eCommerceAction.action_type = '3' THEN 1 ELSE 0 END) AS num_addtocart
    ,SUM(CASE WHEN eCommerceAction.action_type = '6' AND product.productRevenue IS NOT NULL THEN 1 ELSE 0 END) AS num_purchase
  FROM `bigquery-public-data.google_analytics_sample.ga_sessions_2017*`
  ,UNNEST (hits) AS hits
  ,UNNEST (hits.product) AS product
  WHERE _table_suffix BETWEEN '0101' AND '0331'
    AND eCommerceAction.action_type IN ('2','3','6')
  GROUP BY 1
  ORDER BY 1
)
SELECT 
  *
  ,ROUND(num_addtocart*100.00/num_product_view,2) AS add_to_cart_rate
  ,ROUND(num_purchase*100.00/num_product_view,2) AS purchase_rate
FROM product_data
ORDER BY month;

-- Option 2:
WITH product_view AS(
  SELECT 
    FORMAT_DATE('%Y_%m',PARSE_DATE('%Y%m%d',date)) AS month
    ,COUNT(eCommerceAction.action_type) AS num_product_view
  FROM `bigquery-public-data.google_analytics_sample.ga_sessions_2017*`
  ,UNNEST (hits) AS hit
  WHERE _table_suffix BETWEEN '0101' AND '0331'
    AND eCommerceAction.action_type = '2'
  GROUP BY 1
)
,add_to_cart AS(
  SELECT 
    FORMAT_DATE('%Y_%m',PARSE_DATE('%Y%m%d',date)) AS month
    ,COUNT(eCommerceAction.action_type) AS num_add_to_cart
  FROM `bigquery-public-data.google_analytics_sample.ga_sessions_2017*`
  ,UNNEST (hits) AS hit
  WHERE _table_suffix BETWEEN '0101' AND '0331'
    AND eCommerceAction.action_type = '3'
  GROUP BY 1
)
,purchase AS (
SELECT 
    FORMAT_DATE('%Y_%m',PARSE_DATE('%Y%m%d',date)) AS month
    ,COUNT(eCommerceAction.action_type) AS num_purchase
  FROM `bigquery-public-data.google_analytics_sample.ga_sessions_2017*`
  ,UNNEST (hits) AS hits
  ,UNNEST (hits.product) AS product
  WHERE _table_suffix BETWEEN '0101' AND '0331'
    AND eCommerceAction.action_type = '6'
    AND productRevenue IS NOT NULL
  GROUP BY 1
)
SELECT
  v.month
  ,v.num_product_view
  ,a.num_add_to_cart
  ,p.num_purchase
  ,a.num_add_to_cart*100/v.num_product_view AS add_to_cart_rate
  ,p.num_purchase*100/v.num_product_view AS purchase_rate
FROM product_view AS v
INNER JOIN add_to_cart AS a USING (month)
INNER JOIN purchase AS p USING (month)
ORDER BY 1;
