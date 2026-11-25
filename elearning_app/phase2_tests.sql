-- =====================================================================
-- PHASE 2 TEST SUITE   (run after phase2_data.sql)
--   CALL sp_run_phase2_tests();
-- Every case runs inside one transaction that is rolled back at the end, so the
-- database is left exactly as it was. Each row of the output is one test case.
-- (Do not call procedures that COMMIT, such as sp_enroll_student, inside the suite.)
-- =====================================================================
USE elearning_db;
DELIMITER $$

DROP PROCEDURE IF EXISTS sp_run_phase2_tests$$
CREATE PROCEDURE sp_run_phase2_tests()
BEGIN
    DECLARE v_msg       TEXT DEFAULT NULL;
    DECLARE v_val       VARCHAR(60);
    DECLARE v_s1_enr    INT;          -- student 1 in DBMS (offering 1)
    DECLARE v_new_stu   INT;          -- throw-away student without prerequisite history
    DECLARE v_new_stu2  INT;
    DECLARE v_new_enr   INT;          -- throw-away student enrolled in Verbal Ability (offering 6)
    DECLARE v_a1        INT;          -- Verbal Assignment 1 (past due, no late)
    DECLARE v_a2        INT;          -- Verbal Assignment 2 (open)
    DECLARE v_a_other   INT;          -- an assignment from a different offering
    DECLARE v_sub       INT;          -- an existing graded submission
    DECLARE v_sub_off   INT;
    DECLARE v_grader    INT;          -- instructor assigned to that offering
    DECLARE v_outsider  INT;          -- instructor NOT assigned to that offering
    DECLARE v_att_enr   INT;          -- DBMS enrolment that already has quiz attempts
    DECLARE v_new_att   INT;
    DECLARE v_done_att  INT;          -- an already scored attempt
    DECLARE v_q1        INT;
    DECLARE v_q2        INT;
    DECLARE v_opt_q1    INT;
    DECLARE v_opt_q2    INT;
    DECLARE v_session   INT;

    DROP TEMPORARY TABLE IF EXISTS test_results;
    CREATE TEMPORARY TABLE test_results (
        test_no   INT AUTO_INCREMENT PRIMARY KEY,
        area      VARCHAR(20),
        test_case VARCHAR(90),
        expected  VARCHAR(40),
        actual    VARCHAR(160),
        status    VARCHAR(4)
    ) ENGINE = MEMORY;                 -- MEMORY: results survive the ROLLBACK below

    -- look-ups --------------------------------------------------------
    SELECT enrollment_id INTO v_s1_enr FROM enrollment WHERE student_id = 1 AND offering_id = 1;
    SELECT assignment_id INTO v_a1 FROM assignment WHERE offering_id = 6 AND title = 'Assignment 1';
    SELECT assignment_id INTO v_a2 FROM assignment WHERE offering_id = 6 AND title = 'Assignment 2';
    SELECT assignment_id INTO v_a_other FROM assignment WHERE offering_id = 1 AND title = 'Assignment 1';
    SELECT s.submission_id, a.offering_id INTO v_sub, v_sub_off
      FROM submission s JOIN assignment a ON a.assignment_id = s.assignment_id
     WHERE s.marks_obtained IS NOT NULL AND a.offering_id = 1 LIMIT 1;
    SELECT instructor_id INTO v_grader FROM offering_instructor WHERE offering_id = v_sub_off AND role = 'primary';
    SELECT instructor_id INTO v_outsider FROM instructor
     WHERE instructor_id NOT IN (SELECT instructor_id FROM offering_instructor WHERE offering_id = v_sub_off) LIMIT 1;
    SELECT enrollment_id INTO v_att_enr FROM quiz_attempt WHERE quiz_id = 1 LIMIT 1;
    SELECT attempt_id INTO v_done_att FROM quiz_attempt WHERE quiz_id = 1 AND score IS NOT NULL LIMIT 1;
    SELECT MIN(question_id), MAX(question_id) INTO v_q1, v_q2 FROM question WHERE quiz_id = 1;
    SELECT option_id INTO v_opt_q1 FROM question_option WHERE question_id = v_q1 ORDER BY option_id LIMIT 1;
    SELECT option_id INTO v_opt_q2 FROM question_option WHERE question_id = v_q2 ORDER BY option_id LIMIT 1;

    START TRANSACTION;

    INSERT INTO student (roll_number, first_name, last_name, email, program_id, admission_year)
    VALUES ('TEST0001', 'Test', 'Student', 'test.student@student.college.edu', 1, 2026);
    SET v_new_stu = LAST_INSERT_ID();
    INSERT INTO student (roll_number, first_name, last_name, email, program_id, admission_year, status)
    VALUES ('TEST0002', 'Test', 'Suspended', 'test.suspended@student.college.edu', 1, 2026, 'suspended');
    SET v_new_stu2 = LAST_INSERT_ID();

    -- ===================== ENROLLMENT =====================
    BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
            INSERT INTO test_results (area, test_case, expected, actual, status)
            VALUES ('Enrollment', 'Enroll same student twice in the same offering', 'rejected', LEFT(v_msg, 160),
                    IF(v_msg LIKE '%already enrolled%' OR v_msg LIKE '%Duplicate%', 'PASS', 'FAIL'));
        END;
        INSERT INTO enrollment (student_id, offering_id) VALUES (1, 1);
        INSERT INTO test_results (area, test_case, expected, actual, status)
        VALUES ('Enrollment', 'Enroll same student twice in the same offering', 'rejected', 'NO ERROR RAISED', 'FAIL');
    END;

    BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
            INSERT INTO test_results (area, test_case, expected, actual, status)
            VALUES ('Enrollment', 'Enroll when the offering is full', 'rejected', LEFT(v_msg, 160),
                    IF(v_msg LIKE '%full%', 'PASS', 'FAIL'));
        END;
        UPDATE course_offering SET max_capacity = 1 WHERE offering_id = 4;
        INSERT INTO enrollment (student_id, offering_id) VALUES (1, 4);
        INSERT INTO test_results (area, test_case, expected, actual, status)
        VALUES ('Enrollment', 'Enroll when the offering is full', 'rejected', 'NO ERROR RAISED', 'FAIL');
    END;

    BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
            INSERT INTO test_results (area, test_case, expected, actual, status)
            VALUES ('Enrollment', 'Enroll without the prerequisite (DBMS needs Data Structures)', 'rejected', LEFT(v_msg, 160),
                    IF(v_msg LIKE '%prerequisite%', 'PASS', 'FAIL'));
        END;
        INSERT INTO enrollment (student_id, offering_id) VALUES (v_new_stu, 1);
        INSERT INTO test_results (area, test_case, expected, actual, status)
        VALUES ('Enrollment', 'Enroll without the prerequisite (DBMS needs Data Structures)', 'rejected', 'NO ERROR RAISED', 'FAIL');
    END;

    BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
            INSERT INTO test_results (area, test_case, expected, actual, status)
            VALUES ('Enrollment', 'Enroll a suspended student', 'rejected', LEFT(v_msg, 160),
                    IF(v_msg LIKE '%active students%', 'PASS', 'FAIL'));
        END;
        INSERT INTO enrollment (student_id, offering_id) VALUES (v_new_stu2, 6);
        INSERT INTO test_results (area, test_case, expected, actual, status)
        VALUES ('Enrollment', 'Enroll a suspended student', 'rejected', 'NO ERROR RAISED', 'FAIL');
    END;

    BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
            INSERT INTO test_results (area, test_case, expected, actual, status)
            VALUES ('Enrollment', 'Enroll in a second section of a course already taken this term', 'rejected', LEFT(v_msg, 160),
                    IF(v_msg LIKE '%already enrolled in this course%', 'PASS', 'FAIL'));
        END;
        INSERT INTO course_offering (course_id, term_id, section_code) VALUES (1, 2, 'B');
        INSERT INTO enrollment (student_id, offering_id) VALUES (1, LAST_INSERT_ID());
        INSERT INTO test_results (area, test_case, expected, actual, status)
        VALUES ('Enrollment', 'Enroll in a second section of a course already taken this term', 'rejected', 'NO ERROR RAISED', 'FAIL');
    END;

    BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
            INSERT INTO test_results (area, test_case, expected, actual, status)
            VALUES ('Enrollment', 'Valid enrollment (no prerequisite, seats free)', 'accepted', LEFT(v_msg, 160), 'FAIL');
        END;
        INSERT INTO enrollment (student_id, offering_id) VALUES (v_new_stu, 6);
        SET v_new_enr = LAST_INSERT_ID();
        INSERT INTO test_results (area, test_case, expected, actual, status)
        VALUES ('Enrollment', 'Valid enrollment (no prerequisite, seats free)', 'accepted', 'accepted', 'PASS');
    END;

    -- ===================== SUBMISSIONS =====================
    BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
            INSERT INTO test_results (area, test_case, expected, actual, status)
            VALUES ('Submission', 'Submit after the deadline when late is not allowed', 'rejected', LEFT(v_msg, 160),
                    IF(v_msg LIKE '%deadline%', 'PASS', 'FAIL'));
        END;
        INSERT INTO submission (assignment_id, enrollment_id, content_url) VALUES (v_a1, v_new_enr, 'https://example.com/late');
        INSERT INTO test_results (area, test_case, expected, actual, status)
        VALUES ('Submission', 'Submit after the deadline when late is not allowed', 'rejected', 'NO ERROR RAISED', 'FAIL');
    END;

    BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
            INSERT INTO test_results (area, test_case, expected, actual, status)
            VALUES ('Submission', 'Submit on time for an open assignment', 'accepted', LEFT(v_msg, 160), 'FAIL');
        END;
        INSERT INTO submission (assignment_id, enrollment_id, content_url) VALUES (v_a2, v_new_enr, 'https://example.com/ontime');
        INSERT INTO test_results (area, test_case, expected, actual, status)
        VALUES ('Submission', 'Submit on time for an open assignment', 'accepted', 'accepted', 'PASS');
    END;

    BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
            INSERT INTO test_results (area, test_case, expected, actual, status)
            VALUES ('Submission', 'Submit an assignment from a different course', 'rejected', LEFT(v_msg, 160),
                    IF(v_msg LIKE '%does not belong%', 'PASS', 'FAIL'));
        END;
        INSERT INTO submission (assignment_id, enrollment_id, content_url) VALUES (v_a_other, v_new_enr, 'https://example.com/x');
        INSERT INTO test_results (area, test_case, expected, actual, status)
        VALUES ('Submission', 'Submit an assignment from a different course', 'rejected', 'NO ERROR RAISED', 'FAIL');
    END;

    -- ===================== GRADING =====================
    BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
            INSERT INTO test_results (area, test_case, expected, actual, status)
            VALUES ('Grading', 'Marks above the assignment maximum', 'rejected', LEFT(v_msg, 160),
                    IF(v_msg LIKE '%exceed%', 'PASS', 'FAIL'));
        END;
        CALL sp_grade_submission(v_sub, 9999, 'too high', v_grader);
        INSERT INTO test_results (area, test_case, expected, actual, status)
        VALUES ('Grading', 'Marks above the assignment maximum', 'rejected', 'NO ERROR RAISED', 'FAIL');
    END;

    BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
            INSERT INTO test_results (area, test_case, expected, actual, status)
            VALUES ('Grading', 'Negative marks', 'rejected', LEFT(v_msg, 160),
                    IF(v_msg LIKE '%heck constraint%' OR v_msg LIKE '%CONSTRAINT%', 'PASS', 'FAIL'));
        END;
        CALL sp_grade_submission(v_sub, -5, 'negative', v_grader);
        INSERT INTO test_results (area, test_case, expected, actual, status)
        VALUES ('Grading', 'Negative marks', 'rejected', 'NO ERROR RAISED', 'FAIL');
    END;

    BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
            INSERT INTO test_results (area, test_case, expected, actual, status)
            VALUES ('Grading', 'Instructor not assigned to the course tries to grade', 'rejected', LEFT(v_msg, 160),
                    IF(v_msg LIKE '%not assigned%', 'PASS', 'FAIL'));
        END;
        CALL sp_grade_submission(v_sub, 5, 'not mine', v_outsider);
        INSERT INTO test_results (area, test_case, expected, actual, status)
        VALUES ('Grading', 'Instructor not assigned to the course tries to grade', 'rejected', 'NO ERROR RAISED', 'FAIL');
    END;

    BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
            INSERT INTO test_results (area, test_case, expected, actual, status)
            VALUES ('Grading', 'Valid grading by the course instructor', 'accepted', LEFT(v_msg, 160), 'FAIL');
        END;
        CALL sp_grade_submission(v_sub, 5, 'regraded', v_grader);
        INSERT INTO test_results (area, test_case, expected, actual, status)
        VALUES ('Grading', 'Valid grading by the course instructor', 'accepted', 'accepted',
                IF((SELECT marks_obtained FROM submission WHERE submission_id = v_sub) = 5, 'PASS', 'FAIL'));
    END;

    -- ===================== ATTENDANCE =====================
    INSERT INTO class_session (offering_id, session_date, start_time, end_time, topic)
    VALUES (1, DATE_ADD(CURRENT_DATE, INTERVAL 30 DAY), '09:00:00', '10:00:00', 'Future lecture');
    SET v_session = LAST_INSERT_ID();

    BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
            INSERT INTO test_results (area, test_case, expected, actual, status)
            VALUES ('Attendance', 'Mark attendance for a future session', 'rejected', LEFT(v_msg, 160),
                    IF(v_msg LIKE '%future%', 'PASS', 'FAIL'));
        END;
        INSERT INTO attendance (session_id, enrollment_id, status) VALUES (v_session, v_s1_enr, 'present');
        INSERT INTO test_results (area, test_case, expected, actual, status)
        VALUES ('Attendance', 'Mark attendance for a future session', 'rejected', 'NO ERROR RAISED', 'FAIL');
    END;

    BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
            INSERT INTO test_results (area, test_case, expected, actual, status)
            VALUES ('Attendance', 'Mark a student present in a course they are not in', 'rejected', LEFT(v_msg, 160),
                    IF(v_msg LIKE '%not enrolled%', 'PASS', 'FAIL'));
        END;
        INSERT INTO attendance (session_id, enrollment_id, status)
        SELECT session_id, v_s1_enr, 'present' FROM class_session WHERE offering_id = 4 LIMIT 1;
        INSERT INTO test_results (area, test_case, expected, actual, status)
        VALUES ('Attendance', 'Mark a student present in a course they are not in', 'rejected', 'NO ERROR RAISED', 'FAIL');
    END;

    -- ===================== QUIZZES =====================
    BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
            INSERT INTO test_results (area, test_case, expected, actual, status)
            VALUES ('Quiz', 'Attempt a quiz outside its open window', 'rejected', LEFT(v_msg, 160),
                    IF(v_msg LIKE '%not open%', 'PASS', 'FAIL'));
        END;
        INSERT INTO quiz_attempt (quiz_id, enrollment_id) VALUES (1, v_s1_enr);      -- Quiz 1 closed in September
        INSERT INTO test_results (area, test_case, expected, actual, status)
        VALUES ('Quiz', 'Attempt a quiz outside its open window', 'rejected', 'NO ERROR RAISED', 'FAIL');
    END;

    BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
            INSERT INTO test_results (area, test_case, expected, actual, status)
            VALUES ('Quiz', 'Attempt beyond the maximum number of attempts', 'rejected', LEFT(v_msg, 160),
                    IF(v_msg LIKE '%maximum attempts%', 'PASS', 'FAIL'));
        END;
        UPDATE quiz SET max_attempts = 1 WHERE quiz_id = 1;
        INSERT INTO quiz_attempt (quiz_id, enrollment_id, attempted_on) VALUES (1, v_att_enr, '2026-09-23 10:00:00');
        INSERT INTO test_results (area, test_case, expected, actual, status)
        VALUES ('Quiz', 'Attempt beyond the maximum number of attempts', 'rejected', 'NO ERROR RAISED', 'FAIL');
    END;

    BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
            INSERT INTO test_results (area, test_case, expected, actual, status)
            VALUES ('Quiz', 'Valid attempt gets the next sequential attempt number', 'accepted', LEFT(v_msg, 160), 'FAIL');
        END;
        UPDATE quiz SET max_attempts = 5 WHERE quiz_id = 1;
        INSERT INTO quiz_attempt (quiz_id, enrollment_id, attempted_on) VALUES (1, v_att_enr, '2026-09-25 12:00:00');
        SET v_new_att = LAST_INSERT_ID();
        INSERT INTO test_results (area, test_case, expected, actual, status)
        VALUES ('Quiz', 'Valid attempt gets the next sequential attempt number', 'attempt_no = count',
                CONCAT('attempt_no = ', (SELECT attempt_no FROM quiz_attempt WHERE attempt_id = v_new_att)),
                IF((SELECT attempt_no FROM quiz_attempt WHERE attempt_id = v_new_att) =
                   (SELECT COUNT(*) FROM quiz_attempt WHERE quiz_id = 1 AND enrollment_id = v_att_enr), 'PASS', 'FAIL'));
    END;

    BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
            INSERT INTO test_results (area, test_case, expected, actual, status)
            VALUES ('Quiz', 'Answer with an option from a different question', 'rejected', LEFT(v_msg, 160),
                    IF(v_msg LIKE '%does not belong to the question%', 'PASS', 'FAIL'));
        END;
        INSERT INTO quiz_answer (attempt_id, question_id, selected_option_id) VALUES (v_new_att, v_q1, v_opt_q2);
        INSERT INTO test_results (area, test_case, expected, actual, status)
        VALUES ('Quiz', 'Answer with an option from a different question', 'rejected', 'NO ERROR RAISED', 'FAIL');
    END;

    BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
            INSERT INTO test_results (area, test_case, expected, actual, status)
            VALUES ('Quiz', 'Change answers on an attempt that is already scored', 'rejected', LEFT(v_msg, 160),
                    IF(v_msg LIKE '%already been scored%', 'PASS', 'FAIL'));
        END;
        INSERT INTO quiz_answer (attempt_id, question_id, selected_option_id) VALUES (v_done_att, v_q1, v_opt_q1);
        INSERT INTO test_results (area, test_case, expected, actual, status)
        VALUES ('Quiz', 'Change answers on an attempt that is already scored', 'rejected', 'NO ERROR RAISED', 'FAIL');
    END;

    BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
            INSERT INTO test_results (area, test_case, expected, actual, status)
            VALUES ('Quiz', 'Add a second correct option to a question', 'rejected', LEFT(v_msg, 160),
                    IF(v_msg LIKE '%only one correct%', 'PASS', 'FAIL'));
        END;
        INSERT INTO question_option (question_id, option_text, is_correct) VALUES (v_q1, 'Another right answer', TRUE);
        INSERT INTO test_results (area, test_case, expected, actual, status)
        VALUES ('Quiz', 'Add a second correct option to a question', 'rejected', 'NO ERROR RAISED', 'FAIL');
    END;

    -- ===================== STAFF AND PREREQUISITES =====================
    BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
            INSERT INTO test_results (area, test_case, expected, actual, status)
            VALUES ('Staff', 'Second primary instructor on one offering', 'rejected', LEFT(v_msg, 160),
                    IF(v_msg LIKE '%already has a primary%', 'PASS', 'FAIL'));
        END;
        INSERT INTO offering_instructor (offering_id, instructor_id, role) VALUES (1, 3, 'primary');
        INSERT INTO test_results (area, test_case, expected, actual, status)
        VALUES ('Staff', 'Second primary instructor on one offering', 'rejected', 'NO ERROR RAISED', 'FAIL');
    END;

    BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
            INSERT INTO test_results (area, test_case, expected, actual, status)
            VALUES ('Prerequisite', 'Circular prerequisite (A needs B, B needs A)', 'rejected', LEFT(v_msg, 160),
                    IF(v_msg LIKE '%circular%', 'PASS', 'FAIL'));
        END;
        INSERT INTO course_prerequisite (course_id, prerequisite_course_id) VALUES (7, 1);
        INSERT INTO test_results (area, test_case, expected, actual, status)
        VALUES ('Prerequisite', 'Circular prerequisite (A needs B, B needs A)', 'rejected', 'NO ERROR RAISED', 'FAIL');
    END;

    BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
            INSERT INTO test_results (area, test_case, expected, actual, status)
            VALUES ('Prerequisite', 'Course that is its own prerequisite', 'rejected', LEFT(v_msg, 160),
                    IF(v_msg LIKE '%heck constraint%' OR v_msg LIKE '%CONSTRAINT%', 'PASS', 'FAIL'));
        END;
        INSERT INTO course_prerequisite (course_id, prerequisite_course_id) VALUES (3, 3);
        INSERT INTO test_results (area, test_case, expected, actual, status)
        VALUES ('Prerequisite', 'Course that is its own prerequisite', 'rejected', 'NO ERROR RAISED', 'FAIL');
    END;

    -- ===================== FUNCTIONS =====================
    INSERT INTO test_results (area, test_case, expected, actual, status) VALUES
        ('Function', 'fn_letter_grade(95) = A+',            'A+', fn_letter_grade(95),    IF(fn_letter_grade(95)    = 'A+', 'PASS', 'FAIL')),
        ('Function', 'fn_letter_grade(50) = D (boundary)',  'D',  fn_letter_grade(50),    IF(fn_letter_grade(50)    = 'D',  'PASS', 'FAIL')),
        ('Function', 'fn_letter_grade(49.99) = F',          'F',  fn_letter_grade(49.99), IF(fn_letter_grade(49.99) = 'F',  'PASS', 'FAIL')),
        ('Function', 'fn_attendance_deduction(75) = 0 (boundary)', '0',  fn_attendance_deduction(75),  IF(fn_attendance_deduction(75)  = 0,  'PASS', 'FAIL')),
        ('Function', 'fn_attendance_deduction(70) = 2',     '2',  fn_attendance_deduction(70),  IF(fn_attendance_deduction(70)  = 2,  'PASS', 'FAIL')),
        ('Function', 'fn_attendance_deduction(30) = 10 (cap)', '10', fn_attendance_deduction(30), IF(fn_attendance_deduction(30) = 10, 'PASS', 'FAIL')),
        ('Function', 'fn_attendance_deduction(NULL) = 0',   '0',  fn_attendance_deduction(NULL), IF(fn_attendance_deduction(NULL) = 0, 'PASS', 'FAIL'));

    -- ===================== RESULT CALCULATION (hand-computed) =====================
    -- v_new_enr: one assignment graded 15/20 = 75%, no quiz, no attendance -> final must be 75.00
    DELETE FROM submission WHERE enrollment_id = v_new_enr;
    INSERT INTO submission (assignment_id, enrollment_id, submitted_on, content_url)
    VALUES (v_a1, v_new_enr, '2026-09-10 10:00:00', 'https://example.com/a1');
    CALL sp_grade_submission(LAST_INSERT_ID(), 15, 'ok', (SELECT instructor_id FROM offering_instructor WHERE offering_id = 6 AND role = 'primary'));
    CALL sp_calculate_result(v_new_enr, 0);
    SELECT CAST(final_percentage AS CHAR) INTO v_val FROM course_result WHERE enrollment_id = v_new_enr;
    INSERT INTO test_results (area, test_case, expected, actual, status)
    VALUES ('Result', '15/20 assignment, nothing else assessed -> 75.00', '75.00', v_val, IF(v_val = '75.00', 'PASS', 'FAIL'));

    -- add 10 sessions: 7 present, 3 absent = 70% attendance -> deduction 2 -> final must be 73.00
    INSERT INTO attendance (session_id, enrollment_id, status)
    SELECT session_id, v_new_enr, IF(rn <= 7, 'present', 'absent')
    FROM (SELECT session_id, ROW_NUMBER() OVER (ORDER BY session_date) AS rn
            FROM class_session WHERE offering_id = 6 AND session_date <= CURRENT_DATE) t
    WHERE rn <= 10;
    CALL sp_calculate_result(v_new_enr, 0);
    SELECT CAST(final_percentage AS CHAR) INTO v_val FROM course_result WHERE enrollment_id = v_new_enr;
    INSERT INTO test_results (area, test_case, expected, actual, status)
    VALUES ('Result', '75% base with 70% attendance (-2 deduction) -> 73.00', '73.00', v_val, IF(v_val = '73.00', 'PASS', 'FAIL'));

    BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
            INSERT INTO test_results (area, test_case, expected, actual, status)
            VALUES ('Result', 'Result for an enrollment with nothing assessed', 'rejected', LEFT(v_msg, 160),
                    IF(v_msg LIKE '%nothing has been assessed%', 'PASS', 'FAIL'));
        END;
        DELETE FROM submission WHERE enrollment_id = v_new_enr;
        UPDATE assignment SET due_date = DATE_ADD(NOW(), INTERVAL 40 DAY) WHERE offering_id = 6;
        CALL sp_calculate_result(v_new_enr, 0);
        INSERT INTO test_results (area, test_case, expected, actual, status)
        VALUES ('Result', 'Result for an enrollment with nothing assessed', 'rejected', 'NO ERROR RAISED', 'FAIL');
    END;

    BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
            INSERT INTO test_results (area, test_case, expected, actual, status)
            VALUES ('Enrollment', 'Re-grade or change a completed (finalised) enrollment', 'rejected', LEFT(v_msg, 160),
                    IF(v_msg LIKE '%finalised%', 'PASS', 'FAIL'));
        END;
        UPDATE enrollment SET status = 'enrolled' WHERE offering_id = 7 LIMIT 1;
        INSERT INTO test_results (area, test_case, expected, actual, status)
        VALUES ('Enrollment', 'Re-grade or change a completed (finalised) enrollment', 'rejected', 'NO ERROR RAISED', 'FAIL');
    END;

    ROLLBACK;

    SELECT test_no, area, test_case, expected, actual, status FROM test_results ORDER BY test_no;
    SELECT SUM(status = 'PASS') AS passed, SUM(status = 'FAIL') AS failed, COUNT(*) AS total FROM test_results;
END$$

DELIMITER ;

CALL sp_run_phase2_tests();
