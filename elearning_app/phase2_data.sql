-- =====================================================================
-- PHASE 2: sample activity loaded THROUGH the triggers and procedures
-- Run after phase2_routines.sql.
--
-- seed.sql already holds 12 students, 6 current offerings, 3 months of attendance
-- (Aug-Oct 2026), assignments and submissions. This file adds quiz attempts with
-- answers (validated by the quiz triggers), scores them, then computes results.
-- =====================================================================
USE elearning_db;

-- First attempt on Quiz 1 for most DBMS students (trigger sets attempt_no = 1)
INSERT INTO quiz_attempt (quiz_id, enrollment_id, attempted_on)
SELECT 1, e.enrollment_id, '2026-09-22 11:00:00'
FROM enrollment e
WHERE e.offering_id = 1 AND e.status = 'enrolled' AND MOD(e.enrollment_id, 7) <> 0;

-- A second attempt for some of them (Quiz 1 allows 2; trigger sets attempt_no = 2)
INSERT INTO quiz_attempt (quiz_id, enrollment_id, attempted_on)
SELECT 1, e.enrollment_id, '2026-09-24 10:00:00'
FROM enrollment e
WHERE e.offering_id = 1 AND e.status = 'enrolled' AND MOD(e.enrollment_id, 3) = 0;

-- Answers: a deterministic mix of right and wrong options (validated by trg_quiz_answer_bi)
INSERT INTO quiz_answer (attempt_id, question_id, selected_option_id)
SELECT qa.attempt_id, q.question_id,
       (SELECT o.option_id FROM question_option o
         WHERE o.question_id = q.question_id
           AND o.is_correct = (MOD(qa.attempt_id * 3 + q.question_id * 5, 4) <> 0)
         ORDER BY o.option_id LIMIT 1)
FROM quiz_attempt qa
JOIN question q ON q.quiz_id = qa.quiz_id;

CALL sp_score_quiz(1);

-- Results for every current offering (offerings 1-6)
CALL sp_calculate_offering_results(1);
CALL sp_calculate_offering_results(2);
CALL sp_calculate_offering_results(3);
CALL sp_calculate_offering_results(4);
CALL sp_calculate_offering_results(5);
CALL sp_calculate_offering_results(6);

-- Quick look at the outcome
SELECT s.roll_number, CONCAT(s.first_name, ' ', s.last_name) AS student, c.course_code,
       fn_assignment_pct(e.enrollment_id)  AS assignment_pct,
       fn_quiz_pct(e.enrollment_id)        AS quiz_pct,
       fn_attendance_pct(e.enrollment_id)  AS attendance_pct,
       r.final_percentage,
       fn_letter_grade(r.final_percentage) AS grade
FROM enrollment e
JOIN student s          ON s.student_id = e.student_id
JOIN course_offering o  ON o.offering_id = e.offering_id
JOIN course c           ON c.course_id = o.course_id
JOIN course_result r    ON r.enrollment_id = e.enrollment_id
WHERE o.offering_id = 1
ORDER BY s.roll_number;
