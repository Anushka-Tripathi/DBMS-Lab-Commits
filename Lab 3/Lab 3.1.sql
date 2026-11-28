-- LAB QUESTION 1: Stored Procedures for Patient Registration and Treatment
-- Write two procedures.
--
-- register_patient(p_id, p_name, p_age, p_contact)
--   Inserts one row into patient using the four given values.
--
-- enter_treatment(a_id, t_id, diag, t_date, presc_id, med, dose)
--   Inserts one row into treatment (treatment_id = t_id, appointment_id =
--   a_id, diagnosis = diag, treatment_date = t_date), then inserts one row
--   into prescription (prescription_id = presc_id, treatment_id = t_id,
--   medicine = med, dosage = dose) - both in the same call.
--
-- Then call both procedures with these values:
--
-- register_patient: p_id = 7, p_name = Neha, p_age = 38,
--                   p_contact = 9990007777
--
-- enter_treatment: a_id = 701, t_id = 802, diag = Seasonal allergy,
--                  t_date = 2026-08-01, presc_id = 902,
--                  med = Cetirizine, dose = 10mg once daily

CREATE OR REPLACE PROCEDURE register_patient(
    p_id INT, p_name VARCHAR, p_age INT, p_contact VARCHAR
)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO patient (patient_id, name, age, contact)
    VALUES (p_id, p_name, p_age, p_contact);
END;
$$;

CREATE OR REPLACE PROCEDURE enter_treatment(
    a_id INT, t_id INT, diag VARCHAR, t_date DATE,
    presc_id INT, med VARCHAR, dose VARCHAR
)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO treatment (treatment_id, appointment_id, diagnosis, treatment_date)
    VALUES (t_id, a_id, diag, t_date);

    INSERT INTO prescription (prescription_id, treatment_id, medicine, dosage)
    VALUES (presc_id, t_id, med, dose);
END;
$$;

CALL register_patient(7, 'Neha', 38, '9990007777');
CALL enter_treatment(701, 802, 'Seasonal allergy', '2026-08-01', 902, 'Cetirizine', '10mg once daily');
```[cite: 6, 7, 8]