-- LAB QUESTION 1: Grouping and Aggregation
-- For every course that has at least one exam record, show the course_id, how
-- many students appeared, the average marks rounded to two decimal places, and
-- the highest marks. Name the three computed columns students_appeared,
-- average_marks and top_marks. Sort by course_id ascending.
-- A course with no exam records must not appear in your result.
SELECT
    course_id,
    COUNT(DISTINCT student_id) AS students_appeared,
    ROUND(AVG(marks), 2) AS average_marks,
    MAX(marks) AS top_marks
FROM
    exam
GROUP BY
    course_id
ORDER BY
    course_id ASC;


-- LAB QUESTION 2: Inner Join
-- For every exam record, show the student's name, the course_name and the marks.
-- Sort by marks descending, and where marks are equal, by student name ascending.
SELECT
    s.name AS name,
    c.course_name,
    e.marks
FROM
    exam e
JOIN
    student s ON e.student_id = s.student_id
JOIN
    course c ON e.course_id = c.course_id
ORDER BY
    e.marks DESC,
    s.name ASC;


-- LAB QUESTION 3: Left Join
-- List every student together with the number of exams they have appeared for,
-- as exams_taken. A student who has not appeared for any exam must still appear
-- in the result, with a count of 0. Sort by student_id.
SELECT
    s.student_id,
    s.name,
    COUNT(e.exam_id) AS exams_taken
FROM
    student s
LEFT JOIN
    exam e ON s.student_id = e.student_id
GROUP BY
    s.student_id,
    s.name
ORDER BY
    s.student_id ASC;


-- LAB QUESTION 4: Self Join
-- List every pair of faculty members who work in the same department. Each pair
-- must appear exactly once - do not list a faculty member with themselves, and
-- do not list the same pair twice in reversed order. Name the columns faculty1,
-- faculty2 and department. Sort by department, then by faculty1.
SELECT
    f1.name AS faculty1,
    f2.name AS faculty2,
    f1.department
FROM
    faculty f1
JOIN
    faculty f2
    ON f1.department = f2.department
    AND f1.faculty_id < f2.faculty_id
ORDER BY
    f1.department ASC,
    faculty1 ASC;