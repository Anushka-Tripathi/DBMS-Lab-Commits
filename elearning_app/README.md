# EduHub LMS: E-Learning & Course Management Database

DBMS capstone. Phase 1 (schema + ER diagram) with a working role-based frontend.
Stack: MySQL 8 · Python Flask · plain HTML/CSS (no ORM, every query is raw SQL).

## Setup (Windows, MySQL Workbench)

1. **Install packages**
   ```
   pip install -r requirements.txt
   ```
2. **Create the database.** In Workbench: *File → Open SQL Script* and run these in order
   (lightning-bolt button each time):
   `schema.sql` → `seed.sql` → `phase2_routines.sql` → `phase2_data.sql`
   (optional: `phase2_tests.sql`, expect 35 passed, 0 failed).
3. **Tell the app your MySQL password.** In PowerShell, in this folder:
   ```
   $env:DB_PASSWORD = "your-mysql-root-password"
   ```
   (Optional extras: `DB_USER`, `DB_HOST`, `DB_PORT`, `DB_NAME`; defaults are root / localhost / 3306 / elearning_db.)
4. **Create the logins** (passwords are stored hashed):
   ```
   python create_users.py
   ```
5. **Run**
   ```
   python app.py
   ```
   Open http://127.0.0.1:5000

## Demo accounts

| Role       | Username     | Password   |
|------------|--------------|------------|
| Admin      | `admin`      | `admin123` |
| Instructor | `EMP1002`    | `teach123` |
| Student    | `2501730001` | `learn123` |

Every seeded instructor logs in with their employee code (EMP1001 to EMP1005) and every
student with their roll number (2501730001 to 2501730010, 2401730011, 2401730012).

## What each role can do

- **Admin**: dashboard, search and add students (student + login in one transaction), student
  detail with CGPA and history, courses with prerequisites, offerings, enroll and drop students,
  calculate results.
- **Instructor**: only their own offerings; post assignments, grade submissions, add class
  sessions, mark attendance, calculate results, see the roster with final grades.
- **Student**: only their own courses; study material by module, submit assignments, see
  grades, quizzes, attendance, a result breakdown per course and CGPA.

## Files

| File | Purpose |
|------|---------|
| `schema.sql` | Phase 1 DDL, 24 tables, 3NF |
| `seed.sql` | Base sample data (12 students, 5 instructors, 6 offerings, attendance, assignments, a quiz) |
| `phase2_routines.sql` | Phase 2: 5 functions, 7 procedures, 12 triggers |
| `phase2_data.sql` | Phase 2: quiz attempts and results loaded through the triggers and procedures |
| `phase2_tests.sql` | Phase 2: 35-case test suite (`CALL sp_run_phase2_tests();`) |
| `PHASE2.md` | Phase 2 documentation: grading rule, routines, triggers, tests |
| `create_users.py` | Creates hashed login accounts |
| `db.py` | MySQL helper (query, call procedure, transaction) |
| `charts.py` | Server-side SVG charts (bar, column, donut, line), no JavaScript library needed |
| `app.py` | Flask routes for all three roles |
| `templates/`, `static/` | Pages and stylesheet |

## Look and feel

Light and dark themes (toggle in the top bar; your choice is remembered in the browser),
gradient hero banners, icon stat tiles, coloured course cards and charts on every dashboard.
If the page looks unchanged after an update, press **Ctrl+F5** to reload the stylesheet.

## Database logic

Capacity, prerequisites, deadlines, grading range, attendance rules and result calculation
live in MySQL (see `PHASE2.md`). The app calls the procedures and shows the trigger messages.

## Not built yet (later phases)

Index/EXPLAIN reports (Phase 3), MySQL-level roles and transaction/test documentation
(Phase 4), quiz-taking UI and the final report (Phase 5).
