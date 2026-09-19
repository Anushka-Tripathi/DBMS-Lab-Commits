-- LAB QUESTION 1: College Record Management — SQL Operations
-- The examination cell has sent three corrections. Write the SQL statements to
-- apply all three, in this order.
-- 1. Rohan (student_id 108) and Aman (student_id 106) both appeared for the AI
--    course (course_id 204), but their records were never entered. Insert these
--    two exam rows:
--      exam_id = 312, student_id = 108, course_id = 204, marks = 72
--      exam_id = 313, student_id = 106, course_id = 204, marks = 68
-- 2. Kabir (student_id 103) was re-evaluated in Networks (course_id 203).
--    Update his marks in that course to 75.
-- 3. Meera's Operating Systems record (exam_id 307) was entered by mistake.
--    Delete it.
INSERT INTO exam (exam_id, student_id, course_id, marks)
VALUES
(312, 108, 204, 72),
(313, 106, 204, 68);

UPDATE exam
SET marks = 75
WHERE student_id = 103
AND course_id = 203;

DELETE FROM exam
WHERE exam_id = 307;


-- LAB QUESTION 2: Filtering and Sorting
-- List the student_id, name and branch of every student in the CSE branch,
-- sorted alphabetically by name.
SELECT student_id, name, branch
FROM student
WHERE branch = 'CSE'
ORDER BY name ASC;