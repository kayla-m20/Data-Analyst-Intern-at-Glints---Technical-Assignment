-- Glints Data Analyst Intern - Assignment 2 : SQL query optimisation, 100% MySQL 8.0
-- Run with:  mysql -uroot --table < assignment2_glints.sql     (tested on MySQL 8.0.46)
-- What this script does, all in SQL:
--   1. uses schema `glints` 
--   2. creates v_original (draft query) and v_optimised (rewrite) as views
--   3. proves the two return the same data (row counts, EXCEPT in both directions, the fan-out bug)
--   4. benchmarks both on enlarged copies of the data with a stored procedure and stores timings in glints.bench_results


-- ====================================================================================================
-- 1. USE DATABASE
-- ====================================================================================================
USE glints;

-- Drop views dulu 
DROP VIEW IF EXISTS v_original;
DROP VIEW IF EXISTS v_optimised;
DROP VIEW IF EXISTS v_original_bench;
DROP VIEW IF EXISTS v_optimised_bench;

-- Drop stored procedure
DROP PROCEDURE IF EXISTS run_benchmark;

-- Drop semua tabel
DROP TABLE IF EXISTS staff_particulars;
DROP TABLE IF EXISTS staff_small;
DROP TABLE IF EXISTS staff_big;
DROP TABLE IF EXISTS recruitment_costs;
DROP TABLE IF EXISTS salary_grid;
DROP TABLE IF EXISTS bench_results;
DROP TABLE IF EXISTS staff_particulars_backup;

-- Cek
SHOW TABLES;
-- Harus: Empty set

USE glints;

-- Tabel 1: staff_particulars
CREATE TABLE staff_particulars (
    `Employee Name` VARCHAR(200),
    `Employee Number` VARCHAR(30),
    `State` VARCHAR(10),
    `Zip` VARCHAR(20),
    `DOB` VARCHAR(30),
    `Sex` VARCHAR(20),
    `MaritalDesc` VARCHAR(30),
    `CitizenDesc` VARCHAR(50),
    `Hispanic/Latino` VARCHAR(20),
    `RaceDesc` VARCHAR(80),
    `Date of Hire` VARCHAR(30),
    `Date of Termination` VARCHAR(30),
    `Reason For Term` VARCHAR(200),
    `Employment Status` VARCHAR(50),
    `Department` VARCHAR(80),
    `Position` VARCHAR(150),
    `Manager Name` VARCHAR(150),
    `Employee Source` VARCHAR(150),
    `Performance Score` VARCHAR(50),
    `Pay Rate` DECIMAL(8,2)
);

-- Tabel 2: recruitment_costs
CREATE TABLE recruitment_costs (
    `Employment Source` VARCHAR(150),
    `January` VARCHAR(20),
    `February` VARCHAR(20),
    `March` VARCHAR(20),
    `April` VARCHAR(20),
    `May` VARCHAR(20),
    `June` VARCHAR(20),
    `July` VARCHAR(20),
    `August` VARCHAR(20),
    `September` VARCHAR(20),
    `October` VARCHAR(20),
    `November` VARCHAR(20),
    `December` VARCHAR(20),
    `Total` VARCHAR(20)
);

-- Tabel 3: salary_grid
CREATE TABLE salary_grid (
    `Position` VARCHAR(150),
    `Salary Min` VARCHAR(20),
    `Salary Mid` VARCHAR(20),
    `Salary Max` VARCHAR(20),
    `Hourly Min` VARCHAR(20),
    `Hourly Mid` VARCHAR(20),
    `Hourly Max` VARCHAR(20)
);

-- Cek
SHOW TABLES;

LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/staff_particulars.csv'
INTO TABLE staff_particulars
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 ROWS;

-- Cek
SELECT COUNT(*) FROM staff_particulars;
-- Harus: 310

LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/recruitment_costs.csv'
INTO TABLE recruitment_costs
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 ROWS;

-- Cek
SELECT COUNT(*) FROM recruitment_costs;
-- Harus: 22

INSERT INTO salary_grid VALUES
('Administrative Assistant', '30000', '40000', '50000', '14.42', '19.23', '24.04'),
('Sr. Administrative Assistant', '35000', '45000', '55000', '16.83', '21.63', '26.44'),
('Accountant I', '42274', '51425', '62299', '20.32', '24.72', '29.95'),
('Accountant II', '50490', '62158', '74658', '24.27', '29.88', '35.89'),
('Sr. Accountant', '63264', '76988', '92454', '30.42', '37.01', '44.45'),
('Network Engineer', '50845', '66850', '88279', '24.44', '32.14', '42.44'),
('Sr. Network Engineer', '79428', '99458', '120451', '38.19', '47.82', '57.91'),
('Database Administrator', '50569', '68306', '93312', '24.31', '32.84', '44.86'),
('Sr. DBA', '92863', '116007', '139170', '44.65', '55.77', '66.91'),
('Production Technician I', '30000', '40000', '50000', '14.42', '19.23', '24.04'),
('Production Technician II', '38000', '48000', '58000', '18.27', '23.08', '27.88'),
('Lead Production Technician', '45000', '55000', '65000', '21.63', '26.44', '31.25');

-- Cek
SELECT COUNT(*) FROM salary_grid;
-- Harus: 12

SELECT 'staff_particulars' AS tabel, COUNT(*) AS rows_count FROM staff_particulars
UNION ALL
SELECT 'recruitment_costs', COUNT(*) FROM recruitment_costs
UNION ALL
SELECT 'salary_grid', COUNT(*) FROM salary_grid;


-- ====================================================================================================
-- 2. THE TWO QUERIES AS VIEWS
-- ====================================================================================================
USE glints;
DROP VIEW IF EXISTS v_original;
DROP VIEW IF EXISTS v_optimised;

CREATE VIEW v_original AS
SELECT *
FROM (
    SELECT DISTINCT
        sp.*,
        sg.`Salary Min`,
        sg.`Salary Mid`,
        sg.`Salary Max`,
        sg.`Hourly Min`,
        sg.`Hourly Max`,
        rc.`Employment Source` AS matched_source,
        rc.Total AS source_total_cost,
        t.total_staff,

        TIMESTAMPDIFF(YEAR, STR_TO_DATE(NULLIF(sp.DOB, ''), '%m/%d/%Y'), CURDATE()) AS age,
        DATEDIFF(
            IFNULL(STR_TO_DATE(NULLIF(sp.`Date of Termination`, ''), '%m/%d/%Y'), CURDATE()),
            STR_TO_DATE(NULLIF(sp.`Date of Hire`, ''), '%m/%d/%Y')
        ) / 365 AS tenure_years,

        (SELECT AVG(s2.`Pay Rate`)
           FROM staff_particulars s2
          WHERE s2.Department = sp.Department) AS dept_avg_pay,

        (SELECT COUNT(*)
           FROM staff_particulars s3
          WHERE s3.`Manager Name` = sp.`Manager Name`) AS manager_team_size,

        (SELECT COUNT(*)
           FROM staff_particulars s4
          WHERE s4.`Employee Source` = sp.`Employee Source`) AS hires_from_source,

        rc.Total / (SELECT COUNT(*)
                      FROM staff_particulars s5
                     WHERE s5.`Employee Source` = sp.`Employee Source`) AS cost_per_hire,

        (SELECT COUNT(*)
           FROM staff_particulars s6
          WHERE s6.Department = sp.Department
            AND s6.`Pay Rate` > sp.`Pay Rate`) + 1 AS pay_rank_in_dept,

        (IFNULL(rc.January, 0) + IFNULL(rc.February, 0) + IFNULL(rc.March, 0) + IFNULL(rc.April, 0) + IFNULL(rc.May, 0) + IFNULL(rc.June, 0) + IFNULL(rc.July, 0) + IFNULL(rc.August, 0) + IFNULL(rc.September, 0) + IFNULL(rc.October, 0) + IFNULL(rc.November, 0) + IFNULL(rc.December, 0)) AS recomputed_total,

        CASE
            WHEN sp.`Pay Rate` < sg.`Hourly Min` THEN 'Below Grid'
            WHEN sp.`Pay Rate` > sg.`Hourly Max` THEN 'Above Grid'
            WHEN sp.`Pay Rate` BETWEEN sg.`Hourly Min` AND sg.`Hourly Mid`
                THEN 'Lower Half'
            WHEN sp.`Pay Rate` BETWEEN sg.`Hourly Mid` AND sg.`Hourly Max`
                THEN 'Upper Half'
            ELSE 'Unknown'
        END AS grid_position

    FROM staff_particulars sp

    LEFT JOIN salary_grid sg
           ON UPPER(TRIM(sp.Position)) = UPPER(TRIM(sg.Position))

    LEFT JOIN recruitment_costs rc
           ON LOWER(sp.`Employee Source`) LIKE CONCAT('%', LOWER(rc.`Employment Source`), '%')

    CROSS JOIN (SELECT COUNT(*) AS total_staff FROM staff_particulars) t

    WHERE
        sp.`Employee Number` IN (SELECT `Employee Number`
                                   FROM staff_particulars
                                  WHERE `Employment Status` IS NOT NULL)
        AND (sp.`Employment Status` LIKE '%Active%'
          OR sp.`Employment Status` LIKE '%Terminated%'
          OR sp.`Employment Status` LIKE '%Voluntarily%')
        AND YEAR(STR_TO_DATE(NULLIF(sp.`Date of Hire`, ''), '%m/%d/%Y')) >= 2000
        AND NOT EXISTS (SELECT 1
                          FROM salary_grid g
                         WHERE g.Position = sp.Position
                           AND g.`Salary Min` IS NULL)
        AND LENGTH(sp.`Employee Name`) + 0 > 0
) AS x

ORDER BY UPPER(x.Department), x.pay_rank_in_dept, 5 DESC;

CREATE VIEW v_optimised AS
/* ============================================================================
   Employee master view: employee details + grid position + recruitment cost
   + department / manager / source level metrics.
   Optimised for performance and maintainability (see report, Assignment 2).
   ============================================================================ */
WITH staff AS (
    /* Step 1: parse text dates ONCE and compute every "whole-table" metric in a
       single pass with window functions (replaces 5 correlated sub-queries).
       These run BEFORE the filters below on purpose: the original query
       counted / averaged over ALL rows of staff_particulars, not only over the
       rows that survive the WHERE clause.                                     */
    SELECT
        sp.`Employee Name`,
        sp.`Employee Number`,
        sp.State,
        sp.Zip,
        sp.DOB,
        sp.Sex,
        sp.MaritalDesc,
        sp.CitizenDesc,
        sp.`Hispanic/Latino`,
        sp.RaceDesc,
        sp.`Date of Hire`,
        sp.`Date of Termination`,
        sp.`Reason For Term`,
        sp.`Employment Status`,
        sp.Department,
        sp.Position,
        sp.`Manager Name`,
        sp.`Employee Source`,
        sp.`Performance Score`,
        sp.`Pay Rate`,

        STR_TO_DATE(NULLIF(sp.DOB, ''),                   '%m/%d/%Y') AS dob_dt,
        STR_TO_DATE(NULLIF(sp.`Date of Hire`, ''),        '%m/%d/%Y') AS hire_dt,
        STR_TO_DATE(NULLIF(sp.`Date of Termination`, ''), '%m/%d/%Y') AS term_dt,

        COUNT(*)              OVER ()                                          AS total_staff,
        AVG(sp.`Pay Rate`)    OVER (PARTITION BY sp.Department)                AS dept_avg_pay,
        COUNT(*)              OVER (PARTITION BY sp.`Manager Name`)            AS manager_team_size,
        COUNT(*)              OVER (PARTITION BY sp.`Employee Source`)         AS hires_from_source,
        /* RANK() = "number of people paid strictly more, + 1" (ties share a rank) */
        RANK()                OVER (PARTITION BY sp.Department
                                    ORDER BY sp.`Pay Rate` DESC)               AS pay_rank_in_dept
    FROM staff_particulars AS sp
),
recruit AS (
    /* Step 2: derive the monthly re-sum once per channel (22 rows),
       not once per employee row.                                              */
    SELECT
        rc.`Employment Source`,
        rc.Total,
        IFNULL(rc.January,0)  + IFNULL(rc.February,0) + IFNULL(rc.March,0)
      + IFNULL(rc.April,0)    + IFNULL(rc.May,0)      + IFNULL(rc.June,0)
      + IFNULL(rc.July,0)     + IFNULL(rc.August,0)   + IFNULL(rc.September,0)
      + IFNULL(rc.October,0)  + IFNULL(rc.November,0) + IFNULL(rc.December,0)
            AS recomputed_total
    FROM recruitment_costs AS rc
)
SELECT
    s.`Employee Name`,
    s.`Employee Number`,
    s.State,
    s.Zip,
    s.DOB,
    s.Sex,
    s.MaritalDesc,
    s.CitizenDesc,
    s.`Hispanic/Latino`,
    s.RaceDesc,
    s.`Date of Hire`,
    s.`Date of Termination`,
    s.`Reason For Term`,
    s.`Employment Status`,
    s.Department,
    s.Position,
    s.`Manager Name`,
    s.`Employee Source`,
    s.`Performance Score`,
    s.`Pay Rate`,

    sg.`Salary Min`,
    sg.`Salary Mid`,
    sg.`Salary Max`,
    sg.`Hourly Min`,
    sg.`Hourly Max`,

    rc.`Employment Source`                                   AS matched_source,
    rc.Total                                                 AS source_total_cost,
    s.total_staff,

    TIMESTAMPDIFF(YEAR, s.dob_dt, CURDATE())                 AS age,
    DATEDIFF(IFNULL(s.term_dt, CURDATE()), s.hire_dt) / 365  AS tenure_years,

    s.dept_avg_pay,
    s.manager_team_size,
    s.hires_from_source,
    rc.Total / NULLIF(s.hires_from_source, 0)                AS cost_per_hire,
    s.pay_rank_in_dept,
    IFNULL(rc.recomputed_total, 0)                           AS recomputed_total,   -- 0 (not NULL) if no channel row

    CASE
        WHEN s.`Pay Rate` <  sg.`Hourly Min`                                THEN 'Below Grid'
        WHEN s.`Pay Rate` >  sg.`Hourly Max`                                THEN 'Above Grid'
        WHEN s.`Pay Rate` BETWEEN sg.`Hourly Min` AND sg.`Hourly Mid`       THEN 'Lower Half'
        WHEN s.`Pay Rate` BETWEEN sg.`Hourly Mid` AND sg.`Hourly Max`       THEN 'Upper Half'
        ELSE 'Unknown'
    END                                                      AS grid_position

FROM staff AS s
/* exact (case-insensitive by collation) keys -> 1 row per employee, index-friendly */
LEFT JOIN salary_grid AS sg ON sg.Position            = s.Position
LEFT JOIN recruit     AS rc ON rc.`Employment Source` = s.`Employee Source`

WHERE s.`Employment Status` IN ('Active', 'Voluntarily Terminated', 'Terminated for Cause')
  AND s.hire_dt >= '2000-01-01'                                -- sargable replacement for YEAR(...) >= 2000
  AND (sg.Position IS NULL OR sg.`Salary Min` IS NOT NULL)     -- drop positions whose grid row is incomplete
  AND CHAR_LENGTH(s.`Employee Name`) > 0                       -- non-empty name

ORDER BY s.Department,
         s.pay_rank_in_dept,
         s.dob_dt DESC;                                        -- was positional "5 DESC" (= DOB as text);


-- ====================================================================================================
-- 3. CORRECTNESS CHECKS
-- ====================================================================================================

-- 3a. Row counts: the original returns duplicates because of its fuzzy LIKE join
SELECT 'original'  AS query_version, COUNT(*) AS rows_returned, COUNT(DISTINCT `Employee Number`, `Employee Name`) AS distinct_employees FROM v_original
UNION ALL
SELECT 'optimised' AS query_version, COUNT(*), COUNT(DISTINCT `Employee Number`, `Employee Name`) FROM v_optimised;

-- 3b. The fan-out bug: 'Pay Per Click - Google' employees are matched to TWO channels in the original
SELECT 'original' AS query_version, matched_source, source_total_cost, ROUND(cost_per_hire, 2) AS cost_per_hire, COUNT(*) AS employee_rows
FROM v_original WHERE `Employee Source` = 'Pay Per Click - Google' GROUP BY matched_source, source_total_cost, cost_per_hire
UNION ALL
SELECT 'optimised', matched_source, source_total_cost, ROUND(cost_per_hire, 2), COUNT(*)
FROM v_optimised WHERE `Employee Source` = 'Pay Per Click - Google' GROUP BY matched_source, source_total_cost, cost_per_hire;

-- 3c. Full-row comparison on all 37 columns. Both queries must return 0 rows.
--     (the 21 wrongly matched duplicate rows of the original are excluded on the left side)
SELECT 'in original but not in optimised' AS direction, COUNT(*) AS differing_rows FROM (
    SELECT * FROM v_original
    WHERE NOT (`Employee Source` = 'Pay Per Click - Google' AND matched_source = 'Pay Per Click')
    EXCEPT
    SELECT * FROM v_optimised
) a
UNION ALL
SELECT 'in optimised but not in original', COUNT(*) FROM (
    SELECT * FROM v_optimised
    EXCEPT
    SELECT * FROM v_original
    WHERE NOT (`Employee Source` = 'Pay Per Click - Google' AND matched_source = 'Pay Per Click')
) b;

-- 3d. Unmatched channel (Indeed): the original returns recomputed_total = 0, so must the rewrite
SELECT 'original' AS query_version, `Employee Source`, matched_source, recomputed_total, COUNT(*) AS employees FROM v_original WHERE `Employee Source` = 'Indeed' GROUP BY 1, 2, 3, 4
UNION ALL
SELECT 'optimised', `Employee Source`, matched_source, recomputed_total, COUNT(*) FROM v_optimised WHERE `Employee Source` = 'Indeed' GROUP BY 1, 2, 3, 4;


-- ====================================================================================================
-- 4. BENCHMARK (pure SQL)
-- ====================================================================================================

USE glints;
DROP TABLE IF EXISTS bench_results;
CREATE TABLE bench_results (rows_in_table INT, original_seconds DECIMAL(10,3), optimised_seconds DECIMAL(10,3), speed_up DECIMAL(10,1));

DROP PROCEDURE IF EXISTS run_benchmark;
DELIMITER $$
CREATE PROCEDURE run_benchmark(IN extra_rows INT)
BEGIN
    DECLARE t0, t1, t2 DATETIME(6);
    DECLARE total_rows INT;

    -- build an enlarged copy of staff_particulars by replicating the real rows
    DROP TABLE IF EXISTS staff_big;
    CREATE TABLE staff_big LIKE staff_particulars;
    INSERT INTO staff_big SELECT * FROM staff_particulars;
    INSERT INTO staff_big
    SELECT s.* FROM staff_particulars s
    JOIN (WITH RECURSIVE n (i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 60) SELECT i FROM n) q ON 1 = 1
    LIMIT extra_rows;
    SELECT COUNT(*) INTO total_rows FROM staff_big;

    -- swap the big table in under the original name so both views read it
    RENAME TABLE staff_particulars TO staff_small, staff_big TO staff_particulars;

    SET t0 = SYSDATE(6);
    CREATE TEMPORARY TABLE tmp_original AS SELECT * FROM v_original;
    SET t1 = SYSDATE(6);
    CREATE TEMPORARY TABLE tmp_optimised AS SELECT * FROM v_optimised;
    SET t2 = SYSDATE(6);

    DROP TEMPORARY TABLE tmp_original;
    DROP TEMPORARY TABLE tmp_optimised;
    RENAME TABLE staff_particulars TO staff_big, staff_small TO staff_particulars;
    DROP TABLE staff_big;

    INSERT INTO bench_results
    VALUES (total_rows,
            TIMESTAMPDIFF(MICROSECOND, t0, t1) / 1000000,
            TIMESTAMPDIFF(MICROSECOND, t1, t2) / 1000000,
            (TIMESTAMPDIFF(MICROSECOND, t0, t1)) / NULLIF(TIMESTAMPDIFF(MICROSECOND, t1, t2), 0));
END$$
DELIMITER ;

CALL run_benchmark(2000);
CALL run_benchmark(4000);
CALL run_benchmark(6000);

SELECT * FROM bench_results ORDER BY rows_in_table;
