-- LAB QUESTION 1: Subquery
-- Using a subquery - not a JOIN - list the student_id and name of every student
-- who has no exam record at all. Sort by student_id.
SELECT student_id, name
FROM student
WHERE student_id NOT IN (
    SELECT student_id
    FROM exam
)
ORDER BY student_id;


-- LAB QUESTION 2: Set Operation
-- Using INTERSECT, list the student_id of every student who both scored 85 or
-- above in at least one exam and appeared for course 201. Sort ascending.
SELECT student_id
FROM exam
WHERE marks >= 85

INTERSECT

SELECT student_id
FROM exam
WHERE course_id = 201

ORDER BY student_id ASC;