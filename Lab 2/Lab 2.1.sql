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