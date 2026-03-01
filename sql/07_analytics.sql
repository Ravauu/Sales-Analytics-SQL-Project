USE SalesPortfolio;
GO

/* =========================================================
   Analytics: Sales & Profit by ProductLine
   ========================================================= */
SELECT
    p.ProductLine,
    SUM(fs.Sales)  AS TotalSales,
    SUM(fs.Profit) AS TotalProfit
FROM dbo.fact_sales AS fs
JOIN dbo.dim_product AS p
    ON p.ProductKey = fs.ProductKey
GROUP BY
    p.ProductLine
ORDER BY
    TotalSales DESC;
GO

/* =========================================================
   Analytics: Top 10 Products by Sales
   ========================================================= */
SELECT TOP (10)
    p.ProductCode,
    p.ProductLine,
    SUM(fs.Sales)  AS TotalSales,
    SUM(fs.Profit) AS TotalProfit
FROM dbo.fact_sales AS fs
JOIN dbo.dim_product AS p
    ON p.ProductKey = fs.ProductKey
GROUP BY
    p.ProductCode,
    p.ProductLine
ORDER BY
    TotalSales DESC;
GO

/* =========================================================
   Analytics: Sales & Profit quarterly (Year + Quarter)
   ========================================================= */
SELECT
    d.[Year],
    d.[Quarter],
    SUM(fs.Sales)  AS TotalSales,
    SUM(fs.Profit) AS TotalProfit
FROM dbo.fact_sales AS fs
JOIN dbo.dim_date AS d
    ON d.DateKey = fs.DateKey
GROUP BY
    d.[Year],
    d.[Quarter]
ORDER BY
    d.[Year],
    d.[Quarter];
GO

/* =========================================================
   Analytics: Sales & Profit monthly (YearMonth)
   ========================================================= */
SELECT
    d.YearMonth,
    SUM(fs.Sales)  AS TotalSales,
    SUM(fs.Profit) AS TotalProfit
FROM dbo.fact_sales AS fs
JOIN dbo.dim_date AS d
    ON d.DateKey = fs.DateKey
GROUP BY
    d.YearMonth
ORDER BY
    d.YearMonth;
GO

/* =========================================================
   Analytics: YoY Sales Growth monthly (LAG 12)
   ========================================================= */
WITH Monthly AS
(
    SELECT
        d.YearMonth,
        SUM(fs.Sales) AS TotalSales
    FROM dbo.fact_sales AS fs
    JOIN dbo.dim_date AS d
        ON d.DateKey = fs.DateKey
    GROUP BY
        d.YearMonth
),
MonthlyWithLag AS
(
    SELECT
        YearMonth,
        TotalSales,
        LAG(TotalSales, 12) OVER (ORDER BY YearMonth) AS SalesLastYear
    FROM Monthly
)
SELECT
    YearMonth,
    TotalSales,
    SalesLastYear,
    CAST(
        100.0 * (TotalSales - SalesLastYear) / NULLIF(SalesLastYear, 0.0)
        AS decimal(12, 2)
    ) AS YoYGrowthPct
FROM MonthlyWithLag
ORDER BY
    YearMonth;
GO

/* =========================================================
   Analytics: Top 10 Customers by Sales & Profit
   ========================================================= */
SELECT TOP (10)
    c.CustomerName,
    c.Country,
    SUM(fs.Sales)  AS TotalSales,
    SUM(fs.Profit) AS TotalProfit
FROM dbo.fact_sales AS fs
JOIN dbo.dim_customer AS c
    ON c.CustomerKey = fs.CustomerKey
GROUP BY
    c.CustomerName,
    c.Country
ORDER BY
    TotalSales DESC;
GO

/* =========================================================
   Analytics: Weighted discount vs MSRP + weighted averages
   ========================================================= */
SELECT
    p.ProductLine,
    CAST(
        100.0 * SUM(fs.QuantityOrdered * (p.MSRP - fs.PriceEach))
        / NULLIF(SUM(fs.QuantityOrdered * p.MSRP), 0.0)
        AS decimal(10, 2)
    ) AS WeightedAvgDiscountPct,
    CAST(
        1.0 * SUM(fs.QuantityOrdered * fs.PriceEach)
        / NULLIF(SUM(fs.QuantityOrdered), 0)
        AS decimal(10, 2)
    ) AS WeightedAvgPrice,
    CAST(
        1.0 * SUM(fs.QuantityOrdered * p.MSRP)
        / NULLIF(SUM(fs.QuantityOrdered), 0)
        AS decimal(10, 2)
    ) AS WeightedAvgMSRP
FROM dbo.fact_sales AS fs
JOIN dbo.dim_product AS p
    ON p.ProductKey = fs.ProductKey
GROUP BY
    p.ProductLine
ORDER BY
    WeightedAvgDiscountPct DESC;
GO

/* =========================================================
   Analytics: OrderSize mix within ProductLine (share %)
   ========================================================= */
SELECT
    p.ProductLine,
    fs.OrderSize,
    COUNT(*) AS OrderSizeCount,
    CAST(
        100.0 * COUNT(*)
        / SUM(COUNT(*)) OVER (PARTITION BY p.ProductLine)
        AS decimal(10, 2)
    ) AS SharePctWithinProductLine
FROM dbo.fact_sales AS fs
JOIN dbo.dim_product AS p
    ON p.ProductKey = fs.ProductKey
GROUP BY
    p.ProductLine,
    fs.OrderSize
ORDER BY
    p.ProductLine,
    SharePctWithinProductLine DESC;
GO

/* =========================================================
   Analytics: Avg items per order per ProductLine
   (ItemsInOrder = SUM(QuantityOrdered) per (OrderNumber, ProductLine))
   ========================================================= */
WITH OrderAgg AS
(
    SELECT
        fs.OrderNumber,
        p.ProductLine,
        SUM(fs.QuantityOrdered) AS ItemsInOrder
    FROM dbo.fact_sales AS fs
    JOIN dbo.dim_product AS p
        ON p.ProductKey = fs.ProductKey
    GROUP BY
        fs.OrderNumber,
        p.ProductLine
)
SELECT
    ProductLine,
    CAST(AVG(1.0 * ItemsInOrder) AS decimal(10, 2)) AS AvgItemsPerOrder
FROM OrderAgg
GROUP BY
    ProductLine
ORDER BY
    AvgItemsPerOrder DESC;
GO

/* =========================================================
   Advanced: Pareto 80/20 Customers (cumulative share of sales)
   ========================================================= */
WITH CustomerAgg AS
(
    SELECT
        c.CustomerName,
        c.Country,
        SUM(fs.Sales) AS TotalSales
    FROM dbo.fact_sales AS fs
    JOIN dbo.dim_customer AS c
        ON c.CustomerKey = fs.CustomerKey
    GROUP BY
        c.CustomerName,
        c.Country
),
WithRunning AS
(
    SELECT
        CustomerName,
        Country,
        TotalSales,
        SUM(TotalSales) OVER
        (
            ORDER BY TotalSales DESC, CustomerName, Country
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS RunningSales,
        SUM(TotalSales) OVER () AS TotalSalesAll
    FROM CustomerAgg
)
SELECT
    CustomerName,
    Country,
    TotalSales,
    RunningSales,
    CAST(100.0 * RunningSales / NULLIF(TotalSalesAll, 0) AS decimal(10, 2)) AS RunningPct
FROM WithRunning
WHERE 1.0 * RunningSales / NULLIF(TotalSalesAll, 0) <= 0.80
ORDER BY
    TotalSales DESC;
GO

/* =========================================================
   Advanced: RFM Segmentation (filtered MonetarySales >= 10000)
   ========================================================= */
WITH MaxDate AS
(
    SELECT MAX(d.FullDate) AS MaxDateInData
    FROM dbo.fact_sales AS fs
    JOIN dbo.dim_date AS d
        ON d.DateKey = fs.DateKey
),
Base AS
(
    SELECT
        c.CustomerName,
        c.Country,
        MAX(d.FullDate) AS LastOrderDate,
        COUNT(DISTINCT fs.OrderNumber) AS FrequencyOrders,
        SUM(fs.Sales) AS MonetarySales
    FROM dbo.fact_sales AS fs
    JOIN dbo.dim_customer AS c
        ON c.CustomerKey = fs.CustomerKey
    JOIN dbo.dim_date AS d
        ON d.DateKey = fs.DateKey
    GROUP BY
        c.CustomerName,
        c.Country
),
Base2 AS
(
    SELECT
        b.CustomerName,
        b.Country,
        b.LastOrderDate,
        md.MaxDateInData,
        DATEDIFF(day, b.LastOrderDate, md.MaxDateInData) AS RecencyDays,
        b.FrequencyOrders,
        b.MonetarySales
    FROM Base AS b
    CROSS JOIN MaxDate AS md
),
Scored AS
(
    SELECT
        CustomerName,
        Country,
        LastOrderDate,
        MaxDateInData,
        RecencyDays,
        FrequencyOrders,
        MonetarySales,
        NTILE(5) OVER (ORDER BY RecencyDays DESC, MonetarySales DESC)      AS R_score,
        NTILE(5) OVER (ORDER BY FrequencyOrders DESC, MonetarySales DESC) AS F_score,
        NTILE(5) OVER (ORDER BY MonetarySales DESC, FrequencyOrders DESC) AS M_score
    FROM Base2
)
SELECT
    CustomerName,
    Country,
    LastOrderDate,
    MaxDateInData,
    RecencyDays,
    FrequencyOrders,
    MonetarySales,
    R_score,
    F_score,
    M_score,
    CONCAT(R_score, F_score, M_score) AS RFM_Code,
    CASE
        WHEN R_score >= 4 AND F_score >= 4 AND M_score >= 4 THEN 'Champions'
        WHEN R_score >= 3 AND F_score >= 4                  THEN 'Loyal'
        WHEN R_score >= 4 AND F_score <= 2                  THEN 'Potential'
        WHEN R_score <= 2 AND F_score >= 3                  THEN 'At Risk'
        WHEN R_score = 1  AND F_score <= 2                  THEN 'Lost'
        ELSE 'Others'
    END AS Segment
FROM Scored
WHERE MonetarySales >= 10000
ORDER BY
    MonetarySales DESC;
GO

/* =========================================================
   Advanced: Cohort Retention (MonthsSinceFirst 0..12)
   ========================================================= */
WITH CustomerMonths AS
(
    SELECT DISTINCT
        fs.CustomerKey,
        DATEFROMPARTS(
            CAST(LEFT(d.YearMonth, 4) AS int),
            CAST(RIGHT(d.YearMonth, 2) AS int),
            1
        ) AS OrderMonth
    FROM dbo.fact_sales AS fs
    JOIN dbo.dim_date AS d
        ON d.DateKey = fs.DateKey
),
Cohorts AS
(
    SELECT
        CustomerKey,
        MIN(OrderMonth) AS CohortMonth
    FROM CustomerMonths
    GROUP BY
        CustomerKey
),
CohortActivity AS
(
    SELECT
        c.CohortMonth,
        cm.OrderMonth,
        DATEDIFF(month, c.CohortMonth, cm.OrderMonth) AS MonthsSinceFirst,
        cm.CustomerKey
    FROM CustomerMonths AS cm
    JOIN Cohorts AS c
        ON c.CustomerKey = cm.CustomerKey
),
Agg AS
(
    SELECT
        CohortMonth,
        MonthsSinceFirst,
        COUNT(DISTINCT CustomerKey) AS ActiveCustomers
    FROM CohortActivity
    GROUP BY
        CohortMonth,
        MonthsSinceFirst
)
SELECT
    CohortMonth,
    MonthsSinceFirst,
    ActiveCustomers,
    MAX(CASE WHEN MonthsSinceFirst = 0 THEN ActiveCustomers END)
        OVER (PARTITION BY CohortMonth) AS CohortSize,
    CAST(
        100.0 * ActiveCustomers
        / NULLIF(
            MAX(CASE WHEN MonthsSinceFirst = 0 THEN ActiveCustomers END)
                OVER (PARTITION BY CohortMonth),
            0
        )
        AS decimal(6, 2)
    ) AS RetentionPct
FROM Agg
WHERE MonthsSinceFirst BETWEEN 0 AND 12
ORDER BY
    CohortMonth,
    MonthsSinceFirst;
GO