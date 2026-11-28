-- LAB QUESTION 1: Creating a View
-- Create a view named course_report that shows, for every course with at least one exam record,
-- the course_id, the course_name, and the average marks rounded to two decimal places as average_marks.

CREATE VIEW course_report AS
SELECT
    c.course_id,
    c.course_name,
    ROUND(AVG(e.marks), 2) AS average_marks
FROM course c
JOIN exam e
    ON c.course_id=e.course_id
GROUP BY
    c.course_id,
    c.course_name;

-- LAB QUESTION 2: Creating an Index
-- The reports in this lab repeatedly filter and group the exam table by
-- course_id. Create a B-tree index named idx_exam_course_id on that column.

CREATE INDEX idx_exam_course_id
ON exam(course_id);