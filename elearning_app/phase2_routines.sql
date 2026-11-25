-- =====================================================================
-- PHASE 2: Procedural implementation  (MySQL 8.0)
-- Run after schema.sql and seed.sql. The Phase 1 schema is NOT modified.
--
--   A. Stored functions   grade components, attendance deduction, letter grade
--   B. Stored procedures  result calculation, enrollment, grading, quiz scoring
--   C. Triggers           validate enrollment, submission, attendance, quiz entries
--
-- Grading rule (the "salary + deduction" of this domain)
--   base %   = weighted average of assignment % and quiz %, using the offering's
--              assignment_weight / quiz_weight (a component with nothing assessed
--              yet is left out and the remaining weights are rescaled)
--   deduction = attendance shortage: 2 marks for every started 5% below 75%, max 10
--   final %  = GREATEST(0, base % - deduction)  -> stored in course_result
-- =====================================================================
USE elearning_db;
DELIMITER $$

-- =====================================================================
-- A. STORED FUNCTIONS
-- =====================================================================

-- Attendance % for one enrollment (excused sessions are not counted); NULL if none recorded
DROP FUNCTION IF EXISTS fn_attendance_pct$$
CREATE FUNCTION fn_attendance_pct(p_enrollment_id INT)
RETURNS DECIMAL(5,2)
READS SQL DATA
BEGIN
    DECLARE v_pct DECIMAL(5,2);
    SELECT ROUND(100 * SUM(status IN ('present','late')) / NULLIF(SUM(status <> 'excused'), 0), 2)
      INTO v_pct
      FROM attendance
     WHERE enrollment_id = p_enrollment_id;
    RETURN v_pct;
END$$

-- Assignment % over assignments already past their due date.
-- A missing submission counts as 0; a submitted-but-ungraded one is left out for now.
DROP FUNCTION IF EXISTS fn_assignment_pct$$
CREATE FUNCTION fn_assignment_pct(p_enrollment_id INT)
RETURNS DECIMAL(5,2)
READS SQL DATA
BEGIN
    DECLARE v_off INT;
    DECLARE v_num DECIMAL(10,2);
    DECLARE v_den DECIMAL(10,2);

    SELECT offering_id INTO v_off FROM enrollment WHERE enrollment_id = p_enrollment_id;

    SELECT SUM(COALESCE(s.marks_obtained, 0)), SUM(a.max_marks)
      INTO v_num, v_den
      FROM assignment a
      LEFT JOIN submission s ON s.assignment_id = a.assignment_id
                            AND s.enrollment_id = p_enrollment_id
     WHERE a.offering_id = v_off
       AND a.due_date < NOW()
       AND NOT (s.submission_id IS NOT NULL AND s.marks_obtained IS NULL);

    RETURN IF(v_den IS NULL OR v_den = 0, NULL, ROUND(100 * v_num / v_den, 2));
END$$

-- Quiz % over quizzes that have closed, using the best attempt per quiz (no attempt = 0)
DROP FUNCTION IF EXISTS fn_quiz_pct$$
CREATE FUNCTION fn_quiz_pct(p_enrollment_id INT)
RETURNS DECIMAL(5,2)
READS SQL DATA
BEGIN
    DECLARE v_off INT;
    DECLARE v_num DECIMAL(10,2);
    DECLARE v_den DECIMAL(10,2);

    SELECT offering_id INTO v_off FROM enrollment WHERE enrollment_id = p_enrollment_id;

    SELECT SUM(COALESCE(best.score, 0)), SUM(tot.total_marks)
      INTO v_num, v_den
      FROM quiz q
      JOIN (SELECT quiz_id, SUM(marks) AS total_marks FROM question GROUP BY quiz_id) tot
        ON tot.quiz_id = q.quiz_id
      LEFT JOIN (SELECT quiz_id, MAX(score) AS score
                   FROM quiz_attempt
                  WHERE enrollment_id = p_enrollment_id
                  GROUP BY quiz_id) best
        ON best.quiz_id = q.quiz_id
     WHERE q.offering_id = v_off
       AND q.available_until < NOW();

    RETURN IF(v_den IS NULL OR v_den = 0, NULL, ROUND(100 * v_num / v_den, 2));
END$$

-- Deduction (percentage points) for attendance below 75%
DROP FUNCTION IF EXISTS fn_attendance_deduction$$
CREATE FUNCTION fn_attendance_deduction(p_attendance_pct DECIMAL(5,2))
RETURNS DECIMAL(5,2)
DETERMINISTIC
BEGIN
    IF p_attendance_pct IS NULL OR p_attendance_pct >= 75 THEN
        RETURN 0;
    END IF;
    RETURN LEAST(10, CEILING((75 - p_attendance_pct) / 5) * 2);
END$$

-- Letter grade from the grade_scale lookup table
DROP FUNCTION IF EXISTS fn_letter_grade$$
CREATE FUNCTION fn_letter_grade(p_pct DECIMAL(5,2))
RETURNS VARCHAR(2)
READS SQL DATA
BEGIN
    DECLARE v_grade VARCHAR(2);
    SELECT grade_letter INTO v_grade
      FROM grade_scale
     WHERE min_percentage <= p_pct
     ORDER BY min_percentage DESC
     LIMIT 1;
    RETURN v_grade;
END$$


-- =====================================================================
-- B. STORED PROCEDURES
-- =====================================================================

-- Final result for ONE enrollment. p_show = 1 also returns the breakdown as a result set.
DROP PROCEDURE IF EXISTS sp_calculate_result$$
CREATE PROCEDURE sp_calculate_result(IN p_enrollment_id INT, IN p_show TINYINT)
BEGIN
    DECLARE v_off     INT;
    DECLARE v_status  VARCHAR(20);
    DECLARE v_aw      DECIMAL(5,2);
    DECLARE v_qw      DECIMAL(5,2);
    DECLARE v_ap      DECIMAL(5,2);
    DECLARE v_qp      DECIMAL(5,2);
    DECLARE v_att     DECIMAL(5,2);
    DECLARE v_ded     DECIMAL(5,2);
    DECLARE v_wa      DECIMAL(5,2);
    DECLARE v_wq      DECIMAL(5,2);
    DECLARE v_base    DECIMAL(6,2);
    DECLARE v_final   DECIMAL(5,2);

    SELECT e.offering_id, e.status, o.assignment_weight, o.quiz_weight
      INTO v_off, v_status, v_aw, v_qw
      FROM enrollment e
      JOIN course_offering o ON o.offering_id = e.offering_id
     WHERE e.enrollment_id = p_enrollment_id;

    IF v_off IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Result rejected: enrollment not found.';
    END IF;
    IF v_status = 'dropped' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Result rejected: enrollment was dropped.';
    END IF;

    SET v_ap = fn_assignment_pct(p_enrollment_id);
    SET v_qp = fn_quiz_pct(p_enrollment_id);

    -- only weight the components that have actually been assessed
    SET v_wa = IF(v_ap IS NULL, 0, v_aw);
    SET v_wq = IF(v_qp IS NULL, 0, v_qw);
    IF v_wa + v_wq = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Result rejected: nothing has been assessed yet.';
    END IF;

    SET v_base  = (COALESCE(v_ap, 0) * v_wa + COALESCE(v_qp, 0) * v_wq) / (v_wa + v_wq);
    SET v_att   = fn_attendance_pct(p_enrollment_id);
    SET v_ded   = fn_attendance_deduction(v_att);
    SET v_final = GREATEST(0, ROUND(v_base - v_ded, 2));

    INSERT INTO course_result (enrollment_id, final_percentage, computed_on)
    VALUES (p_enrollment_id, v_final, NOW())
    ON DUPLICATE KEY UPDATE final_percentage = v_final, computed_on = NOW();

    IF p_show = 1 THEN
        SELECT p_enrollment_id        AS enrollment_id,
               v_ap                   AS assignment_pct,
               v_qp                   AS quiz_pct,
               ROUND(v_base, 2)       AS weighted_base_pct,
               v_att                  AS attendance_pct,
               v_ded                  AS attendance_deduction,
               v_final                AS final_percentage,
               fn_letter_grade(v_final) AS grade;
    END IF;
END$$

-- Results for every active enrollment in an offering; skips students with nothing assessed
DROP PROCEDURE IF EXISTS sp_calculate_offering_results$$
CREATE PROCEDURE sp_calculate_offering_results(IN p_offering_id INT)
BEGIN
    DECLARE v_done  INT DEFAULT 0;
    DECLARE v_eid   INT;
    DECLARE v_total INT DEFAULT 0;
    DECLARE v_skip  INT DEFAULT 0;
    DECLARE cur CURSOR FOR
        SELECT enrollment_id FROM enrollment
         WHERE offering_id = p_offering_id AND status = 'enrolled';
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = 1;
    DECLARE CONTINUE HANDLER FOR SQLSTATE '45000' SET v_skip = v_skip + 1;

    IF NOT EXISTS (SELECT 1 FROM course_offering WHERE offering_id = p_offering_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Offering not found.';
    END IF;

    OPEN cur;
    read_loop: LOOP
        FETCH cur INTO v_eid;
        IF v_done = 1 THEN LEAVE read_loop; END IF;
        SET v_total = v_total + 1;
        CALL sp_calculate_result(v_eid, 0);
    END LOOP;
    CLOSE cur;

    SELECT v_total - v_skip AS results_calculated, v_skip AS skipped_nothing_assessed;
END$$

-- Enroll a student (or re-activate a dropped enrollment). The enrollment triggers do the
-- validation; locking the offering row makes the capacity check safe under concurrency.
DROP PROCEDURE IF EXISTS sp_enroll_student$$
CREATE PROCEDURE sp_enroll_student(IN p_student_id INT, IN p_offering_id INT)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    IF NOT EXISTS (SELECT 1 FROM course_offering WHERE offering_id = p_offering_id FOR UPDATE) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Enrollment rejected: offering not found.';
    END IF;

    IF EXISTS (SELECT 1 FROM enrollment
                WHERE student_id = p_student_id AND offering_id = p_offering_id
                  AND status = 'dropped') THEN
        UPDATE enrollment SET status = 'enrolled', enrolled_on = CURRENT_DATE
         WHERE student_id = p_student_id AND offering_id = p_offering_id;
    ELSE
        INSERT INTO enrollment (student_id, offering_id) VALUES (p_student_id, p_offering_id);
    END IF;

    COMMIT;
END$$

-- Grade a submission. The submission triggers check the range and that the grader teaches the course.
DROP PROCEDURE IF EXISTS sp_grade_submission$$
CREATE PROCEDURE sp_grade_submission(IN p_submission_id INT, IN p_marks DECIMAL(6,2),
                                     IN p_feedback TEXT, IN p_instructor_id INT)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM submission WHERE submission_id = p_submission_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Grading rejected: submission not found.';
    END IF;

    UPDATE submission
       SET marks_obtained = p_marks,
           feedback       = p_feedback,
           graded_by      = p_instructor_id
     WHERE submission_id = p_submission_id;
END$$

-- Score one quiz attempt from the answers given (sum of marks of correctly answered questions)
DROP PROCEDURE IF EXISTS sp_score_quiz_attempt$$
CREATE PROCEDURE sp_score_quiz_attempt(IN p_attempt_id INT)
BEGIN
    UPDATE quiz_attempt qa
       SET qa.score = COALESCE((SELECT SUM(q.marks)
                                  FROM quiz_answer a
                                  JOIN question q        ON q.question_id = a.question_id
                                  JOIN question_option o ON o.option_id   = a.selected_option_id
                                 WHERE a.attempt_id = qa.attempt_id AND o.is_correct = 1), 0)
     WHERE qa.attempt_id = p_attempt_id;
END$$

-- Score every attempt of a quiz at once
DROP PROCEDURE IF EXISTS sp_score_quiz$$
CREATE PROCEDURE sp_score_quiz(IN p_quiz_id INT)
BEGIN
    UPDATE quiz_attempt qa
       SET qa.score = COALESCE((SELECT SUM(q.marks)
                                  FROM quiz_answer a
                                  JOIN question q        ON q.question_id = a.question_id
                                  JOIN question_option o ON o.option_id   = a.selected_option_id
                                 WHERE a.attempt_id = qa.attempt_id AND o.is_correct = 1), 0)
     WHERE qa.quiz_id = p_quiz_id;
END$$

-- End-of-term: compute results, then mark each active enrollment completed or failed.
-- Pass mark is the minimum percentage of grade 'D' in grade_scale. All-or-nothing.
DROP PROCEDURE IF EXISTS sp_finalize_offering$$
CREATE PROCEDURE sp_finalize_offering(IN p_offering_id INT)
BEGIN
    DECLARE v_pass DECIMAL(5,2);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    SELECT min_percentage INTO v_pass FROM grade_scale WHERE grade_letter = 'D';

    START TRANSACTION;
    CALL sp_calculate_offering_results(p_offering_id);

    UPDATE enrollment e
      JOIN course_result r ON r.enrollment_id = e.enrollment_id
       SET e.status = IF(r.final_percentage >= v_pass, 'completed', 'failed')
     WHERE e.offering_id = p_offering_id AND e.status = 'enrolled';
    COMMIT;
END$$


-- =====================================================================
-- C. TRIGGERS
-- =====================================================================

-- ---------- enrollment ----------
DROP TRIGGER IF EXISTS trg_enrollment_bi$$
CREATE TRIGGER trg_enrollment_bi BEFORE INSERT ON enrollment
FOR EACH ROW
BEGIN
    DECLARE v_student_status VARCHAR(20);
    DECLARE v_cap     SMALLINT;
    DECLARE v_course  INT;
    DECLARE v_term    INT;
    DECLARE v_taken   INT;
    DECLARE v_missing VARCHAR(80);
    DECLARE v_msg     VARCHAR(128);

    IF NEW.status = 'enrolled' THEN
        SELECT status INTO v_student_status FROM student WHERE student_id = NEW.student_id;
        IF v_student_status <> 'active' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Enrollment rejected: only active students can enroll.';
        END IF;

        SELECT max_capacity, course_id, term_id INTO v_cap, v_course, v_term
          FROM course_offering WHERE offering_id = NEW.offering_id;

        SELECT COUNT(*) INTO v_taken FROM enrollment
         WHERE offering_id = NEW.offering_id AND status <> 'dropped';
        IF v_taken >= v_cap THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Enrollment rejected: this offering is full.';
        END IF;

        IF EXISTS (SELECT 1 FROM enrollment e
                     JOIN course_offering o ON o.offering_id = e.offering_id
                    WHERE e.student_id = NEW.student_id AND o.course_id = v_course
                      AND o.term_id = v_term AND e.status <> 'dropped') THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Enrollment rejected: student is already enrolled in this course this term.';
        END IF;

        SELECT GROUP_CONCAT(pc.course_code SEPARATOR ', ') INTO v_missing
          FROM course_prerequisite cp
          JOIN course pc ON pc.course_id = cp.prerequisite_course_id
         WHERE cp.course_id = v_course
           AND NOT EXISTS (SELECT 1 FROM enrollment e2
                             JOIN course_offering o2 ON o2.offering_id = e2.offering_id
                            WHERE e2.student_id = NEW.student_id
                              AND o2.course_id = cp.prerequisite_course_id
                              AND e2.status = 'completed');
        IF v_missing IS NOT NULL THEN
            SET v_msg = CONCAT('Enrollment rejected: prerequisite not completed (', v_missing, ').');
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
        END IF;
    END IF;
END$$

DROP TRIGGER IF EXISTS trg_enrollment_bu$$
CREATE TRIGGER trg_enrollment_bu BEFORE UPDATE ON enrollment
FOR EACH ROW
BEGIN
    DECLARE v_cap   SMALLINT;
    DECLARE v_taken INT;

    IF NEW.student_id <> OLD.student_id OR NEW.offering_id <> OLD.offering_id THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Enrollment rejected: student and offering cannot be changed.';
    END IF;
    IF OLD.status IN ('completed','failed') AND NEW.status <> OLD.status THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Enrollment rejected: a finalised enrollment cannot be changed.';
    END IF;
    IF OLD.status = 'dropped' AND NEW.status = 'enrolled' THEN
        SELECT max_capacity INTO v_cap FROM course_offering WHERE offering_id = NEW.offering_id;
        SELECT COUNT(*) INTO v_taken FROM enrollment
         WHERE offering_id = NEW.offering_id AND status <> 'dropped';
        IF v_taken >= v_cap THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Enrollment rejected: this offering is full.';
        END IF;
    END IF;
END$$

-- ---------- assignment submissions ----------
DROP TRIGGER IF EXISTS trg_submission_bi$$
CREATE TRIGGER trg_submission_bi BEFORE INSERT ON submission
FOR EACH ROW
BEGIN
    DECLARE v_e_off    INT;
    DECLARE v_e_status VARCHAR(20);
    DECLARE v_a_off    INT;
    DECLARE v_due      DATETIME;
    DECLARE v_late     TINYINT;
    DECLARE v_max      DECIMAL(6,2);

    SELECT offering_id, status INTO v_e_off, v_e_status
      FROM enrollment WHERE enrollment_id = NEW.enrollment_id;
    SELECT offering_id, due_date, allow_late, max_marks INTO v_a_off, v_due, v_late, v_max
      FROM assignment WHERE assignment_id = NEW.assignment_id;

    IF v_e_status <> 'enrolled' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Submission rejected: student is not actively enrolled.';
    END IF;
    IF v_e_off <> v_a_off THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Submission rejected: assignment does not belong to this course.';
    END IF;
    IF NEW.submitted_on > v_due AND v_late = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Submission rejected: deadline passed and late submissions are not allowed.';
    END IF;
    IF NEW.marks_obtained IS NOT NULL AND NEW.marks_obtained > v_max THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Marks exceed the maximum for this assignment.';
    END IF;
END$$

DROP TRIGGER IF EXISTS trg_submission_bu$$
CREATE TRIGGER trg_submission_bu BEFORE UPDATE ON submission
FOR EACH ROW
BEGIN
    DECLARE v_max DECIMAL(6,2);
    DECLARE v_off INT;

    IF NEW.assignment_id <> OLD.assignment_id OR NEW.enrollment_id <> OLD.enrollment_id THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Submission rejected: assignment and student cannot be changed.';
    END IF;

    IF NEW.marks_obtained IS NOT NULL THEN
        SELECT max_marks, offering_id INTO v_max, v_off
          FROM assignment WHERE assignment_id = NEW.assignment_id;
        IF NEW.marks_obtained > v_max THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Marks exceed the maximum for this assignment.';
        END IF;
        IF NEW.graded_by IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Grading rejected: the grader must be recorded.';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM offering_instructor
                        WHERE offering_id = v_off AND instructor_id = NEW.graded_by) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Grading rejected: grader is not assigned to this course.';
        END IF;
        IF OLD.marks_obtained IS NULL OR NEW.marks_obtained <> OLD.marks_obtained THEN
            SET NEW.graded_on = NOW();
        END IF;
    END IF;
END$$

-- ---------- attendance ----------
DROP TRIGGER IF EXISTS trg_attendance_bi$$
CREATE TRIGGER trg_attendance_bi BEFORE INSERT ON attendance
FOR EACH ROW
BEGIN
    DECLARE v_s_off    INT;
    DECLARE v_s_date   DATE;
    DECLARE v_e_off    INT;
    DECLARE v_e_status VARCHAR(20);

    SELECT offering_id, session_date INTO v_s_off, v_s_date
      FROM class_session WHERE session_id = NEW.session_id;
    SELECT offering_id, status INTO v_e_off, v_e_status
      FROM enrollment WHERE enrollment_id = NEW.enrollment_id;

    IF v_s_off <> v_e_off THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Attendance rejected: student is not enrolled in this course.';
    END IF;
    IF v_e_status <> 'enrolled' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Attendance rejected: enrollment is not active.';
    END IF;
    IF v_s_date > CURRENT_DATE THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Attendance cannot be marked for a future session.';
    END IF;
END$$

-- ---------- quizzes ----------
DROP TRIGGER IF EXISTS trg_quiz_attempt_bi$$
CREATE TRIGGER trg_quiz_attempt_bi BEFORE INSERT ON quiz_attempt
FOR EACH ROW
BEGIN
    DECLARE v_q_off    INT;
    DECLARE v_from     DATETIME;
    DECLARE v_until    DATETIME;
    DECLARE v_max      TINYINT;
    DECLARE v_e_off    INT;
    DECLARE v_e_status VARCHAR(20);
    DECLARE v_prev     INT;

    SELECT offering_id, available_from, available_until, max_attempts
      INTO v_q_off, v_from, v_until, v_max FROM quiz WHERE quiz_id = NEW.quiz_id;
    SELECT offering_id, status INTO v_e_off, v_e_status
      FROM enrollment WHERE enrollment_id = NEW.enrollment_id;

    IF v_e_status <> 'enrolled' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Quiz attempt rejected: student is not actively enrolled.';
    END IF;
    IF v_e_off <> v_q_off THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Quiz attempt rejected: quiz does not belong to this course.';
    END IF;
    IF NEW.attempted_on < v_from OR NEW.attempted_on > v_until THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Quiz attempt rejected: the quiz is not open.';
    END IF;

    SELECT COUNT(*) INTO v_prev FROM quiz_attempt
     WHERE quiz_id = NEW.quiz_id AND enrollment_id = NEW.enrollment_id;
    IF v_prev >= v_max THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Quiz attempt rejected: maximum attempts reached.';
    END IF;
    SET NEW.attempt_no = v_prev + 1;      -- attempt numbers are always sequential
END$$

DROP TRIGGER IF EXISTS trg_quiz_answer_bi$$
CREATE TRIGGER trg_quiz_answer_bi BEFORE INSERT ON quiz_answer
FOR EACH ROW
BEGIN
    DECLARE v_att_quiz INT;
    DECLARE v_score    DECIMAL(6,2);
    DECLARE v_q_quiz   INT;
    DECLARE v_opt_q    INT;

    SELECT quiz_id, score INTO v_att_quiz, v_score FROM quiz_attempt WHERE attempt_id = NEW.attempt_id;
    SELECT quiz_id INTO v_q_quiz FROM question WHERE question_id = NEW.question_id;
    SELECT question_id INTO v_opt_q FROM question_option WHERE option_id = NEW.selected_option_id;

    IF v_att_quiz <> v_q_quiz THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Answer rejected: question is not part of this quiz.';
    END IF;
    IF v_opt_q <> NEW.question_id THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Answer rejected: option does not belong to the question.';
    END IF;
    IF v_score IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Answer rejected: this attempt has already been scored.';
    END IF;
END$$

DROP TRIGGER IF EXISTS trg_option_bi$$
CREATE TRIGGER trg_option_bi BEFORE INSERT ON question_option
FOR EACH ROW
BEGIN
    IF NEW.is_correct AND EXISTS (SELECT 1 FROM question_option
                                   WHERE question_id = NEW.question_id AND is_correct = 1) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'A question can have only one correct option.';
    END IF;
END$$

DROP TRIGGER IF EXISTS trg_option_bu$$
CREATE TRIGGER trg_option_bu BEFORE UPDATE ON question_option
FOR EACH ROW
BEGIN
    IF NEW.is_correct AND EXISTS (SELECT 1 FROM question_option
                                   WHERE question_id = NEW.question_id AND is_correct = 1
                                     AND option_id <> OLD.option_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'A question can have only one correct option.';
    END IF;
END$$

-- ---------- teaching staff and prerequisites ----------
DROP TRIGGER IF EXISTS trg_offering_instructor_bi$$
CREATE TRIGGER trg_offering_instructor_bi BEFORE INSERT ON offering_instructor
FOR EACH ROW
BEGIN
    DECLARE v_active TINYINT;
    SELECT is_active INTO v_active FROM instructor WHERE instructor_id = NEW.instructor_id;
    IF v_active = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Assignment rejected: instructor is not active.';
    END IF;
    IF NEW.role = 'primary' AND EXISTS (SELECT 1 FROM offering_instructor
                                         WHERE offering_id = NEW.offering_id AND role = 'primary') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Assignment rejected: this offering already has a primary instructor.';
    END IF;
END$$

DROP TRIGGER IF EXISTS trg_offering_instructor_bu$$
CREATE TRIGGER trg_offering_instructor_bu BEFORE UPDATE ON offering_instructor
FOR EACH ROW
BEGIN
    IF NEW.role = 'primary' AND OLD.role <> 'primary'
       AND EXISTS (SELECT 1 FROM offering_instructor
                    WHERE offering_id = NEW.offering_id AND role = 'primary'
                      AND instructor_id <> OLD.instructor_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Assignment rejected: this offering already has a primary instructor.';
    END IF;
END$$

DROP TRIGGER IF EXISTS trg_prerequisite_bi$$
CREATE TRIGGER trg_prerequisite_bi BEFORE INSERT ON course_prerequisite
FOR EACH ROW
BEGIN
    IF EXISTS (SELECT 1 FROM course_prerequisite
                WHERE course_id = NEW.prerequisite_course_id
                  AND prerequisite_course_id = NEW.course_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Prerequisite rejected: circular dependency between the two courses.';
    END IF;
END$$

DELIMITER ;
