"""E-Learning & Course Management: Flask frontend over the college LMS schema.

Roles
  admin       students, courses, offerings, enrollments, results
  instructor  own offerings, assignments, grading, attendance, results
  student     own courses, material, assignments, attendance, results

Business rules (capacity, prerequisites, deadlines, grading range, ...) live in the
database as triggers and stored procedures (phase2_routines.sql). This file only calls
them and shows their error messages.
"""
import os
from functools import wraps

import mysql.connector
from flask import (Flask, abort, flash, redirect, render_template, request,
                   session, url_for)
from werkzeug.security import check_password_hash, generate_password_hash

import db
from charts import (GRADE_COLORS, GRADE_ORDER, PALETTE, bar_chart, column_chart,
                    donut_chart, line_chart)

app = Flask(__name__)
app.secret_key = os.getenv("SECRET_KEY", "dev-only-change-me")

DEFAULT_STUDENT_PASSWORD = "learn123"

PRIMARY_INSTRUCTORS = """
    (SELECT GROUP_CONCAT(CONCAT(i.first_name, ' ', i.last_name) SEPARATOR ', ')
       FROM offering_instructor oi JOIN instructor i ON i.instructor_id = oi.instructor_id
      WHERE oi.offering_id = o.offering_id AND oi.role = 'primary')"""

STATUS_CHOICES = ("present", "late", "absent", "excused")


def grade_chart(rows):
    """rows: dicts with a 'g' (letter) and 'n' (count) key."""
    counts = {r["g"]: r["n"] for r in rows}
    return column_chart(GRADE_ORDER, [counts.get(g, 0) for g in GRADE_ORDER],
                        colors=[GRADE_COLORS[g] for g in GRADE_ORDER])


def attendance_donut(values):
    """values: attendance percentages (None = nothing recorded)."""
    good = sum(1 for v in values if v is not None and v >= 90)
    ok = sum(1 for v in values if v is not None and 75 <= v < 90)
    low = sum(1 for v in values if v is not None and v < 75)
    none = sum(1 for v in values if v is None)
    rated = good + ok + low
    return donut_chart(["90% or more", "75 to 90%", "Below 75%", "No data"], [good, ok, low, none],
                       colors=["var(--c3)", "var(--c6)", "var(--c5)", "var(--muted)"],
                       center_big=(f"{round(100 * (good + ok) / rated)}%" if rated else "-"),
                       center_small="on track")


def db_message(err):
    """Friendly text for a MySQL error (trigger messages are already readable)."""
    return getattr(err, "msg", None) or str(err)


@app.context_processor
def inject_helpers():
    def grade_class(letter):
        return {"A+": "ga", "A": "ga", "B": "gb", "C": "gc", "D": "gd", "F": "gf"}.get(letter, "")
    return {"grade_class": grade_class}


# ---------------------------------------------------------------- auth --
def role_required(*roles):
    def decorator(view):
        @wraps(view)
        def wrapper(*args, **kwargs):
            user = session.get("user")
            if not user:
                return redirect(url_for("login"))
            if user["role"] not in roles:
                abort(403)
            return view(*args, **kwargs)
        return wrapper
    return decorator


@app.route("/")
def index():
    user = session.get("user")
    if not user:
        return redirect(url_for("login"))
    return redirect(url_for({"admin": "admin_dashboard",
                             "instructor": "instructor_dashboard",
                             "student": "student_dashboard"}[user["role"]]))


@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        username = request.form.get("username", "").strip()
        password = request.form.get("password", "")
        u = db.query(
            """SELECT u.user_id, u.username, u.password_hash, u.role, u.is_active,
                      u.student_id, u.instructor_id,
                      COALESCE(CONCAT(s.first_name, ' ', s.last_name),
                               CONCAT(i.first_name, ' ', i.last_name),
                               'Administrator') AS full_name
                 FROM user_account u
                 LEFT JOIN student s    ON s.student_id = u.student_id
                 LEFT JOIN instructor i ON i.instructor_id = u.instructor_id
                WHERE u.username = %s""", (username,), one=True)
        if u and u["is_active"] and check_password_hash(u["password_hash"], password):
            session.clear()
            session["user"] = {k: u[k] for k in
                               ("user_id", "username", "role", "student_id",
                                "instructor_id", "full_name")}
            db.execute("UPDATE user_account SET last_login = NOW() WHERE user_id = %s",
                       (u["user_id"],))
            return redirect(url_for("index"))
        flash("Invalid username or password.", "error")
    return render_template("login.html")


@app.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("login"))


@app.errorhandler(403)
def forbidden(_):
    return render_template("error.html", code=403,
                           message="You do not have access to this page."), 403


@app.errorhandler(404)
def not_found(_):
    return render_template("error.html", code=404, message="Page not found."), 404


@app.errorhandler(mysql.connector.Error)
def database_error(err):
    return render_template("error.html", code=500,
                           message=f"Database error: {db_message(err)}"), 500


# --------------------------------------------------------------- admin --
@app.route("/admin")
@role_required("admin")
def admin_dashboard():
    counts = db.query(
        """SELECT (SELECT COUNT(*) FROM student WHERE status = 'active')   AS students,
                  (SELECT COUNT(*) FROM instructor WHERE is_active)        AS instructors,
                  (SELECT COUNT(*) FROM course)                            AS courses,
                  (SELECT COUNT(*) FROM course_offering o
                     JOIN academic_term t ON t.term_id = o.term_id
                    WHERE t.is_current)                                    AS offerings,
                  (SELECT COUNT(*) FROM enrollment WHERE status = 'enrolled') AS enrollments,
                  (SELECT COUNT(*) FROM submission WHERE marks_obtained IS NULL) AS ungraded""",
        one=True)
    recent = db.query(
        """SELECT e.enrollment_id, e.enrolled_on, s.roll_number,
                  CONCAT(s.first_name, ' ', s.last_name) AS student,
                  c.course_code, c.title
             FROM enrollment e
             JOIN student s ON s.student_id = e.student_id
             JOIN course_offering o ON o.offering_id = e.offering_id
             JOIN course c ON c.course_id = o.course_id
            ORDER BY e.enrollment_id DESC LIMIT 8""")
    low_attendance = db.query(
        """SELECT s.student_id, s.roll_number, CONCAT(s.first_name, ' ', s.last_name) AS student,
                  c.course_code, fn_attendance_pct(e.enrollment_id) AS pct
             FROM enrollment e
             JOIN student s ON s.student_id = e.student_id
             JOIN course_offering o ON o.offering_id = e.offering_id
             JOIN course c ON c.course_id = o.course_id
            WHERE e.status = 'enrolled'
           HAVING pct < 75
            ORDER BY pct LIMIT 8""")
    fill = db.query(
        """SELECT CONCAT(c.course_code, IF(o.section_code <> 'A', CONCAT(' · ', o.section_code), '')) AS course_code,
                  o.max_capacity, COUNT(e.enrollment_id) AS enrolled
             FROM course_offering o
             JOIN course c ON c.course_id = o.course_id
             JOIN academic_term t ON t.term_id = o.term_id
             LEFT JOIN enrollment e ON e.offering_id = o.offering_id AND e.status <> 'dropped'
            WHERE t.is_current
            GROUP BY o.offering_id, c.course_code, o.section_code, o.max_capacity
            ORDER BY c.course_code, o.section_code""")
    grades = db.query(
        """SELECT fn_letter_grade(r.final_percentage) AS g, COUNT(*) AS n
             FROM course_result r
             JOIN enrollment e ON e.enrollment_id = r.enrollment_id
             JOIN course_offering o ON o.offering_id = e.offering_id
             JOIN academic_term t ON t.term_id = o.term_id
            WHERE t.is_current GROUP BY g""")
    avg = db.query(
        """SELECT c.course_code, ROUND(AVG(r.final_percentage), 1) AS avg_pct
             FROM course_result r
             JOIN enrollment e ON e.enrollment_id = r.enrollment_id
             JOIN course_offering o ON o.offering_id = e.offering_id
             JOIN course c ON c.course_id = o.course_id
             JOIN academic_term t ON t.term_id = o.term_id
            WHERE t.is_current GROUP BY c.course_code ORDER BY c.course_code""")
    att = db.query("SELECT fn_attendance_pct(e.enrollment_id) AS pct FROM enrollment e "
                   "WHERE e.status = 'enrolled'")
    charts = {
        "fill": bar_chart([r["course_code"] for r in fill],
                          [{"name": "Seats filled", "color": "var(--c1)",
                            "values": [round(100 * r["enrolled"] / r["max_capacity"]) for r in fill]}],
                          unit="%", max_value=100,
                          notes=[f"{r['enrolled']}/{r['max_capacity']}" for r in fill]),
        "grades": grade_chart(grades),
        "avg": bar_chart([r["course_code"] for r in avg],
                         [{"name": "Average result", "color": "var(--c2)",
                           "values": [float(r["avg_pct"]) for r in avg]}],
                         unit="%", max_value=100),
        "attendance": attendance_donut([None if r["pct"] is None else float(r["pct"]) for r in att]),
    }
    return render_template("admin_dashboard.html", counts=counts, recent=recent,
                           low_attendance=low_attendance, charts=charts)


@app.route("/admin/students")
@role_required("admin")
def admin_students():
    q = request.args.get("q", "").strip()
    like = f"%{q}%"
    rows = db.query(
        """SELECT s.student_id, s.roll_number, s.first_name, s.last_name, s.email,
                  p.program_name, s.current_semester, s.status,
                  (SELECT COUNT(*) FROM enrollment e
                    WHERE e.student_id = s.student_id AND e.status = 'enrolled') AS courses
             FROM student s JOIN program p ON p.program_id = s.program_id
            WHERE %s = '' OR s.roll_number LIKE %s OR s.first_name LIKE %s
                  OR s.last_name LIKE %s OR s.email LIKE %s
            ORDER BY s.roll_number""", (q, like, like, like, like))
    return render_template("admin_students.html", students=rows, q=q)


def cgpa_for(student_id):
    return db.query(
        """SELECT ROUND(SUM(gs.grade_points * c.credits) / SUM(c.credits), 2) AS cgpa,
                  SUM(c.credits) AS credits
             FROM enrollment e
             JOIN course_offering o ON o.offering_id = e.offering_id
             JOIN course c ON c.course_id = o.course_id
             JOIN course_result r ON r.enrollment_id = e.enrollment_id
             JOIN grade_scale gs ON gs.grade_letter = fn_letter_grade(r.final_percentage)
            WHERE e.student_id = %s AND e.status IN ('completed', 'failed')""",
        (student_id,), one=True)


@app.route("/admin/students/<int:sid>")
@role_required("admin")
def admin_student_detail(sid):
    student = db.query(
        """SELECT s.*, p.program_name FROM student s
             JOIN program p ON p.program_id = s.program_id WHERE s.student_id = %s""",
        (sid,), one=True)
    if not student:
        abort(404)
    courses = db.query(
        f"""SELECT e.enrollment_id, e.status, c.course_code, c.title, c.credits, t.term_name,
                   {PRIMARY_INSTRUCTORS} AS instructor,
                   fn_attendance_pct(e.enrollment_id) AS attendance_pct,
                   fn_assignment_pct(e.enrollment_id) AS assignment_pct,
                   fn_quiz_pct(e.enrollment_id) AS quiz_pct,
                   r.final_percentage, fn_letter_grade(r.final_percentage) AS grade
              FROM enrollment e
              JOIN course_offering o ON o.offering_id = e.offering_id
              JOIN course c ON c.course_id = o.course_id
              JOIN academic_term t ON t.term_id = o.term_id
              LEFT JOIN course_result r ON r.enrollment_id = e.enrollment_id
             WHERE e.student_id = %s
             ORDER BY t.start_date DESC, c.title""", (sid,))
    return render_template("admin_student_detail.html", student=student,
                           courses=courses, cgpa=cgpa_for(sid))


@app.route("/admin/students/new", methods=["GET", "POST"])
@role_required("admin")
def admin_student_new():
    programs = db.query("SELECT program_id, program_name FROM program ORDER BY program_name")
    if request.method == "POST":
        f = request.form
        try:
            # Student row + login account: both succeed or neither does
            with db.transaction() as cur:
                cur.execute(
                    """INSERT INTO student (roll_number, first_name, last_name, email, phone,
                                            date_of_birth, program_id, admission_year, current_semester)
                       VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)""",
                    (f["roll_number"].strip(), f["first_name"].strip(), f["last_name"].strip(),
                     f["email"].strip(), f.get("phone") or None, f.get("date_of_birth") or None,
                     f["program_id"], f["admission_year"], f["current_semester"]))
                cur.execute(
                    """INSERT INTO user_account (username, password_hash, role, student_id)
                       VALUES (%s, %s, 'student', %s)""",
                    (f["roll_number"].strip(),
                     generate_password_hash(DEFAULT_STUDENT_PASSWORD), cur.lastrowid))
            flash(f"Student added. Login: {f['roll_number'].strip()} / {DEFAULT_STUDENT_PASSWORD}",
                  "success")
            return redirect(url_for("admin_students"))
        except mysql.connector.Error as err:
            flash(f"Could not add student: {db_message(err)}", "error")
    return render_template("admin_student_form.html", programs=programs, form=request.form)


@app.route("/admin/instructors")
@role_required("admin")
def admin_instructors():
    rows = db.query(
        """SELECT i.instructor_id, i.employee_code, i.first_name, i.last_name, i.email,
                  d.department_name, i.designation, i.is_active,
                  (SELECT COUNT(*) FROM offering_instructor oi WHERE oi.instructor_id = i.instructor_id) AS offerings
             FROM instructor i JOIN department d ON d.department_id = i.department_id
            ORDER BY i.employee_code""")
    return render_template("admin_instructors.html", instructors=rows)


@app.route("/admin/courses", methods=["GET", "POST"])
@role_required("admin")
def admin_courses():
    if request.method == "POST":
        f = request.form
        try:
            with db.transaction() as cur:
                cur.execute(
                    """INSERT INTO course (course_code, title, description, department_id, credits)
                       VALUES (%s, %s, %s, %s, %s)""",
                    (f["course_code"].strip().upper(), f["title"].strip(),
                     f.get("description") or None, f["department_id"], f["credits"]))
                course_id = cur.lastrowid
                for pre in f.getlist("prerequisites"):
                    cur.execute("INSERT INTO course_prerequisite (course_id, prerequisite_course_id) "
                                "VALUES (%s, %s)", (course_id, pre))
            flash("Course added to the catalog.", "success")
        except mysql.connector.Error as err:
            flash(f"Could not add course: {db_message(err)}", "error")
        return redirect(url_for("admin_courses"))
    courses = db.query(
        """SELECT c.course_id, c.course_code, c.title, c.credits, d.department_name,
                  (SELECT GROUP_CONCAT(p.course_code SEPARATOR ', ')
                     FROM course_prerequisite cp JOIN course p ON p.course_id = cp.prerequisite_course_id
                    WHERE cp.course_id = c.course_id) AS prerequisites
             FROM course c JOIN department d ON d.department_id = c.department_id
            ORDER BY c.course_code""")
    departments = db.query("SELECT department_id, department_name FROM department ORDER BY department_name")
    return render_template("admin_courses.html", courses=courses, departments=departments)


@app.route("/admin/offerings", methods=["GET", "POST"])
@role_required("admin")
def admin_offerings():
    if request.method == "POST":
        f = request.form
        try:
            with db.transaction() as cur:
                cur.execute(
                    """INSERT INTO course_offering (course_id, term_id, section_code, max_capacity,
                                                    assignment_weight, quiz_weight)
                       VALUES (%s, %s, %s, %s, %s, %s)""",
                    (f["course_id"], f["term_id"], f["section_code"].strip().upper() or "A",
                     f["max_capacity"], f["assignment_weight"], 100 - float(f["assignment_weight"])))
                cur.execute("INSERT INTO offering_instructor (offering_id, instructor_id, role) "
                            "VALUES (%s, %s, 'primary')", (cur.lastrowid, f["instructor_id"]))
            flash("Offering created.", "success")
        except (mysql.connector.Error, ValueError) as err:
            flash(f"Could not create offering: {db_message(err)}", "error")
        return redirect(url_for("admin_offerings"))
    offerings = db.query(
        f"""SELECT o.offering_id, c.course_code, c.title, t.term_name, t.is_current,
                   o.section_code, o.max_capacity,
                   (SELECT COUNT(*) FROM enrollment e
                     WHERE e.offering_id = o.offering_id AND e.status <> 'dropped') AS enrolled,
                   {PRIMARY_INSTRUCTORS} AS instructor
              FROM course_offering o
              JOIN course c ON c.course_id = o.course_id
              JOIN academic_term t ON t.term_id = o.term_id
             ORDER BY t.start_date DESC, c.course_code""")
    return render_template(
        "admin_offerings.html", offerings=offerings,
        courses=db.query("SELECT course_id, course_code, title FROM course ORDER BY course_code"),
        terms=db.query("SELECT term_id, term_name FROM academic_term ORDER BY start_date DESC"),
        instructors=db.query("SELECT instructor_id, first_name, last_name FROM instructor "
                             "WHERE is_active ORDER BY first_name"))


@app.route("/admin/offerings/<int:oid>")
@role_required("admin")
def admin_offering_detail(oid):
    offering = db.query(
        f"""SELECT o.*, c.course_code, c.title, t.term_name, t.is_current,
                   {PRIMARY_INSTRUCTORS} AS instructor
              FROM course_offering o
              JOIN course c ON c.course_id = o.course_id
              JOIN academic_term t ON t.term_id = o.term_id
             WHERE o.offering_id = %s""", (oid,), one=True)
    if not offering:
        abort(404)
    roster = db.query(
        """SELECT e.enrollment_id, e.enrolled_on, e.status, s.student_id, s.roll_number,
                  CONCAT(s.first_name, ' ', s.last_name) AS student,
                  fn_attendance_pct(e.enrollment_id) AS attendance_pct,
                  r.final_percentage, fn_letter_grade(r.final_percentage) AS grade
             FROM enrollment e JOIN student s ON s.student_id = e.student_id
             LEFT JOIN course_result r ON r.enrollment_id = e.enrollment_id
            WHERE e.offering_id = %s ORDER BY s.roll_number""", (oid,))
    available = db.query(
        """SELECT s.student_id, s.roll_number, s.first_name, s.last_name FROM student s
            WHERE s.status = 'active'
              AND s.student_id NOT IN (SELECT student_id FROM enrollment
                                        WHERE offering_id = %s AND status <> 'dropped')
            ORDER BY s.roll_number""", (oid,))
    return render_template("admin_offering_detail.html", offering=offering,
                           roster=roster, available=available)


@app.post("/admin/offerings/<int:oid>/enroll")
@role_required("admin")
def admin_enroll(oid):
    sid = request.form.get("student_id", type=int)
    if not sid:
        flash("Choose a student first.", "error")
    else:
        try:
            db.call("sp_enroll_student", (sid, oid))      # triggers check capacity, prerequisites...
            flash("Student enrolled.", "success")
        except mysql.connector.Error as err:
            flash(db_message(err), "error")
    return redirect(url_for("admin_offering_detail", oid=oid))


@app.post("/admin/enrollments/<int:eid>/drop")
@role_required("admin")
def admin_drop(eid):
    row = db.query("SELECT offering_id FROM enrollment WHERE enrollment_id = %s", (eid,), one=True)
    if not row:
        abort(404)
    try:
        db.execute("UPDATE enrollment SET status = 'dropped' WHERE enrollment_id = %s", (eid,))
        flash("Enrollment dropped.", "success")
    except mysql.connector.Error as err:
        flash(db_message(err), "error")
    return redirect(url_for("admin_offering_detail", oid=row["offering_id"]))


def run_results(offering_id, back_endpoint):
    try:
        sets = db.call("sp_calculate_offering_results", (offering_id,))
        r = sets[0][0]
        flash(f"Results calculated for {r['results_calculated']} student(s)"
              + (f"; {r['skipped_nothing_assessed']} skipped (nothing assessed yet)."
                 if r["skipped_nothing_assessed"] else "."), "success")
    except mysql.connector.Error as err:
        flash(db_message(err), "error")
    return redirect(url_for(back_endpoint, oid=offering_id))


@app.post("/admin/offerings/<int:oid>/results")
@role_required("admin")
def admin_results(oid):
    return run_results(oid, "admin_offering_detail")


# ---------------------------------------------------------- instructor --
def my_offering_or_403(oid):
    row = db.query(
        """SELECT o.*, c.course_code, c.title, t.term_name, t.is_current
             FROM course_offering o
             JOIN course c ON c.course_id = o.course_id
             JOIN academic_term t ON t.term_id = o.term_id
             JOIN offering_instructor oi ON oi.offering_id = o.offering_id
            WHERE o.offering_id = %s AND oi.instructor_id = %s""",
        (oid, session["user"]["instructor_id"]), one=True)
    if not row:
        abort(403)
    return row


@app.route("/instructor")
@role_required("instructor")
def instructor_dashboard():
    rows = db.query(
        """SELECT o.offering_id, c.course_code, c.title, t.term_name, t.is_current,
                  o.section_code, oi.role,
                  (SELECT COUNT(*) FROM enrollment e
                    WHERE e.offering_id = o.offering_id AND e.status = 'enrolled') AS students,
                  (SELECT COUNT(*) FROM submission s JOIN assignment a ON a.assignment_id = s.assignment_id
                    WHERE a.offering_id = o.offering_id AND s.marks_obtained IS NULL) AS to_grade
             FROM offering_instructor oi
             JOIN course_offering o ON o.offering_id = oi.offering_id
             JOIN course c ON c.course_id = o.course_id
             JOIN academic_term t ON t.term_id = o.term_id
            WHERE oi.instructor_id = %s
            ORDER BY t.start_date DESC, c.title""", (session["user"]["instructor_id"],))
    iid = session["user"]["instructor_id"]
    avg = db.query(
        """SELECT c.course_code, ROUND(AVG(r.final_percentage), 1) AS avg_pct
             FROM offering_instructor oi
             JOIN course_offering o ON o.offering_id = oi.offering_id
             JOIN course c ON c.course_id = o.course_id
             JOIN academic_term t ON t.term_id = o.term_id
             JOIN enrollment e ON e.offering_id = o.offering_id
             JOIN course_result r ON r.enrollment_id = e.enrollment_id
            WHERE oi.instructor_id = %s AND t.is_current
            GROUP BY c.course_code ORDER BY c.course_code""", (iid,))
    queue = db.query(
        """SELECT COALESCE(SUM(s.marks_obtained IS NOT NULL), 0) AS graded,
                  COALESCE(SUM(s.marks_obtained IS NULL), 0) AS waiting
             FROM submission s
             JOIN assignment a ON a.assignment_id = s.assignment_id
             JOIN offering_instructor oi ON oi.offering_id = a.offering_id
            WHERE oi.instructor_id = %s""", (iid,), one=True)
    charts = {
        "avg": bar_chart([r["course_code"] for r in avg],
                         [{"name": "Average result", "color": "var(--c1)",
                           "values": [float(r["avg_pct"]) for r in avg]}],
                         unit="%", max_value=100),
        "queue": donut_chart(["Graded", "Waiting for grading"],
                             [int(queue["graded"]), int(queue["waiting"])],
                             colors=["var(--c3)", "var(--c4)"],
                             center_big=int(queue["waiting"]), center_small="to grade"),
    }
    return render_template("instructor_dashboard.html", offerings=rows, charts=charts)


@app.route("/instructor/offering/<int:oid>")
@role_required("instructor")
def instructor_offering(oid):
    offering = my_offering_or_403(oid)
    assignments = db.query(
        """SELECT a.assignment_id, a.title, a.max_marks, a.due_date,
                  (SELECT COUNT(*) FROM submission s WHERE s.assignment_id = a.assignment_id) AS submitted,
                  (SELECT COUNT(*) FROM submission s WHERE s.assignment_id = a.assignment_id
                      AND s.marks_obtained IS NULL) AS ungraded
             FROM assignment a WHERE a.offering_id = %s ORDER BY a.due_date""", (oid,))
    roster = db.query(
        """SELECT s.roll_number, CONCAT(s.first_name, ' ', s.last_name) AS student, e.status,
                  fn_attendance_pct(e.enrollment_id) AS attendance_pct,
                  fn_assignment_pct(e.enrollment_id) AS assignment_pct,
                  fn_quiz_pct(e.enrollment_id) AS quiz_pct,
                  r.final_percentage, fn_letter_grade(r.final_percentage) AS grade
             FROM enrollment e JOIN student s ON s.student_id = e.student_id
             LEFT JOIN course_result r ON r.enrollment_id = e.enrollment_id
            WHERE e.offering_id = %s AND e.status <> 'dropped' ORDER BY s.roll_number""", (oid,))
    sessions = db.query(
        """SELECT cs.session_id, cs.session_date, cs.start_time, cs.end_time, cs.topic,
                  (cs.session_date > CURDATE()) AS is_future,
                  (SELECT COUNT(*) FROM attendance a WHERE a.session_id = cs.session_id) AS marked,
                  (SELECT COUNT(*) FROM enrollment e
                    WHERE e.offering_id = cs.offering_id AND e.status = 'enrolled') AS total
             FROM class_session cs WHERE cs.offering_id = %s
            ORDER BY cs.session_date DESC, cs.start_time DESC""", (oid,))
    trend = db.query(
        """SELECT cs.session_date,
                  ROUND(100 * SUM(a.status IN ('present','late')) / NULLIF(SUM(a.status <> 'excused'), 0), 1) AS pct
             FROM class_session cs JOIN attendance a ON a.session_id = cs.session_id
            WHERE cs.offering_id = %s GROUP BY cs.session_id, cs.session_date
            ORDER BY cs.session_date""", (oid,))
    counts = {}
    for r in roster:
        if r["grade"]:
            counts[r["grade"]] = counts.get(r["grade"], 0) + 1
    charts = {
        "grades": grade_chart([{"g": g, "n": n} for g, n in counts.items()]),
        "trend": line_chart([t["session_date"].strftime("%d %b") for t in trend],
                            [None if t["pct"] is None else float(t["pct"]) for t in trend]),
    }
    return render_template("instructor_offering.html", offering=offering,
                           assignments=assignments, roster=roster, sessions=sessions,
                           charts=charts)


@app.post("/instructor/offering/<int:oid>/results")
@role_required("instructor")
def instructor_results(oid):
    my_offering_or_403(oid)
    return run_results(oid, "instructor_offering")


@app.post("/instructor/offering/<int:oid>/assignments")
@role_required("instructor")
def instructor_add_assignment(oid):
    my_offering_or_403(oid)
    f = request.form
    try:
        db.execute(
            """INSERT INTO assignment (offering_id, title, description, max_marks, due_date, allow_late)
               VALUES (%s, %s, %s, %s, %s, %s)""",
            (oid, f["title"].strip(), f.get("description") or None, f["max_marks"],
             f["due_date"].replace("T", " "), 1 if f.get("allow_late") else 0))
        flash("Assignment posted.", "success")
    except mysql.connector.Error as err:
        flash(f"Could not post assignment: {db_message(err)}", "error")
    return redirect(url_for("instructor_offering", oid=oid))


@app.post("/instructor/offering/<int:oid>/sessions")
@role_required("instructor")
def instructor_add_session(oid):
    my_offering_or_403(oid)
    f = request.form
    try:
        db.execute(
            """INSERT INTO class_session (offering_id, session_date, start_time, end_time, topic)
               VALUES (%s, %s, %s, %s, %s)""",
            (oid, f["session_date"], f["start_time"], f["end_time"], f.get("topic") or None))
        flash("Class session added.", "success")
    except mysql.connector.Error as err:
        flash(f"Could not add session: {db_message(err)}", "error")
    return redirect(url_for("instructor_offering", oid=oid))


@app.route("/instructor/session/<int:cid>/attendance", methods=["GET", "POST"])
@role_required("instructor")
def instructor_attendance(cid):
    cs = db.query("SELECT * FROM class_session WHERE session_id = %s", (cid,), one=True)
    if not cs:
        abort(404)
    offering = my_offering_or_403(cs["offering_id"])
    students = db.query(
        """SELECT e.enrollment_id, s.roll_number, CONCAT(s.first_name, ' ', s.last_name) AS student,
                  a.status
             FROM enrollment e JOIN student s ON s.student_id = e.student_id
             LEFT JOIN attendance a ON a.enrollment_id = e.enrollment_id AND a.session_id = %s
            WHERE e.offering_id = %s AND e.status = 'enrolled' ORDER BY s.roll_number""",
        (cid, cs["offering_id"]))
    if request.method == "POST":
        try:
            with db.transaction() as cur:          # all rows saved, or none
                for s in students:
                    status = request.form.get(f"status_{s['enrollment_id']}")
                    if status not in STATUS_CHOICES:
                        continue
                    cur.execute(
                        """INSERT INTO attendance (session_id, enrollment_id, status)
                           VALUES (%s, %s, %s)
                           ON DUPLICATE KEY UPDATE status = %s""",
                        (cid, s["enrollment_id"], status, status))
            flash("Attendance saved.", "success")
            return redirect(url_for("instructor_offering", oid=cs["offering_id"]))
        except mysql.connector.Error as err:
            flash(db_message(err), "error")
    return render_template("instructor_attendance.html", cs=cs, offering=offering,
                           students=students, choices=STATUS_CHOICES)


@app.route("/instructor/assignment/<int:aid>")
@role_required("instructor")
def instructor_grade(aid):
    assignment = db.query("SELECT * FROM assignment WHERE assignment_id = %s", (aid,), one=True)
    if not assignment:
        abort(404)
    offering = my_offering_or_403(assignment["offering_id"])
    rows = db.query(
        """SELECT e.enrollment_id, s.roll_number, CONCAT(s.first_name, ' ', s.last_name) AS student,
                  sub.submission_id, sub.submitted_on, sub.content_url,
                  sub.marks_obtained, sub.feedback
             FROM enrollment e
             JOIN student s ON s.student_id = e.student_id
             LEFT JOIN submission sub ON sub.enrollment_id = e.enrollment_id AND sub.assignment_id = %s
            WHERE e.offering_id = %s AND e.status <> 'dropped'
            ORDER BY (sub.submission_id IS NULL), (sub.marks_obtained IS NOT NULL), s.roll_number""",
        (aid, assignment["offering_id"]))
    return render_template("instructor_grade.html", assignment=assignment,
                           offering=offering, rows=rows)


@app.post("/instructor/submission/<int:sid>/grade")
@role_required("instructor")
def instructor_grade_submit(sid):
    sub = db.query(
        """SELECT s.submission_id, a.assignment_id, a.offering_id
             FROM submission s JOIN assignment a ON a.assignment_id = s.assignment_id
            WHERE s.submission_id = %s""", (sid,), one=True)
    if not sub:
        abort(404)
    my_offering_or_403(sub["offering_id"])
    try:
        marks = float(request.form["marks"])
        db.call("sp_grade_submission",                 # triggers validate range and grader
                (sid, marks, request.form.get("feedback") or None,
                 session["user"]["instructor_id"]))
        flash("Grade saved.", "success")
    except (ValueError, KeyError):
        flash("Enter valid marks.", "error")
    except mysql.connector.Error as err:
        flash(db_message(err), "error")
    return redirect(url_for("instructor_grade", aid=sub["assignment_id"]))


# ------------------------------------------------------------- student --
def my_enrollment_or_403(eid):
    row = db.query(
        f"""SELECT e.enrollment_id, e.offering_id, e.status, c.course_code, c.title, c.credits,
                   t.term_name, o.section_code, o.assignment_weight, o.quiz_weight,
                   {PRIMARY_INSTRUCTORS} AS instructor
              FROM enrollment e
              JOIN course_offering o ON o.offering_id = e.offering_id
              JOIN course c ON c.course_id = o.course_id
              JOIN academic_term t ON t.term_id = o.term_id
             WHERE e.enrollment_id = %s AND e.student_id = %s""",
        (eid, session["user"]["student_id"]), one=True)
    if not row:
        abort(403)
    return row


@app.route("/student")
@role_required("student")
def student_dashboard():
    sid = session["user"]["student_id"]
    rows = db.query(
        f"""SELECT e.enrollment_id, e.status, c.course_code, c.title, c.credits,
                   t.term_name, o.section_code,
                   {PRIMARY_INSTRUCTORS} AS instructor,
                   fn_attendance_pct(e.enrollment_id) AS attendance_pct,
                   (SELECT COUNT(*) FROM assignment x WHERE x.offering_id = o.offering_id) AS total_assignments,
                   (SELECT COUNT(*) FROM submission s WHERE s.enrollment_id = e.enrollment_id) AS submitted,
                   r.final_percentage, fn_letter_grade(r.final_percentage) AS grade
              FROM enrollment e
              JOIN course_offering o ON o.offering_id = e.offering_id
              JOIN course c ON c.course_id = o.course_id
              JOIN academic_term t ON t.term_id = o.term_id
              LEFT JOIN course_result r ON r.enrollment_id = e.enrollment_id
             WHERE e.student_id = %s AND e.status <> 'dropped'
             ORDER BY t.start_date DESC, c.title""", (sid,))
    current = [r for r in rows if r["status"] == "enrolled"]
    history = [r for r in rows if r["status"] in ("completed", "failed")]
    profile = db.query(
        """SELECT s.roll_number, p.program_name, s.current_semester
             FROM student s JOIN program p ON p.program_id = s.program_id
            WHERE s.student_id = %s""", (sid,), one=True)
    upcoming = db.query(
        """SELECT a.assignment_id, a.title, a.due_date, c.course_code, e.enrollment_id
             FROM enrollment e
             JOIN assignment a ON a.offering_id = e.offering_id
             JOIN course_offering o ON o.offering_id = e.offering_id
             JOIN course c ON c.course_id = o.course_id
             LEFT JOIN submission s ON s.assignment_id = a.assignment_id AND s.enrollment_id = e.enrollment_id
            WHERE e.student_id = %s AND e.status = 'enrolled'
              AND s.submission_id IS NULL AND a.due_date >= NOW()
            ORDER BY a.due_date LIMIT 5""", (sid,))
    atts = [c["attendance_pct"] for c in current if c["attendance_pct"] is not None]
    summary = {
        "courses": len(current),
        "attendance": round(sum(atts) / len(atts), 1) if atts else None,
        "pending": len(upcoming),
        "cgpa": cgpa_for(sid),
    }
    charts = {}
    if current:
        charts["standing"] = bar_chart(
            [c["course_code"] for c in current],
            [{"name": "Attendance", "color": "var(--c3)",
              "values": [float(c["attendance_pct"] or 0) for c in current]},
             {"name": "Current standing", "color": "var(--c1)",
              "values": [float(c["final_percentage"] or 0) for c in current]}],
            unit="%", max_value=100)
        done = sum(c["submitted"] for c in current)
        total = sum(c["total_assignments"] for c in current)
        charts["assignments"] = donut_chart(["Submitted", "Still to submit"], [done, max(total - done, 0)],
                                            colors=["var(--c3)", "var(--c4)"],
                                            center_big=f"{done}/{total}", center_small="submitted")
    return render_template("student_dashboard.html", current=current, history=history,
                           profile=profile, upcoming=upcoming, summary=summary, charts=charts)


@app.route("/student/course/<int:eid>")
@role_required("student")
def student_course(eid):
    enr = my_enrollment_or_403(eid)
    oid = enr["offering_id"]
    material_rows = db.query(
        """SELECT mo.module_number, mo.title AS module_title,
                  ma.title, ma.material_type, ma.resource_url
             FROM module mo LEFT JOIN material ma ON ma.module_id = mo.module_id
            WHERE mo.offering_id = %s ORDER BY mo.module_number, ma.material_id""", (oid,))
    modules = {}
    for r in material_rows:
        m = modules.setdefault(r["module_number"], {"title": r["module_title"], "items": []})
        if r["title"]:
            m["items"].append(r)
    assignments = db.query(
        """SELECT a.assignment_id, a.title, a.description, a.max_marks, a.due_date, a.allow_late,
                  s.submission_id, s.submitted_on, s.marks_obtained, s.feedback,
                  (a.due_date < NOW()) AS past_due
             FROM assignment a
             LEFT JOIN submission s ON s.assignment_id = a.assignment_id AND s.enrollment_id = %s
            WHERE a.offering_id = %s ORDER BY a.due_date""", (eid, oid))
    sessions = db.query(
        """SELECT cs.session_date, cs.topic, a.status
             FROM class_session cs
             LEFT JOIN attendance a ON a.session_id = cs.session_id AND a.enrollment_id = %s
            WHERE cs.offering_id = %s AND cs.session_date <= CURDATE()
            ORDER BY cs.session_date DESC""", (eid, oid))
    att = {k: 0 for k in STATUS_CHOICES}
    for s in sessions:
        if s["status"] in att:
            att[s["status"]] += 1
    quizzes = db.query(
        """SELECT q.quiz_id, q.title, q.time_limit_minutes, q.max_attempts,
                  q.available_from, q.available_until,
                  (SELECT COUNT(*) FROM question WHERE quiz_id = q.quiz_id) AS questions,
                  (SELECT COUNT(*) FROM quiz_attempt qa
                    WHERE qa.quiz_id = q.quiz_id AND qa.enrollment_id = %s) AS attempts,
                  (SELECT MAX(qa.score) FROM quiz_attempt qa
                    WHERE qa.quiz_id = q.quiz_id AND qa.enrollment_id = %s) AS best_score,
                  (SELECT SUM(marks) FROM question WHERE quiz_id = q.quiz_id) AS total_marks
             FROM quiz q WHERE q.offering_id = %s ORDER BY q.available_from""", (eid, eid, oid))
    result = db.query(
        """SELECT fn_assignment_pct(%s) AS assignment_pct, fn_quiz_pct(%s) AS quiz_pct,
                  fn_attendance_pct(%s) AS attendance_pct,
                  fn_attendance_deduction(fn_attendance_pct(%s)) AS deduction,
                  r.final_percentage, fn_letter_grade(r.final_percentage) AS grade, r.computed_on
             FROM (SELECT 1) x LEFT JOIN course_result r ON r.enrollment_id = %s""",
        (eid, eid, eid, eid, eid), one=True)
    charts = {
        "attendance": donut_chart(["Present", "Late", "Absent", "Excused"],
                                  [att["present"], att["late"], att["absent"], att["excused"]],
                                  colors=["var(--c3)", "var(--c4)", "var(--c5)", "var(--c6)"],
                                  center_big=(f"{result['attendance_pct']}%"
                                              if result["attendance_pct"] is not None else "-"),
                                  center_small="attendance"),
        "parts": bar_chart(["Assignments", "Quizzes", "Attendance"],
                           [{"name": "Score", "color": "var(--c1)",
                             "values": [float(result[k] or 0) for k in
                                        ("assignment_pct", "quiz_pct", "attendance_pct")]}],
                           unit="%", max_value=100,
                           notes=[(f"{result[k]}%" if result[k] is not None else "-") for k in
                                  ("assignment_pct", "quiz_pct", "attendance_pct")]),
    }
    return render_template("student_course.html", enr=enr, modules=modules,
                           assignments=assignments, sessions=sessions, att=att,
                           quizzes=quizzes, result=result, charts=charts)


@app.post("/student/course/<int:eid>/submit/<int:aid>")
@role_required("student")
def student_submit(eid, aid):
    enr = my_enrollment_or_403(eid)
    if not db.query("SELECT 1 AS ok FROM assignment WHERE assignment_id = %s AND offering_id = %s",
                    (aid, enr["offering_id"]), one=True):
        abort(404)
    url = request.form.get("content_url", "").strip()
    if not url:
        flash("Please paste a link to your work.", "error")
    else:
        try:
            # deadline, enrollment status and course match are enforced by trg_submission_bi
            db.execute("INSERT INTO submission (assignment_id, enrollment_id, content_url) "
                       "VALUES (%s, %s, %s)", (aid, eid, url))
            flash("Submitted successfully.", "success")
        except mysql.connector.IntegrityError:
            flash("You have already submitted this assignment.", "error")
        except mysql.connector.Error as err:
            flash(db_message(err), "error")
    return redirect(url_for("student_course", eid=eid))


if __name__ == "__main__":
    app.run(debug=True)
