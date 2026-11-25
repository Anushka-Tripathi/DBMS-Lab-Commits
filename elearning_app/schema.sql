-- =====================================================================
-- E-Learning & Course Management Database  |  Phase 1 schema (MySQL 8.0.16+)
-- Models a real college LMS: programs, academic terms, course catalog vs.
-- term-wise course offerings (sections), co-teaching, prerequisites,
-- modules, class attendance, assignments, quizzes and final results.
-- Normalised to 3NF. This exact schema is reused in Phases 2-5.
-- =====================================================================

DROP DATABASE IF EXISTS elearning_db;
CREATE DATABASE elearning_db CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE elearning_db;

-- =====================================================================
-- 1. ACADEMIC STRUCTURE
-- =====================================================================
CREATE TABLE department (
    department_id   INT AUTO_INCREMENT PRIMARY KEY,
    department_code VARCHAR(10)  NOT NULL UNIQUE,
    department_name VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE program (
    program_id     INT AUTO_INCREMENT PRIMARY KEY,
    program_name   VARCHAR(100) NOT NULL UNIQUE,          -- e.g. B.Tech CSE (AI & ML)
    department_id  INT NOT NULL,
    degree_level   ENUM('Diploma','Undergraduate','Postgraduate','Doctoral') NOT NULL,
    duration_years TINYINT NOT NULL,
    FOREIGN KEY (department_id) REFERENCES department(department_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CHECK (duration_years BETWEEN 1 AND 6)
);

CREATE TABLE academic_term (
    term_id     INT AUTO_INCREMENT PRIMARY KEY,
    term_name   VARCHAR(50) NOT NULL UNIQUE,              -- e.g. 2026-27 Odd Semester
    start_date  DATE NOT NULL,
    end_date    DATE NOT NULL,
    is_current  BOOLEAN NOT NULL DEFAULT FALSE,
    CHECK (end_date > start_date)
);

-- Letter grade is looked up from the percentage (keeps results in 3NF)
CREATE TABLE grade_scale (
    grade_letter   VARCHAR(2)   PRIMARY KEY,
    min_percentage DECIMAL(5,2) NOT NULL UNIQUE,
    grade_points   DECIMAL(3,1) NOT NULL,
    CHECK (min_percentage BETWEEN 0 AND 100)
);

-- =====================================================================
-- 2. PEOPLE AND LOGIN
-- =====================================================================
CREATE TABLE student (
    student_id       INT AUTO_INCREMENT PRIMARY KEY,
    roll_number      VARCHAR(20)  NOT NULL UNIQUE,
    first_name       VARCHAR(50)  NOT NULL,
    last_name        VARCHAR(50)  NOT NULL,
    email            VARCHAR(100) NOT NULL UNIQUE,
    phone            VARCHAR(15),
    date_of_birth    DATE,
    program_id       INT NOT NULL,
    admission_year   YEAR NOT NULL,
    current_semester TINYINT NOT NULL DEFAULT 1,
    status           ENUM('active','graduated','suspended','withdrawn') NOT NULL DEFAULT 'active',
    FOREIGN KEY (program_id) REFERENCES program(program_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CHECK (current_semester BETWEEN 1 AND 12)
);

CREATE TABLE instructor (
    instructor_id INT AUTO_INCREMENT PRIMARY KEY,
    employee_code VARCHAR(20)  NOT NULL UNIQUE,
    first_name    VARCHAR(50)  NOT NULL,
    last_name     VARCHAR(50)  NOT NULL,
    email         VARCHAR(100) NOT NULL UNIQUE,
    department_id INT NOT NULL,
    designation   ENUM('Professor','Associate Professor','Assistant Professor','Lecturer','Teaching Assistant') NOT NULL,
    hire_date     DATE NOT NULL,
    is_active     BOOLEAN NOT NULL DEFAULT TRUE,
    FOREIGN KEY (department_id) REFERENCES department(department_id)
        ON UPDATE CASCADE ON DELETE RESTRICT
);

-- Logins; used for role-based access in Phases 4-5
CREATE TABLE user_account (
    user_id       INT AUTO_INCREMENT PRIMARY KEY,
    username      VARCHAR(50)  NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    role          ENUM('admin','instructor','student') NOT NULL,
    student_id    INT UNIQUE NULL,
    instructor_id INT UNIQUE NULL,
    is_active     BOOLEAN NOT NULL DEFAULT TRUE,
    last_login    DATETIME NULL,
    FOREIGN KEY (student_id)    REFERENCES student(student_id)       ON DELETE CASCADE,
    FOREIGN KEY (instructor_id) REFERENCES instructor(instructor_id) ON DELETE CASCADE,
    CHECK (
        (role = 'admin'      AND student_id IS NULL     AND instructor_id IS NULL) OR
        (role = 'student'    AND student_id IS NOT NULL AND instructor_id IS NULL) OR
        (role = 'instructor' AND instructor_id IS NOT NULL AND student_id IS NULL)
    )
);

-- =====================================================================
-- 3. COURSE CATALOG AND TERM-WISE OFFERINGS
-- =====================================================================
-- Catalog entry: what the course is (independent of any term)
CREATE TABLE course (
    course_id     INT AUTO_INCREMENT PRIMARY KEY,
    course_code   VARCHAR(15)  NOT NULL UNIQUE,
    title         VARCHAR(150) NOT NULL,
    description   TEXT,
    department_id INT NOT NULL,
    credits       TINYINT NOT NULL DEFAULT 3,
    FOREIGN KEY (department_id) REFERENCES department(department_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CHECK (credits BETWEEN 1 AND 10)
);

-- A course may require other courses first (many-to-many, self-referencing)
CREATE TABLE course_prerequisite (
    course_id              INT NOT NULL,
    prerequisite_course_id INT NOT NULL,
    PRIMARY KEY (course_id, prerequisite_course_id),
    FOREIGN KEY (course_id)              REFERENCES course(course_id) ON DELETE CASCADE,
    FOREIGN KEY (prerequisite_course_id) REFERENCES course(course_id) ON DELETE CASCADE,
    CHECK (course_id <> prerequisite_course_id)
);

-- Offering: the course as run in one term / section; everything students do hangs off this
CREATE TABLE course_offering (
    offering_id       INT AUTO_INCREMENT PRIMARY KEY,
    course_id         INT NOT NULL,
    term_id           INT NOT NULL,
    section_code      VARCHAR(5) NOT NULL DEFAULT 'A',
    max_capacity      SMALLINT NOT NULL DEFAULT 60,
    assignment_weight DECIMAL(5,2) NOT NULL DEFAULT 50.00,
    quiz_weight       DECIMAL(5,2) NOT NULL DEFAULT 50.00,
    UNIQUE (course_id, term_id, section_code),
    FOREIGN KEY (course_id) REFERENCES course(course_id)        ON DELETE RESTRICT,
    FOREIGN KEY (term_id)   REFERENCES academic_term(term_id)   ON DELETE RESTRICT,
    CHECK (max_capacity > 0),
    CHECK (assignment_weight >= 0 AND quiz_weight >= 0 AND assignment_weight + quiz_weight = 100)
);

-- Several instructors / TAs can teach one offering
CREATE TABLE offering_instructor (
    offering_id   INT NOT NULL,
    instructor_id INT NOT NULL,
    role          ENUM('primary','co-instructor','teaching-assistant') NOT NULL DEFAULT 'primary',
    PRIMARY KEY (offering_id, instructor_id),
    FOREIGN KEY (offering_id)   REFERENCES course_offering(offering_id) ON DELETE CASCADE,
    FOREIGN KEY (instructor_id) REFERENCES instructor(instructor_id)    ON DELETE RESTRICT
);

-- =====================================================================
-- 4. ENROLLMENT
-- =====================================================================
CREATE TABLE enrollment (
    enrollment_id INT AUTO_INCREMENT PRIMARY KEY,
    student_id    INT NOT NULL,
    offering_id   INT NOT NULL,
    enrolled_on   DATE NOT NULL DEFAULT (CURRENT_DATE),
    status        ENUM('enrolled','dropped','completed','failed') NOT NULL DEFAULT 'enrolled',
    UNIQUE (student_id, offering_id),
    FOREIGN KEY (student_id)  REFERENCES student(student_id)           ON DELETE CASCADE,
    FOREIGN KEY (offering_id) REFERENCES course_offering(offering_id)  ON DELETE CASCADE
);

-- =====================================================================
-- 5. LEARNING CONTENT (modules and study material)
-- =====================================================================
CREATE TABLE module (
    module_id     INT AUTO_INCREMENT PRIMARY KEY,
    offering_id   INT NOT NULL,
    module_number TINYINT NOT NULL,
    title         VARCHAR(150) NOT NULL,
    UNIQUE (offering_id, module_number),
    FOREIGN KEY (offering_id) REFERENCES course_offering(offering_id) ON DELETE CASCADE,
    CHECK (module_number > 0)
);

CREATE TABLE material (
    material_id   INT AUTO_INCREMENT PRIMARY KEY,
    module_id     INT NOT NULL,
    title         VARCHAR(150) NOT NULL,
    material_type ENUM('video','pdf','slides','notebook','link','other') NOT NULL,
    resource_url  VARCHAR(500) NOT NULL,
    uploaded_by   INT NOT NULL,
    uploaded_on   DATE NOT NULL DEFAULT (CURRENT_DATE),
    FOREIGN KEY (module_id)   REFERENCES module(module_id)         ON DELETE CASCADE,
    FOREIGN KEY (uploaded_by) REFERENCES instructor(instructor_id) ON DELETE RESTRICT
);

-- =====================================================================
-- 6. ATTENDANCE
-- =====================================================================
CREATE TABLE class_session (
    session_id   INT AUTO_INCREMENT PRIMARY KEY,
    offering_id  INT NOT NULL,
    session_date DATE NOT NULL,
    start_time   TIME NOT NULL,
    end_time     TIME NOT NULL,
    topic        VARCHAR(200),
    UNIQUE (offering_id, session_date, start_time),
    FOREIGN KEY (offering_id) REFERENCES course_offering(offering_id) ON DELETE CASCADE,
    CHECK (end_time > start_time)
);

CREATE TABLE attendance (
    session_id    INT NOT NULL,
    enrollment_id INT NOT NULL,
    status        ENUM('present','absent','late','excused') NOT NULL DEFAULT 'present',
    PRIMARY KEY (session_id, enrollment_id),
    FOREIGN KEY (session_id)    REFERENCES class_session(session_id) ON DELETE CASCADE,
    FOREIGN KEY (enrollment_id) REFERENCES enrollment(enrollment_id) ON DELETE CASCADE
);

-- =====================================================================
-- 7. ASSIGNMENTS
-- =====================================================================
CREATE TABLE assignment (
    assignment_id INT AUTO_INCREMENT PRIMARY KEY,
    offering_id   INT NOT NULL,
    title         VARCHAR(150) NOT NULL,
    description   TEXT,
    max_marks     DECIMAL(6,2) NOT NULL,
    assigned_on   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    due_date      DATETIME NOT NULL,
    allow_late    BOOLEAN NOT NULL DEFAULT FALSE,
    FOREIGN KEY (offering_id) REFERENCES course_offering(offering_id) ON DELETE CASCADE,
    CHECK (max_marks > 0),
    CHECK (due_date > assigned_on)
);

-- Student is reached through enrollment_id (not stored twice, keeps 3NF)
CREATE TABLE submission (
    submission_id  INT AUTO_INCREMENT PRIMARY KEY,
    assignment_id  INT NOT NULL,
    enrollment_id  INT NOT NULL,
    submitted_on   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    content_url    VARCHAR(500),
    marks_obtained DECIMAL(6,2) NULL,
    graded_by      INT NULL,
    graded_on      DATETIME NULL,
    feedback       TEXT,
    UNIQUE (assignment_id, enrollment_id),
    FOREIGN KEY (assignment_id) REFERENCES assignment(assignment_id) ON DELETE CASCADE,
    FOREIGN KEY (enrollment_id) REFERENCES enrollment(enrollment_id) ON DELETE CASCADE,
    FOREIGN KEY (graded_by)     REFERENCES instructor(instructor_id) ON DELETE SET NULL,
    CHECK (marks_obtained IS NULL OR marks_obtained >= 0)
);

-- =====================================================================
-- 8. QUIZZES
-- =====================================================================
CREATE TABLE quiz (
    quiz_id            INT AUTO_INCREMENT PRIMARY KEY,
    offering_id        INT NOT NULL,
    title              VARCHAR(150) NOT NULL,
    time_limit_minutes SMALLINT NOT NULL DEFAULT 30,
    max_attempts       TINYINT NOT NULL DEFAULT 1,
    available_from     DATETIME NOT NULL,
    available_until    DATETIME NOT NULL,
    FOREIGN KEY (offering_id) REFERENCES course_offering(offering_id) ON DELETE CASCADE,
    CHECK (time_limit_minutes > 0),
    CHECK (max_attempts > 0),
    CHECK (available_until > available_from)
);

CREATE TABLE question (
    question_id   INT AUTO_INCREMENT PRIMARY KEY,
    quiz_id       INT NOT NULL,
    question_text TEXT NOT NULL,
    marks         DECIMAL(5,2) NOT NULL DEFAULT 1.00,
    FOREIGN KEY (quiz_id) REFERENCES quiz(quiz_id) ON DELETE CASCADE,
    CHECK (marks > 0)
);

CREATE TABLE question_option (
    option_id   INT AUTO_INCREMENT PRIMARY KEY,
    question_id INT NOT NULL,
    option_text VARCHAR(300) NOT NULL,
    is_correct  BOOLEAN NOT NULL DEFAULT FALSE,
    FOREIGN KEY (question_id) REFERENCES question(question_id) ON DELETE CASCADE
);

CREATE TABLE quiz_attempt (
    attempt_id    INT AUTO_INCREMENT PRIMARY KEY,
    quiz_id       INT NOT NULL,
    enrollment_id INT NOT NULL,
    attempt_no    TINYINT NOT NULL DEFAULT 1,
    attempted_on  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    score         DECIMAL(6,2) NULL,
    UNIQUE (quiz_id, enrollment_id, attempt_no),
    FOREIGN KEY (quiz_id)       REFERENCES quiz(quiz_id)             ON DELETE CASCADE,
    FOREIGN KEY (enrollment_id) REFERENCES enrollment(enrollment_id) ON DELETE CASCADE,
    CHECK (score IS NULL OR score >= 0)
);

CREATE TABLE quiz_answer (
    attempt_id         INT NOT NULL,
    question_id        INT NOT NULL,
    selected_option_id INT NOT NULL,
    PRIMARY KEY (attempt_id, question_id),
    FOREIGN KEY (attempt_id)         REFERENCES quiz_attempt(attempt_id)   ON DELETE CASCADE,
    FOREIGN KEY (question_id)        REFERENCES question(question_id)      ON DELETE CASCADE,
    FOREIGN KEY (selected_option_id) REFERENCES question_option(option_id) ON DELETE CASCADE
);

-- =====================================================================
-- 9. FINAL RESULT (one row per enrollment, filled by a procedure in Phase 2)
-- =====================================================================
CREATE TABLE course_result (
    enrollment_id    INT PRIMARY KEY,
    final_percentage DECIMAL(5,2) NOT NULL,
    computed_on      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (enrollment_id) REFERENCES enrollment(enrollment_id) ON DELETE CASCADE,
    CHECK (final_percentage BETWEEN 0 AND 100)
);

-- =====================================================================
-- Seed data for the lookup table
-- =====================================================================
INSERT INTO grade_scale (grade_letter, min_percentage, grade_points) VALUES
    ('A+', 90, 10.0), ('A', 80, 9.0), ('B', 70, 8.0),
    ('C', 60, 7.0),  ('D', 50, 6.0), ('F', 0, 0.0);
