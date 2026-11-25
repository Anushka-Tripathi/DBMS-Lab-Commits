"""Thin MySQL helper. Every query in this project is plain SQL, no ORM."""
import os
from contextlib import contextmanager

import mysql.connector

CONFIG = dict(
    host=os.getenv("DB_HOST", "localhost"),
    port=int(os.getenv("DB_PORT", "3306")),
    user=os.getenv("DB_USER", "root"),
    password=os.getenv("DB_PASSWORD", ""),
    database=os.getenv("DB_NAME", "elearning_db"),
)


def get_conn():
    return mysql.connector.connect(**CONFIG)


def query(sql, params=(), one=False):
    """Run a SELECT. Returns a list of dicts, or a single dict/None when one=True."""
    conn = get_conn()
    try:
        cur = conn.cursor(dictionary=True)
        cur.execute(sql, params)
        rows = cur.fetchall()
        if one:
            return rows[0] if rows else None
        return rows
    finally:
        conn.close()


def execute(sql, params=()):
    """Run a single INSERT/UPDATE/DELETE and commit. Returns lastrowid."""
    conn = get_conn()
    try:
        cur = conn.cursor()
        cur.execute(sql, params)
        conn.commit()
        return cur.lastrowid
    finally:
        conn.close()


def call(proc, args=()):
    """Call a stored procedure. Returns its result sets (a list of row lists) and commits."""
    conn = get_conn()
    try:
        cur = conn.cursor(dictionary=True)
        cur.callproc(proc, args)
        sets = [r.fetchall() for r in cur.stored_results()]
        conn.commit()
        return sets
    finally:
        conn.close()


@contextmanager
def transaction():
    """Several statements, one COMMIT. Any error triggers ROLLBACK."""
    conn = get_conn()
    cur = conn.cursor(dictionary=True)
    try:
        yield cur
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()
