"""Creates login accounts for the seeded people (run once after seed.sql).

  admin           / admin123
  instructors     / employee code (e.g. EMP1002) / teach123
  students        / roll number (e.g. 2501730001) / learn123
"""
from werkzeug.security import generate_password_hash

import db

conn = db.get_conn()
cur = conn.cursor()

cur.execute("SELECT username FROM user_account")
existing = {r[0] for r in cur.fetchall()}


def add(username, password, role, student_id=None, instructor_id=None):
    if username in existing:
        return 0
    cur.execute(
        "INSERT INTO user_account (username, password_hash, role, student_id, instructor_id) "
        "VALUES (%s, %s, %s, %s, %s)",
        (username, generate_password_hash(password), role, student_id, instructor_id),
    )
    return 1


created = add("admin", "admin123", "admin")

cur.execute("SELECT instructor_id, employee_code FROM instructor")
for iid, code in cur.fetchall():
    created += add(code, "teach123", "instructor", instructor_id=iid)

cur.execute("SELECT student_id, roll_number FROM student")
for sid, roll in cur.fetchall():
    created += add(roll, "learn123", "student", student_id=sid)

conn.commit()
conn.close()
print(f"Created {created} accounts.")
