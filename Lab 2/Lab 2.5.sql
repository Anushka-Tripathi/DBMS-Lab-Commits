-- LAB QUESTION 1:  Window Function
-- Rank students by marks within each course, highest first. Students with
-- identical marks in the same course must receive the same rank, and the next
-- rank must be skipped. Show course_id, student_id, marks and course_rank.
-- Sort by course_id, then course_rank, then student_id.

SELECT
    course_id,
    student_id,
    marks,
    RANK() OVER (
        PARTITION BY course_id
        ORDER BY marks DESC
    ) AS course_rank
FROM
    exam
ORDER BY
    course_id ASC,
    course_rank ASC,
    student_id ASC;

-- LAB QUESTION 2:  CTE Report
-- Using a WITH clause containing at least three CTEs, build one row per course
-- that has exam records, showing:

--   total_students   - how many students appeared
--   above_avg_count  - how many scored strictly above that course's own average;
--                      show 0 if none did
--   pass_percentage  - the percentage scoring 40 or above, rounded to two
--                      decimal places

-- Sort by course_id.

WITH
-- CTE 1: Calculate average marks per course
CourseAvg AS (
    SELECT
        course_id,
        AVG(marks) AS avg_marks
    FROM exam
    GROUP BY course_id
),

-- CTE 2: Aggregate student counts per course
CourseCounts AS (
    SELECT
        e.course_id,
        COUNT(DISTINCT e.student_id) AS total_students,
        COUNT(CASE WHEN e.marks > ca.avg_marks THEN 1 END) AS above_avg_count
    FROM exam e
    JOIN CourseAvg ca ON e.course_id = ca.course_id
    GROUP BY e.course_id
),

-- CTE 3: Calculate pass percentages
CoursePass AS (
    SELECT
        course_id,
        ROUND((COUNT(CASE WHEN marks >= 40 THEN 1 END) * 100.0) / COUNT(*), 2) AS pass_percentage
    FROM exam
    GROUP BY course_id
)

-- Final SELECT joining the CTE results
SELECT
    cc.course_id,
    cc.total_students,
    cc.above_avg_count,
    cp.pass_percentage
FROM CourseCounts cc
JOIN CoursePass cp ON cc.course_id = cp.course_id
ORDER BY cc.course_id ASC;