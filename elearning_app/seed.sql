USE elearning_db;

-- ---------- Academic structure ----------
INSERT INTO department (department_code, department_name) VALUES
    ('CSE', 'Computer Science & Engineering'),
    ('MATH', 'Mathematics'),
    ('HUM', 'Humanities & Communication');

INSERT INTO program (program_name, department_id, degree_level, duration_years) VALUES
    ('B.Tech CSE (AI & ML)', 1, 'Undergraduate', 4),
    ('B.Tech CSE (Core)',    1, 'Undergraduate', 4),
    ('M.Tech CSE',           1, 'Postgraduate',  2);

INSERT INTO academic_term (term_name, start_date, end_date, is_current) VALUES
    ('2025-26 Even Semester', '2026-01-12', '2026-05-29', FALSE),
    ('2026-27 Odd Semester',  '2026-08-03', '2026-12-18', TRUE);

-- ---------- Instructors ----------
INSERT INTO instructor (employee_code, first_name, last_name, email, department_id, designation, hire_date) VALUES
    ('EMP1001', 'Rakesh',  'Mehra',   'rakesh.mehra@college.edu',  1, 'Professor',           '2012-07-16'),
    ('EMP1002', 'Sunita',  'Verma',   'sunita.verma@college.edu',  1, 'Associate Professor', '2015-08-01'),
    ('EMP1003', 'Arjun',   'Nair',    'arjun.nair@college.edu',    1, 'Assistant Professor', '2019-01-10'),
    ('EMP1004', 'Pooja',   'Bhatia',  'pooja.bhatia@college.edu',  3, 'Lecturer',            '2020-07-20'),
    ('EMP1005', 'Karan',   'Malhotra','karan.malhotra@college.edu',1, 'Teaching Assistant',  '2024-08-01');

-- ---------- Students (12) ----------
INSERT INTO student (roll_number, first_name, last_name, email, phone, date_of_birth, program_id, admission_year, current_semester) VALUES
    ('2501730001', 'Aarav',    'Sharma',   'aarav.sharma@student.college.edu',   '9810000001', '2007-02-11', 1, 2025, 3),
    ('2501730002', 'Ishita',   'Gupta',    'ishita.gupta@student.college.edu',   '9810000002', '2007-05-23', 1, 2025, 3),
    ('2501730003', 'Rohan',    'Singh',    'rohan.singh@student.college.edu',    '9810000003', '2006-11-02', 1, 2025, 3),
    ('2501730004', 'Meera',    'Iyer',     'meera.iyer@student.college.edu',     '9810000004', '2007-01-19', 1, 2025, 3),
    ('2501730005', 'Kabir',    'Khan',     'kabir.khan@student.college.edu',     '9810000005', '2007-08-30', 1, 2025, 3),
    ('2501730006', 'Diya',     'Patel',    'diya.patel@student.college.edu',     '9810000006', '2006-12-14', 1, 2025, 3),
    ('2501730007', 'Vivaan',   'Reddy',    'vivaan.reddy@student.college.edu',   '9810000007', '2007-03-07', 2, 2025, 3),
    ('2501730008', 'Ananya',   'Das',      'ananya.das@student.college.edu',     '9810000008', '2007-06-25', 2, 2025, 3),
    ('2501730009', 'Aditya',   'Joshi',    'aditya.joshi@student.college.edu',   '9810000009', '2006-10-09', 2, 2025, 3),
    ('2501730010', 'Saanvi',   'Kapoor',   'saanvi.kapoor@student.college.edu',  '9810000010', '2007-04-16', 2, 2025, 3),
    ('2401730011', 'Nikhil',   'Bansal',   'nikhil.bansal@student.college.edu',  '9810000011', '2006-09-21', 1, 2024, 5),
    ('2401730012', 'Tanvi',    'Chopra',   'tanvi.chopra@student.college.edu',   '9810000012', '2006-07-05', 1, 2024, 5);

-- ---------- Course catalog ----------
INSERT INTO course (course_code, title, description, department_id, credits) VALUES
    ('ETCCMS304', 'Database Management Systems',        'Relational model, SQL, normalization, transactions and indexing.', 1, 4),
    ('ETCCDA302', 'Design and Analysis of Algorithms',  'Algorithm design paradigms and complexity analysis.',              1, 4),
    ('ETCCML301', 'Introduction to Machine Learning',   'Supervised and unsupervised learning fundamentals.',               1, 3),
    ('ETCCCC303', 'Competitive Coding I',               'Problem solving with data structures and algorithms.',             1, 2),
    ('ETCCHW305', 'Nand2Tetris: Computer Systems',      'Build a computer from logic gates up to a compiler.',              1, 3),
    ('AEC006',    'Verbal Ability',                     'Reading comprehension, grammar and business communication.',       3, 2),
    ('ETCCDS201', 'Data Structures',                    'Arrays, linked lists, trees, graphs and hashing.',                 1, 4);

INSERT INTO course_prerequisite (course_id, prerequisite_course_id) VALUES
    (1, 7),   -- DBMS needs Data Structures
    (2, 7),   -- DAA needs Data Structures
    (3, 7);   -- ML needs Data Structures

-- ---------- Offerings for the current term (id 2) ----------
INSERT INTO course_offering (course_id, term_id, section_code, max_capacity, assignment_weight, quiz_weight) VALUES
    (1, 2, 'A', 60, 50, 50),
    (2, 2, 'A', 60, 60, 40),
    (3, 2, 'A', 60, 50, 50),
    (4, 2, 'A', 40, 70, 30),
    (5, 2, 'A', 60, 50, 50),
    (6, 2, 'A', 60, 40, 60);

INSERT INTO offering_instructor (offering_id, instructor_id, role) VALUES
    (1, 2, 'primary'), (1, 5, 'teaching-assistant'),
    (2, 1, 'primary'),
    (3, 3, 'primary'), (3, 2, 'co-instructor'),
    (4, 3, 'primary'),
    (5, 1, 'primary'),
    (6, 4, 'primary');

-- ---------- Past term: Data Structures (offering 7), the prerequisite everyone completed ----------
INSERT INTO course_offering (course_id, term_id, section_code, max_capacity, assignment_weight, quiz_weight) VALUES
    (7, 1, 'A', 60, 50, 50);
INSERT INTO offering_instructor (offering_id, instructor_id, role) VALUES (7, 3, 'primary');

INSERT INTO enrollment (student_id, offering_id, enrolled_on, status)
SELECT student_id, 7, '2026-01-14', 'completed' FROM student;

INSERT INTO course_result (enrollment_id, final_percentage, computed_on)
SELECT e.enrollment_id, 55 + MOD(e.student_id * 13, 40), '2026-05-30 10:00:00'
FROM enrollment e WHERE e.offering_id = 7;

-- ---------- Enrollments: every student in 4 offerings ----------
-- Students 1-6 (AI & ML): DBMS, DAA, ML, Verbal
INSERT INTO enrollment (student_id, offering_id, enrolled_on)
SELECT s.student_id, o.offering_id, '2026-08-05'
FROM student s JOIN course_offering o ON o.offering_id IN (1, 2, 3, 6)
WHERE s.student_id BETWEEN 1 AND 6;

-- Students 7-10 (Core): DBMS, DAA, Competitive Coding, Nand2Tetris
INSERT INTO enrollment (student_id, offering_id, enrolled_on)
SELECT s.student_id, o.offering_id, '2026-08-06'
FROM student s JOIN course_offering o ON o.offering_id IN (1, 2, 4, 5)
WHERE s.student_id BETWEEN 7 AND 10;

-- Students 11-12 (3rd year): ML, Competitive Coding, Verbal
INSERT INTO enrollment (student_id, offering_id, enrolled_on)
SELECT s.student_id, o.offering_id, '2026-08-06'
FROM student s JOIN course_offering o ON o.offering_id IN (3, 4, 6)
WHERE s.student_id BETWEEN 11 AND 12;

-- ---------- Modules and study material ----------
INSERT INTO module (offering_id, module_number, title) VALUES
    (1, 1, 'Relational Model and ER Design'),
    (1, 2, 'SQL: DDL, DML and Joins'),
    (1, 3, 'Normalization and Functional Dependencies'),
    (1, 4, 'Transactions, Indexing and Security'),
    (2, 1, 'Asymptotic Analysis and Recurrences'),
    (2, 2, 'Divide and Conquer, Greedy'),
    (3, 1, 'Linear and Logistic Regression'),
    (3, 2, 'Model Evaluation and Overfitting'),
    (4, 1, 'Arrays, Hashing and Two Pointers'),
    (5, 1, 'Boolean Logic and the ALU'),
    (6, 1, 'Reading Comprehension and Grammar');

INSERT INTO material (module_id, title, material_type, resource_url, uploaded_by, uploaded_on) VALUES
    (1, 'ER Modelling Slides',            'slides',   'https://lms.college.edu/dbms/er-slides.pdf',        2, '2026-08-10'),
    (1, 'Lecture 1 Recording',            'video',    'https://lms.college.edu/dbms/lec1',                 2, '2026-08-11'),
    (2, 'SQL Practice Workbook',          'pdf',      'https://lms.college.edu/dbms/sql-workbook.pdf',     2, '2026-08-24'),
    (3, 'Normalization Worked Examples',  'pdf',      'https://lms.college.edu/dbms/normalization.pdf',    2, '2026-09-07'),
    (4, 'Transactions and ACID Notes',    'notebook', 'https://lms.college.edu/dbms/transactions.ipynb',   5, '2026-10-05'),
    (5, 'Recurrence Relations Cheat Sheet','pdf',     'https://lms.college.edu/daa/recurrences.pdf',       1, '2026-08-12'),
    (6, 'Greedy Algorithms Slides',       'slides',   'https://lms.college.edu/daa/greedy.pdf',            1, '2026-08-30'),
    (7, 'Regression Colab Worksheet',     'notebook', 'https://lms.college.edu/ml/regression.ipynb',       3, '2026-08-18'),
    (9, 'Two Pointers Problem Set',       'link',     'https://lms.college.edu/cc/two-pointers',           3, '2026-08-20');

-- ---------- Class sessions: weekly for 11 weeks per offering ----------
CREATE TEMPORARY TABLE nums (n INT PRIMARY KEY);
INSERT INTO nums VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9),(10);

INSERT INTO class_session (offering_id, session_date, start_time, end_time, topic)
SELECT o.offering_id,
       DATE_ADD('2026-08-10', INTERVAL (n.n * 7 + MOD(o.offering_id, 5)) DAY),
       MAKETIME(9 + MOD(o.offering_id, 4), 0, 0),
       MAKETIME(10 + MOD(o.offering_id, 4), 0, 0),
       CONCAT('Lecture ', n.n + 1)
FROM course_offering o JOIN academic_term t ON t.term_id = o.term_id CROSS JOIN nums n
WHERE t.is_current;

DROP TEMPORARY TABLE nums;

-- ---------- Attendance (deterministic pseudo-random mix) ----------
INSERT INTO attendance (session_id, enrollment_id, status)
SELECT cs.session_id, e.enrollment_id,
       CASE
           WHEN MOD(cs.session_id * 7 + e.enrollment_id * 3, 10) < 7 THEN 'present'
           WHEN MOD(cs.session_id * 7 + e.enrollment_id * 3, 10) = 7 THEN 'late'
           WHEN MOD(cs.session_id * 7 + e.enrollment_id * 3, 10) = 8 THEN 'excused'
           ELSE 'absent'
       END
FROM class_session cs
JOIN enrollment e ON e.offering_id = cs.offering_id
WHERE cs.session_date <= '2026-10-23';

-- ---------- Assignments: two per offering ----------
INSERT INTO assignment (offering_id, title, description, max_marks, assigned_on, due_date, allow_late)
SELECT o.offering_id, 'Assignment 1', 'First graded assignment covering the early modules.',
       20, '2026-08-24 09:00:00', '2026-09-14 23:59:00', FALSE
FROM course_offering o WHERE o.term_id = 2;

INSERT INTO assignment (offering_id, title, description, max_marks, assigned_on, due_date, allow_late)
SELECT o.offering_id, 'Assignment 2', 'Second graded assignment covering the mid-term modules.',
       30, '2026-10-12 09:00:00', '2026-11-05 23:59:00', TRUE
FROM course_offering o WHERE o.term_id = 2;

-- Assignment 1: most students submitted and were graded
INSERT INTO submission (assignment_id, enrollment_id, submitted_on, content_url, marks_obtained, graded_by, graded_on, feedback)
SELECT a.assignment_id, e.enrollment_id,
       DATE_ADD(a.due_date, INTERVAL -MOD(e.enrollment_id * 5, 48) HOUR),
       CONCAT('https://lms.college.edu/submissions/a', a.assignment_id, '/e', e.enrollment_id, '.pdf'),
       ROUND(a.max_marks * (0.50 + MOD(a.assignment_id * 5 + e.enrollment_id * 11, 45) / 100), 1),
       oi.instructor_id,
       DATE_ADD(a.due_date, INTERVAL 3 DAY),
       'Graded. See rubric for breakdown.'
FROM assignment a
JOIN enrollment e          ON e.offering_id = a.offering_id
JOIN offering_instructor oi ON oi.offering_id = a.offering_id AND oi.role = 'primary'
WHERE a.title = 'Assignment 1'
  AND (MOD(a.assignment_id + e.enrollment_id, 9) <> 0 OR e.student_id = 1);

-- Assignment 2 (due in the future): some submitted, still ungraded
INSERT INTO submission (assignment_id, enrollment_id, submitted_on, content_url)
SELECT a.assignment_id, e.enrollment_id,
       DATE_ADD('2026-10-20 10:00:00', INTERVAL MOD(e.enrollment_id, 24) HOUR),
       CONCAT('https://lms.college.edu/submissions/a', a.assignment_id, '/e', e.enrollment_id, '.pdf')
FROM assignment a
JOIN enrollment e ON e.offering_id = a.offering_id
WHERE a.title = 'Assignment 2'
  AND MOD(a.assignment_id + e.enrollment_id, 3) = 0;

-- ---------- A quiz for DBMS (offering 1) ----------
INSERT INTO quiz (offering_id, title, time_limit_minutes, max_attempts, available_from, available_until) VALUES
    (1, 'Quiz 1: ER Modelling and Normalization', 20, 2, '2026-09-20 09:00:00', '2026-09-27 23:59:00'),
    (1, 'Quiz 2: SQL and Transactions',           25, 1, '2026-11-01 09:00:00', '2026-11-08 23:59:00');

INSERT INTO question (quiz_id, question_text, marks) VALUES
    (1, 'Which normal form removes transitive dependencies?', 1),
    (1, 'A weak entity set is identified by:', 1),
    (1, 'Which key uniquely identifies a row and cannot be NULL?', 1);

INSERT INTO question_option (question_id, option_text, is_correct) VALUES
    (1, 'First Normal Form',  FALSE), (1, 'Second Normal Form', FALSE),
    (1, 'Third Normal Form',  TRUE),  (1, 'Boyce-Codd Normal Form', FALSE),
    (2, 'Its own primary key alone', FALSE), (2, 'Its owner entity key plus a partial key', TRUE),
    (2, 'A foreign key only', FALSE),        (2, 'A composite attribute', FALSE),
    (3, 'Primary key', TRUE), (3, 'Foreign key', FALSE),
    (3, 'Candidate key with NULLs', FALSE), (3, 'Super key with duplicates', FALSE);

-- Quiz 2 (opens in November): questions so it does not look empty
INSERT INTO question (quiz_id, question_text, marks) VALUES
    (2, 'Which SQL clause filters groups after aggregation?', 1),
    (2, 'What does the I in ACID stand for?', 1),
    (2, 'Which index type is the default in InnoDB?', 1);

INSERT INTO question_option (question_id, option_text, is_correct) VALUES
    (4, 'WHERE', FALSE), (4, 'HAVING', TRUE), (4, 'ORDER BY', FALSE), (4, 'LIMIT', FALSE),
    (5, 'Isolation', TRUE), (5, 'Integrity', FALSE), (5, 'Indexing', FALSE), (5, 'Inheritance', FALSE),
    (6, 'Hash', FALSE), (6, 'B-tree', TRUE), (6, 'Bitmap', FALSE), (6, 'R-tree', FALSE);
