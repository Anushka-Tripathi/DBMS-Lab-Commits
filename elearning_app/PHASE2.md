# Phase 2: Procedural implementation

The Phase 1 schema (`schema.sql`, 24 tables) is **unchanged**. All Phase 2 code lives in
`phase2_routines.sql`; sample activity is in `phase2_data.sql`; tests are in `phase2_tests.sql`.

## Load order (MySQL Workbench: open each file, press the lightning bolt)

1. `schema.sql`  2. `seed.sql`  3. `phase2_routines.sql`  4. `phase2_data.sql`  5. `phase2_tests.sql` (optional)

## Grading rule (this domain's "salary calculation + deduction")

```
assignment %  = marks earned / marks available over assignments already past their due date
                (missing submission = 0, submitted-but-ungraded is left out for now)
quiz %        = best attempt per quiz / quiz marks, over quizzes that have closed
base %        = (assignment % x assignment_weight + quiz % x quiz_weight) / (weights of assessed parts)
deduction     = 2 marks for every started 5% of attendance below 75%, capped at 10
final %       = max(0, base % - deduction)           -> stored in course_result
grade         = looked up in grade_scale (A+ 90, A 80, B 70, C 60, D 50, F 0)
```
Attendance excludes `excused` sessions. A part with nothing assessed yet is left out and the other weight is rescaled.

## Stored functions (5)

| Function | Returns |
|---|---|
| `fn_attendance_pct(enrollment_id)` | attendance %, excused sessions ignored |
| `fn_assignment_pct(enrollment_id)` | assignment % (past-due assignments) |
| `fn_quiz_pct(enrollment_id)` | quiz % (closed quizzes, best attempt) |
| `fn_attendance_deduction(pct)` | deduction in marks (0 to 10) |
| `fn_letter_grade(pct)` | letter from `grade_scale` |

## Stored procedures (7)

| Procedure | Purpose |
|---|---|
| `sp_calculate_result(enrollment_id, show)` | final result for one enrollment, upserts `course_result` |
| `sp_calculate_offering_results(offering_id)` | cursor loop over an offering; skips students with nothing assessed |
| `sp_enroll_student(student_id, offering_id)` | transactional enrol / re-activate; locks the offering row |
| `sp_grade_submission(submission_id, marks, feedback, instructor_id)` | grade a submission (triggers validate) |
| `sp_score_quiz_attempt(attempt_id)` / `sp_score_quiz(quiz_id)` | score attempts from the answers given |
| `sp_finalize_offering(offering_id)` | end of term: compute results, mark completed / failed, all-or-nothing |

## Triggers (12)

| Table | Trigger | Rejects |
|---|---|---|
| enrollment | `trg_enrollment_bi` | inactive student, full offering, same course twice in a term, missing prerequisite |
| enrollment | `trg_enrollment_bu` | changing a finalised enrollment, changing student/offering, re-enrol into a full offering |
| submission | `trg_submission_bi` | inactive enrolment, assignment from another course, late without `allow_late`, marks over max |
| submission | `trg_submission_bu` | marks over max, missing grader, grader not teaching the course; stamps `graded_on` |
| attendance | `trg_attendance_bi` | student not in the course, inactive enrolment, future session |
| quiz_attempt | `trg_quiz_attempt_bi` | quiz not open, wrong course, attempts over max; sets `attempt_no` sequentially |
| quiz_answer | `trg_quiz_answer_bi` | question not in quiz, option not of the question, already-scored attempt |
| question_option | `trg_option_bi` / `trg_option_bu` | a second correct option on one question |
| offering_instructor | `trg_offering_instructor_bi` / `_bu` | inactive instructor, second primary instructor |
| course_prerequisite | `trg_prerequisite_bi` | circular prerequisite (A needs B and B needs A) |

Table-level `CHECK` constraints from Phase 1 add: non-negative marks, a course cannot require itself, valid dates, weights sum to 100.

## Sample data (3 months)

12 students and 5 instructors; 6 current offerings; weekly class sessions Aug to Oct 2026 with ~500 attendance records;
2 assignments per offering with graded submissions; a DBMS quiz with 11 attempts and 33 answers; a past-term
Data Structures offering with completed enrolments (the prerequisite history). Quiz attempts and results are
loaded through the triggers and procedures, not by direct inserts.

## Tests: `CALL sp_run_phase2_tests();`

35 cases: 22 invalid or boundary entries that must be rejected, 4 valid entries that must be accepted, 7 function checks,
and 2 hand-computed results (15/20 -> 75.00; with 70% attendance -> 73.00). Everything runs in one transaction that is
rolled back, so the data is untouched. Last run: **35 passed, 0 failed**.
