-- LAB QUESTION 1: Cursor-Based Doctor Appointment Summary
-- Write a function doctor_appointment_summary(doc_id) that uses an explicit
-- cursor to loop through every appointment belonging to the given doctor, and
-- returns one row per appointment with these columns:
--   patient_name - the patient's name
--   appt_date    - the appointment date
--   appt_status  - the appointment status
--   diagnosis    - the diagnosis from treatment, if one exists; otherwise the
--                  text 'Not yet treated'
-- You must use an actual CURSOR with OPEN / FETCH / a loop / CLOSE inside the
-- function body - do not just write a plain SELECT and skip the cursor.
-- Test it by calling:
-- SELECT * FROM doctor_appointment_summary(2) ORDER BY appt_date;

CREATE OR REPLACE FUNCTION doctor_appointment_summary (doc_id INT)
RETURNS TABLE (
    patient_name VARCHAR,
    appt_date DATE,
    appt_status VARCHAR,
    diagnosis VARCHAR
)
LANGUAGE plpgsql
AS $$
DECLARE
    cur CURSOR FOR
        SELECT p.name, a.appointment_date, a.status, t.diagnosis
        FROM appointment a
        JOIN patient p ON a.patient_id = p.patient_id
        LEFT JOIN treatment t ON a.appointment_id = t.appointment_id
        WHERE a.doctor_id = doc_id;
    r RECORD;
BEGIN
    OPEN cur;
    LOOP
        FETCH cur INTO r;
        EXIT WHEN NOT FOUND;

        patient_name := r.name;
        appt_date := r.appointment_date;
        appt_status := r.status;

        IF r.diagnosis IS NOT NULL THEN
            diagnosis := r.diagnosis;
        ELSE
            diagnosis := 'Not yet treated';
        END IF;

        RETURN NEXT;
    END LOOP;
    CLOSE cur;
END;
$$;


-- LAB QUESTION 2: Status Change Audit Trigger
-- Write a trigger (and the function it calls) that fires after an UPDATE on
-- appointment, and - only when the status column actually changes - inserts
-- one row into appointment_log recording the appointment_id, the old status
-- and the new status.
-- You do not need to create appointment_log yourself; it already exists,
-- empty, with columns log_id, appointment_id, old_status, new_status,
-- changed_at.
-- Name your trigger function log_status_change and your trigger
-- trg_status_audit.

CREATE OR REPLACE FUNCTION log_status_change()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF OLD.status IS DISTINCT FROM NEW.status THEN
        INSERT INTO appointment_log (appointment_id, old_status, new_status, changed_at)
        VALUES (NEW.appointment_id, OLD.status, NEW.status, '2026-01-01 00:00:00'::timestamp);
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_status_audit
AFTER UPDATE ON appointment
FOR EACH ROW
EXECUTE FUNCTION log_status_change();