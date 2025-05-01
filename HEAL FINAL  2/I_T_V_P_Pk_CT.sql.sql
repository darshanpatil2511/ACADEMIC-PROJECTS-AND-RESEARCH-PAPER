
------------------------------------------------------------------
--                      INDEXES
------------------------------------------------------------------
-- Drop Queries to drop the indexes 
DROP INDEX ADMIN_USER.idx_appointment_date;
DROP INDEX ADMIN_USER.idx_visit_patient;
DROP INDEX ADMIN_USER.idx_visit_doctor;
DROP INDEX ADMIN_USER.idx_patient_email_phone;
DROP INDEX ADMIN_USER.idx_medicalrecord_patient;


-- Create an index on the Appointment table's AppointmentDate column
CREATE INDEX ADMIN_USER.idx_appointment_date
  ON ADMIN_USER.Appointment(AppointmentDate);
  
-- Create indexes on the Visit table's foreign key columns for faster joins
CREATE INDEX ADMIN_USER.idx_visit_patient
  ON ADMIN_USER.Visit(PatientID);

-- Create an index on the Visit table's DoctorID column for faster joins
CREATE INDEX ADMIN_USER.idx_visit_doctor
  ON ADMIN_USER.Visit(DoctorID);


-- Create a composite index on the Patient table's Email and PhoneNumber columns
-- for faster lookups when querying by both email and phone number together.
CREATE INDEX ADMIN_USER.idx_patient_email_phone
  ON ADMIN_USER.Patient(Email, PhoneNumber);

-- Create an index on the MedicalRecord table's PatientID column for efficient joins
CREATE INDEX ADMIN_USER.idx_medicalrecord_patient
  ON ADMIN_USER.MedicalRecord(PatientID);




----------------------------------------------------------
--    TRIGGERS
----------------------------------------------------------
-- This trigger checks, before any INSERT or UPDATE on the Appointment table, whether the new AppointmentDate is earlier than today (using TRUNC(SYSDATE) to ignore the time component)

CREATE OR REPLACE TRIGGER ADMIN_USER.trg_appointment_date_check
BEFORE INSERT OR UPDATE ON ADMIN_USER.Appointment
FOR EACH ROW
BEGIN
    IF :NEW.AppointmentDate < TRUNC(SYSDATE) THEN
       RAISE_APPLICATION_ERROR(-20001, 'Cannot schedule appointment in the past.');
    END IF;
END;
/

-- Auto-update the "UpdatedAt" Column on the Users Table

CREATE OR REPLACE TRIGGER ADMIN_USER.trg_update_user_timestamp
BEFORE UPDATE ON ADMIN_USER.Users
FOR EACH ROW
BEGIN
    :NEW.UpdatedAt := SYSDATE;
END;
/

--Prevent Deletion of Doctors if They Have Associated Appointments
CREATE OR REPLACE TRIGGER ADMIN_USER.trg_prevent_doctor_delete
BEFORE DELETE ON ADMIN_USER.Doctor
FOR EACH ROW
DECLARE
    v_count NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_count
      FROM ADMIN_USER.Appointment
     WHERE DoctorID = :OLD.DoctorID;
    
    IF v_count > 0 THEN
       RAISE_APPLICATION_ERROR(-20002, 'Cannot delete doctor: appointments exist.');
    END IF;
END;
/



------------------------------------------------------------
-- [VIEW CREATION SECTION] - Run as ADMIN_USER
------------------------------------------------------------


SET SERVEROUTPUT ON;


------------------------------------------------------------------------
-- 1) CREATE OR REPLACE VIEW: Doctor_Availability
--    Allowed: ADMIN_USER, DOC_USER, BILL_USER
--    Others get "Access Denied."
------------------------------------------------------------------------
BEGIN
    EXECUTE IMMEDIATE '
        CREATE OR REPLACE VIEW ADMIN_USER.Doctor_Availability AS
        SELECT 
            DoctorID,
            FirstName,
            LastName,
            Specialization,
            Availability
        FROM ADMIN_USER.Doctor
        WHERE UPPER(SYS_CONTEXT(''USERENV'', ''SESSION_USER'')) 
              IN (''ADMIN_USER'', ''DOC_USER'', ''BILL_USER'')

        UNION ALL

        SELECT 
            ''Access Denied'' AS DoctorID,
            ''Access Denied'' AS FirstName,
            ''Access Denied'' AS LastName,
            ''Access Denied'' AS Specialization,
            ''Access Denied'' AS Availability
        FROM DUAL
        WHERE UPPER(SYS_CONTEXT(''USERENV'', ''SESSION_USER'')) 
              NOT IN (''ADMIN_USER'', ''DOC_USER'', ''BILL_USER'')
    ';
    DBMS_OUTPUT.PUT_LINE('View ADMIN_USER.Doctor_Availability created.');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error creating ADMIN_USER.Doctor_Availability: ' || SQLERRM);
END;
/

-- Grant SELECT on Doctor_Availability to DOC_USER and BILL_USER
BEGIN
    EXECUTE IMMEDIATE 'GRANT SELECT ON ADMIN_USER.Doctor_Availability TO DOC_USER';
    DBMS_OUTPUT.PUT_LINE('Granted SELECT on Doctor_Availability to DOC_USER');

    EXECUTE IMMEDIATE 'GRANT SELECT ON ADMIN_USER.Doctor_Availability TO BILL_USER';
    DBMS_OUTPUT.PUT_LINE('Granted SELECT on Doctor_Availability to BILL_USER');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error granting SELECT on Doctor_Availability: ' || SQLERRM);
END;
/

------------------------------------------------------------------------
-- 2) CREATE OR REPLACE VIEW: Patient_Visit_Summary
--    Allowed: ADMIN_USER, BILL_USER
--    Others get "Access Denied."
------------------------------------------------------------------------
BEGIN
    EXECUTE IMMEDIATE '
        CREATE OR REPLACE VIEW ADMIN_USER.Patient_Visit_Summary AS
        SELECT 
            TO_CHAR(V.VisitID) AS VisitID,
            P.FirstName || '' '' || P.LastName AS PatientName,
            D.FirstName || '' '' || D.LastName AS DoctorName,
            TO_CHAR(V.VisitDate, ''YYYY-MM-DD'') AS VisitDate,
            V.VisitReason,
            V.VisitStatus
        FROM ADMIN_USER.Visit V
             JOIN ADMIN_USER.Patient P ON V.PatientID = P.PatientID
             JOIN ADMIN_USER.Doctor D ON V.DoctorID = D.DoctorID
        WHERE UPPER(SYS_CONTEXT(''USERENV'', ''SESSION_USER'')) 
              IN (''ADMIN_USER'', ''BILL_USER'')

        UNION ALL

        SELECT
            ''Access Denied'' AS VisitID,
            ''Access Denied'' AS PatientName,
            ''Access Denied'' AS DoctorName,
            ''Access Denied'' AS VisitDate,
            ''Access Denied'' AS VisitReason,
            ''Access Denied'' AS VisitStatus
        FROM DUAL
        WHERE UPPER(SYS_CONTEXT(''USERENV'', ''SESSION_USER'')) 
              NOT IN (''ADMIN_USER'', ''BILL_USER'')
    ';
    DBMS_OUTPUT.PUT_LINE('View ADMIN_USER.Patient_Visit_Summary created.');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error creating ADMIN_USER.Patient_Visit_Summary: ' || SQLERRM);
END;
/
-- Grant SELECT on Patient_Visit_Summary to both BILL_USER and DOC_USER
BEGIN
    EXECUTE IMMEDIATE 'GRANT SELECT ON ADMIN_USER.Patient_Visit_Summary TO BILL_USER';
    DBMS_OUTPUT.PUT_LINE('Granted SELECT on Patient_Visit_Summary to BILL_USER');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error granting SELECT on Patient_Visit_Summary to BILL_USER: ' || SQLERRM);
END;
/
BEGIN
    EXECUTE IMMEDIATE 'GRANT SELECT ON ADMIN_USER.Patient_Visit_Summary TO DOC_USER';
    DBMS_OUTPUT.PUT_LINE('Granted SELECT on Patient_Visit_Summary to DOC_USER');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error granting SELECT on Patient_Visit_Summary to DOC_USER: ' || SQLERRM);
END;
/

------------------------------------------------------------------------
-- 3) CREATE OR REPLACE VIEW: Billing_Insights
--    Allowed: ADMIN_USER only
--    Everyone else gets "Access Denied."
------------------------------------------------------------------------
BEGIN
    EXECUTE IMMEDIATE '
        CREATE OR REPLACE VIEW ADMIN_USER.Billing_Insights AS
        SELECT
            TO_CHAR(B.BillID)       AS BillID,
            P.FirstName || '' '' || P.LastName AS PatientName,
            TO_CHAR(V.VisitDate, ''YYYY-MM-DD'') AS VisitDate,
            TO_CHAR(B.TotalAmount)  AS TotalAmount,
            B.PaymentStatus
        FROM ADMIN_USER.Billing B
             JOIN ADMIN_USER.Visit V    ON B.VisitID = V.VisitID
             JOIN ADMIN_USER.Patient P  ON B.PatientID = P.PatientID
        WHERE UPPER(SYS_CONTEXT(''USERENV'', ''SESSION_USER'')) = ''ADMIN_USER''

        UNION ALL

        SELECT
            ''Access Denied'' AS BillID,
            ''Access Denied'' AS PatientName,
            ''Access Denied'' AS VisitDate,
            ''Access Denied'' AS TotalAmount,
            ''Access Denied'' AS PaymentStatus
        FROM DUAL
        WHERE UPPER(SYS_CONTEXT(''USERENV'', ''SESSION_USER'')) <> ''ADMIN_USER''
    ';
    DBMS_OUTPUT.PUT_LINE('View ADMIN_USER.Billing_Insights created.');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error creating ADMIN_USER.Billing_Insights: ' || SQLERRM);
END;
/
-- Grant SELECT on Billing_Insights to BILL_USER (so non-admin users see "Access Denied")
BEGIN
    EXECUTE IMMEDIATE 'GRANT SELECT ON ADMIN_USER.Billing_Insights TO BILL_USER';
    DBMS_OUTPUT.PUT_LINE('Granted SELECT on Billing_Insights to BILL_USER');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error granting SELECT on Billing_Insights to BILL_USER: ' || SQLERRM);
END;
/

------------------------------------------------------------------------
-- 4) CREATE OR REPLACE VIEW: Doctor_Only_Patient_Summary
--    Allowed: DOC_USER only (and optionally ADMIN_USER)
------------------------------------------------------------------------
BEGIN
    EXECUTE IMMEDIATE '
        CREATE OR REPLACE VIEW ADMIN_USER.Doctor_Only_Patient_Summary AS
        SELECT 
            TO_CHAR(V.VisitID) AS VisitID,
            P.FirstName || '' '' || P.LastName AS PatientName,
            TO_CHAR(V.VisitDate, ''YYYY-MM-DD'') AS VisitDate,
            V.VisitReason,
            V.VisitStatus
        FROM ADMIN_USER.Visit V
             JOIN ADMIN_USER.Patient P ON V.PatientID = P.PatientID
             JOIN ADMIN_USER.Doctor D ON V.DoctorID = D.DoctorID
             JOIN ADMIN_USER.Users U ON D.UserID = U.UserID
        WHERE UPPER(U.Username) = UPPER(SYS_CONTEXT(''USERENV'', ''SESSION_USER''))
          AND UPPER(SYS_CONTEXT(''USERENV'', ''SESSION_USER'')) IN (''DOC_USER'', ''ADMIN_USER'')

        UNION ALL

        SELECT
            ''Access Denied'' AS VisitID,
            ''Access Denied'' AS PatientName,
            ''Access Denied'' AS VisitDate,
            ''Access Denied'' AS VisitReason,
            ''Access Denied'' AS VisitStatus
        FROM DUAL
        WHERE UPPER(SYS_CONTEXT(''USERENV'', ''SESSION_USER'')) NOT IN (''DOC_USER'', ''ADMIN_USER'')
    ';
    DBMS_OUTPUT.PUT_LINE('View ADMIN_USER.Doctor_Only_Patient_Summary created.');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error creating ADMIN_USER.Doctor_Only_Patient_Summary: ' || SQLERRM);
END;
/
-- Grant SELECT on Doctor_Only_Patient_Summary to DOC_USER and to BILL_USER (so they can see "Access Denied")
BEGIN
    EXECUTE IMMEDIATE 'GRANT SELECT ON ADMIN_USER.Doctor_Only_Patient_Summary TO DOC_USER';
    DBMS_OUTPUT.PUT_LINE('Granted SELECT on Doctor_Only_Patient_Summary to DOC_USER');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error granting SELECT on Doctor_Only_Patient_Summary to DOC_USER: ' || SQLERRM);
END;
/
BEGIN
    EXECUTE IMMEDIATE 'GRANT SELECT ON ADMIN_USER.Doctor_Only_Patient_Summary TO BILL_USER';
    DBMS_OUTPUT.PUT_LINE('Granted SELECT on Doctor_Only_Patient_Summary to BILL_USER');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error granting SELECT on Doctor_Only_Patient_Summary to BILL_USER: ' || SQLERRM);
END;
/

------------------------------------------------------------------------
-- 5) CREATE OR REPLACE VIEW: Billing_Only_View
--    Allowed: BILL_USER only (and optionally ADMIN_USER).
------------------------------------------------------------------------
BEGIN
    EXECUTE IMMEDIATE '
        CREATE OR REPLACE VIEW ADMIN_USER.Billing_Only_View AS
        SELECT 
            TO_CHAR(B.BillID) AS BillID,
            P.FirstName || '' '' || P.LastName AS PatientName,
            TO_CHAR(V.VisitDate, ''YYYY-MM-DD'') AS VisitDate,
            TO_CHAR(B.TotalAmount) AS TotalAmount,
            B.PaymentStatus
        FROM ADMIN_USER.Billing B
             JOIN ADMIN_USER.Visit V   ON B.VisitID = V.VisitID
             JOIN ADMIN_USER.Patient P ON B.PatientID = P.PatientID
        WHERE UPPER(SYS_CONTEXT(''USERENV'', ''SESSION_USER'')) IN (''BILL_USER'', ''ADMIN_USER'')

        UNION ALL

        SELECT
            ''Access Denied''  AS BillID,
            ''Access Denied''  AS PatientName,
            ''Access Denied''  AS VisitDate,
            ''Access Denied''  AS TotalAmount,
            ''Access Denied''  AS PaymentStatus
        FROM DUAL
        WHERE UPPER(SYS_CONTEXT(''USERENV'', ''SESSION_USER'')) NOT IN (''BILL_USER'', ''ADMIN_USER'')
    ';
    DBMS_OUTPUT.PUT_LINE('View ADMIN_USER.Billing_Only_View created.');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error creating ADMIN_USER.Billing_Only_View: ' || SQLERRM);
END;
/
-- Grant SELECT on Billing_Only_View to BILL_USER (already granted previously in your code)
BEGIN
    EXECUTE IMMEDIATE 'GRANT SELECT ON ADMIN_USER.Billing_Only_View TO BILL_USER';
    DBMS_OUTPUT.PUT_LINE('Granted SELECT on Billing_Only_View to BILL_USER');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error granting SELECT on Billing_Only_View to BILL_USER: ' || SQLERRM);
END;
/

------------------------------------------------------------
-- [UNDERLYING TABLE PRIVILEGES SECTION]
------------------------------------------------------------
BEGIN
    EXECUTE IMMEDIATE 'GRANT SELECT ON ADMIN_USER.Billing TO DOC_USER';
    DBMS_OUTPUT.PUT_LINE('Granted SELECT on Billing to DOC_USER');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error granting SELECT on Billing to DOC_USER: ' || SQLERRM);
END;
/
BEGIN
    EXECUTE IMMEDIATE 'GRANT SELECT ON ADMIN_USER.Visit TO DOC_USER';
    DBMS_OUTPUT.PUT_LINE('Granted SELECT on Visit to DOC_USER');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error granting SELECT on Visit to DOC_USER: ' || SQLERRM);
END;
/
BEGIN
    EXECUTE IMMEDIATE 'GRANT SELECT ON ADMIN_USER.Users TO DOC_USER';
    DBMS_OUTPUT.PUT_LINE('Granted SELECT on Users to DOC_USER');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error granting SELECT on Users to DOC_USER: ' || SQLERRM);
END;
/
BEGIN
    EXECUTE IMMEDIATE 'GRANT SELECT ON ADMIN_USER.MedicalRecord TO BILL_USER';
    DBMS_OUTPUT.PUT_LINE('Granted SELECT on MedicalRecord to BILL_USER');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error granting SELECT on MedicalRecord to BILL_USER: ' || SQLERRM);
END;
/
BEGIN
    EXECUTE IMMEDIATE 'GRANT SELECT ON ADMIN_USER.Visit TO BILL_USER';
    DBMS_OUTPUT.PUT_LINE('Granted SELECT on Visit to BILL_USER');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error granting SELECT on Visit to BILL_USER: ' || SQLERRM);
END;
/

------------------------------------------------------------
-- CREATE PUBLIC SYNONYMS FOR THE VIEWS
------------------------------------------------------------
BEGIN
    EXECUTE IMMEDIATE 'CREATE OR REPLACE PUBLIC SYNONYM Doctor_Availability FOR ADMIN_USER.Doctor_Availability';
    DBMS_OUTPUT.PUT_LINE('Public synonym Doctor_Availability created.');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error creating public synonym for Doctor_Availability: ' || SQLERRM);
END;
/
BEGIN
    EXECUTE IMMEDIATE 'CREATE OR REPLACE PUBLIC SYNONYM Patient_Visit_Summary FOR ADMIN_USER.Patient_Visit_Summary';
    DBMS_OUTPUT.PUT_LINE('Public synonym Patient_Visit_Summary created.');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error creating public synonym for Patient_Visit_Summary: ' || SQLERRM);
END;
/
BEGIN
    EXECUTE IMMEDIATE 'CREATE OR REPLACE PUBLIC SYNONYM Billing_Insights FOR ADMIN_USER.Billing_Insights';
    DBMS_OUTPUT.PUT_LINE('Public synonym Billing_Insights created.');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error creating public synonym for Billing_Insights: ' || SQLERRM);
END;
/
BEGIN
    EXECUTE IMMEDIATE 'CREATE OR REPLACE PUBLIC SYNONYM Doctor_Only_Patient_Summary FOR ADMIN_USER.Doctor_Only_Patient_Summary';
    DBMS_OUTPUT.PUT_LINE('Public synonym Doctor_Only_Patient_Summary created.');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error creating public synonym for Doctor_Only_Patient_Summary: ' || SQLERRM);
END;
/
BEGIN
    EXECUTE IMMEDIATE 'CREATE OR REPLACE PUBLIC SYNONYM Billing_Only_View FOR ADMIN_USER.Billing_Only_View';
    DBMS_OUTPUT.PUT_LINE('Public synonym Billing_Only_View created.');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error creating public synonym for Billing_Only_View: ' || SQLERRM);
END;
/








------------------------------------------------------------
-- [TEST CASES  FOR THE VIEWS SECTION]
------------------------------------------------------------


--Test Queries for ADMIN_USER
------------------------------------------------------------

SELECT * 
FROM ADMIN_USER.Doctor_Availability;
-- Expected: Returns full doctor details.


SELECT * 
FROM ADMIN_USER.Patient_Visit_Summary;
-- Expected: Returns all patient visit records with valid details.


SELECT * 
FROM ADMIN_USER.Billing_Insights;
-- Expected: Returns all billing records.


--Test Queries for DOC_USER
------------------------------------------------------------
SELECT * 
FROM ADMIN_USER.Doctor_Availability;
-- Expected: Returns full doctor details.


SELECT * 
FROM ADMIN_USER.Doctor_Only_Patient_Summary;
-- Expected: Returns visit records associated with DOC_USER (or "Access Denied" if DOC_USER is not matched).


SELECT * 
FROM ADMIN_USER.Patient_Visit_Summary;
-- Expected: Depending on your view logic, this could return "Access Denied" or no rows if Patient_Visit_Summary is not allowed for DOC_USER.



--Test Queries for BILL_USER
--------------------------------------------------------
SELECT * 
FROM ADMIN_USER.Billing_Only_View;
-- Expected: Returns billing-specific records for BILL_USER.


SELECT * 
FROM ADMIN_USER.Billing_Insights;
-- Expected: Should NOT be accessible to BILL_USER; ideally, it should return "Access Denied" or raise an error.


SELECT * 
FROM ADMIN_USER.Doctor_Only_Patient_Summary;
-- Expected: Should NOT be accessible to BILL_USER; it should return "Access Denied" or no data.






------------------------------------------------------------
-- PROCEDURES to be runned in ADMIN_ USER
------------------------------------------------------------
-- Procedure: Update_Visit_Status
CREATE OR REPLACE PROCEDURE Update_Visit_Status (
    p_visit_id IN VARCHAR2,
    p_status   IN VARCHAR2
) AS
BEGIN
    -- Validate the status value
    IF p_status NOT IN ('Pending', 'Completed', 'Canceled') THEN
        RAISE_APPLICATION_ERROR(-20003, 'Invalid visit status. Must be Pending, Completed, or Canceled.');
    END IF;
    
    -- Update Visit table
    UPDATE Visit
    SET VisitStatus = p_status
    WHERE VisitID = p_visit_id;
    
    -- Optionally: COMMIT; -- uncomment if automatic commit is desired
    
    DBMS_OUTPUT.PUT_LINE('Visit status updated successfully for ' || p_visit_id);
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error in Update_Visit_Status: ' || SQLERRM);
        RAISE;
END;
/
  
-- Procedure: Complete_Payment
CREATE OR REPLACE PROCEDURE Complete_Payment (
    p_bill_id IN VARCHAR2
) AS
BEGIN
    -- Update Billing table to mark payment as complete
    UPDATE Billing
    SET PaymentStatus = 'Paid'
    WHERE BillID = p_bill_id;
    
    -- Optionally: COMMIT; -- uncomment if automatic commit is desired
    
    DBMS_OUTPUT.PUT_LINE('Payment completed for Bill ' || p_bill_id);
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error in Complete_Payment: ' || SQLERRM);
        RAISE;
END;
/


-- Procedure: Record_Treatment
CREATE OR REPLACE PROCEDURE Record_Treatment (
    p_visit_id    IN VARCHAR2,
    p_description IN VARCHAR2
) AS
    -- Generate a unique TreatmentID using SYS_GUID (converted to hexadecimal)
    v_treatment_id VARCHAR2(50) := RAWTOHEX(SYS_GUID());
BEGIN
    INSERT INTO ADMIN_USER.TreatmentHistory (TreatmentID, VisitID, Description, TreatmentDate)
    VALUES (v_treatment_id, p_visit_id, p_description, SYSDATE);
    
    DBMS_OUTPUT.PUT_LINE('Treatment recorded successfully for Visit ' || p_visit_id ||
                         '. Treatment ID: ' || v_treatment_id);
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error in Record_Treatment: ' || SQLERRM);
        RAISE;
END;
/


BEGIN
    Record_Treatment('V001', 'Administered flu vaccine');
END;
/




-----------------------------------------------------------------------
--       PACKAGE :- [healthcare_pkg]
-----------------------------------------------------------------------



-- Package Specification (Header):

CREATE OR REPLACE PACKAGE ADMIN_USER.healthcare_pkg IS
    PROCEDURE Update_Visit_Status(p_visit_id IN VARCHAR2, p_status IN VARCHAR2);
    PROCEDURE Complete_Payment(p_bill_id IN VARCHAR2);
    PROCEDURE Record_Treatment(p_visit_id IN VARCHAR2, p_description IN VARCHAR2);
END healthcare_pkg;
/


--Package Body:


CREATE OR REPLACE PACKAGE BODY ADMIN_USER.healthcare_pkg IS

    PROCEDURE Update_Visit_Status(p_visit_id IN VARCHAR2, p_status IN VARCHAR2) IS
    BEGIN
        -- Validate the status value
        IF p_status NOT IN ('Pending', 'Completed', 'Canceled') THEN
            RAISE_APPLICATION_ERROR(-20003, 'Invalid visit status. Must be Pending, Completed, or Canceled.');
        END IF;
        
        UPDATE ADMIN_USER.Visit
        SET VisitStatus = p_status
        WHERE VisitID = p_visit_id;
        
        DBMS_OUTPUT.PUT_LINE('Visit status updated successfully for ' || p_visit_id);
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Error in Update_Visit_Status: ' || SQLERRM);
            RAISE;
    END Update_Visit_Status;
    
    PROCEDURE Complete_Payment(p_bill_id IN VARCHAR2) IS
    BEGIN
        UPDATE ADMIN_USER.Billing
        SET PaymentStatus = 'Paid'
        WHERE BillID = p_bill_id;
        
        DBMS_OUTPUT.PUT_LINE('Payment completed for Bill ' || p_bill_id);
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Error in Complete_Payment: ' || SQLERRM);
            RAISE;
    END Complete_Payment;
    
    PROCEDURE Record_Treatment(p_visit_id IN VARCHAR2, p_description IN VARCHAR2) IS
        v_treatment_id VARCHAR2(50) := RAWTOHEX(SYS_GUID());  -- it will generate unique ID
    BEGIN
        INSERT INTO ADMIN_USER.TreatmentHistory (TreatmentID, VisitID, Description, TreatmentDate)
        VALUES (v_treatment_id, p_visit_id, p_description, SYSDATE);
        
        DBMS_OUTPUT.PUT_LINE('Treatment recorded successfully for Visit ' || p_visit_id ||
                             '. Treatment ID: ' || v_treatment_id);
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Error in Record_Treatment: ' || SQLERRM);
            RAISE;
    END Record_Treatment;
    
END healthcare_pkg;
/





---------------------------------------------------------------
-- Test Package Queries for healthcare_pkg
---------------------------------------------------------------

-- Test Case: Update Visit Status with a valid status.
BEGIN
    -- Calling the procedure with a valid status.
    ADMIN_USER.healthcare_pkg.Update_Visit_Status('V001', 'Completed');
END;
/
-- After running, verify the update:
SELECT VisitID, VisitStatus FROM ADMIN_USER.Visit WHERE VisitID = 'V001';

---------------------------------------------------------------

-- Test Case: Update Visit Status with an invalid status.
-- This will trigger the validation and raise an error, which is then caught.
BEGIN
    -- Calling the procedure with an invalid status (e.g., 'InvalidStatus').
    ADMIN_USER.healthcare_pkg.Update_Visit_Status('V001', 'InvalidStatus');
EXCEPTION
    WHEN OTHERS THEN
        -- The error message should indicate that the status is invalid.
        DBMS_OUTPUT.PUT_LINE('Expected error: ' || SQLERRM);
END;
/
-- Optionally, re-run to confirm the behavior:
BEGIN
    ADMIN_USER.healthcare_pkg.Update_Visit_Status('V001', 'InvalidStatus');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Expected error: ' || SQLERRM);
END;
/

---------------------------------------------------------------

-- Test Case: Complete Payment.
-- This will update the Billing record with BillID 'B001' to 'Paid'.
BEGIN
    -- Calling the procedure with a valid BillID.
    ADMIN_USER.healthcare_pkg.Complete_Payment('B001');
END;
/
-- Verify the result:
SELECT BillID, PaymentStatus FROM ADMIN_USER.Billing WHERE BillID = 'B001';

---------------------------------------------------------------

-- Test Case: Record Treatment.
-- This will insert a new treatment record into the TreatmentHistory table
-- for the Visit with VisitID 'V001' with the given treatment description.
BEGIN
    -- Calling the procedure with a valid VisitID and treatment description.
    ADMIN_USER.healthcare_pkg.Record_Treatment('V001', 'Administered flu vaccine');
END;
/
-- Verify the treatment record:
SELECT * FROM ADMIN_USER.TreatmentHistory WHERE VisitID = 'V001';






------------------------------------------------------------------
-- Constraint Testing
------------------------------------------------------------------
-- These test cases check data integrity constraints on the underlying tables.
-- They should be executed while connected as ADMIN_USER.
------------------------------------------------------------------

-- Test Case 1: Insert duplicate email in Patient (should fail)
BEGIN
    INSERT INTO ADMIN_USER.Patient (PatientID, UserID, FirstName, LastName, DOB, Gender, Email, PhoneNumber, EmergencyContact, CreatedAt)
    VALUES ('P999', 'U001', 'Test', 'Duplicate', SYSDATE, 'Male', 'alice@example.com', '1231231234', 'Test Contact', SYSDATE);
    DBMS_OUTPUT.PUT_LINE('Constraint Test Failed: Duplicate email inserted.');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Constraint Test Passed: Duplicate email not allowed – ' || SQLERRM);
END;
/

-- Test Case 2: Appointment in the past (should fail business logic)
BEGIN
    INSERT INTO ADMIN_USER.Appointment (AppointmentID, DoctorID, AppointmentDate, AppointmentStatus)
    VALUES ('A999', 'D001', TO_DATE('2023-01-01','YYYY-MM-DD'), 'Scheduled');
    DBMS_OUTPUT.PUT_LINE('Constraint Test Failed: Past appointment inserted.');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Constraint Test Passed: Past appointment insertion blocked – ' || SQLERRM);
END;
/


-- Test Case 3: (Run as ADMIN_USER) Insert a Patient with an invalid Gender 
-- (will fail because Gender must be 'Male', 'Female', or 'Other')

BEGIN
    INSERT INTO ADMIN_USER.Patient 
       (PatientID, UserID, FirstName, LastName, DOB, Gender, Email, PhoneNumber, EmergencyContact, CreatedAt)
    VALUES 
       ('P888', 'U888', 'Invalid', 'Gender', TO_DATE('1990-01-01','YYYY-MM-DD'), 'Unknown', 'test_unknown@example.com', '0000000000', 'N/A', SYSDATE);
    DBMS_OUTPUT.PUT_LINE('Constraint Test Failed: Patient inserted with invalid gender.');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Constraint Test Passed: Patient with invalid gender not allowed – ' || SQLERRM);
END;
/


-- Test Case 4: (Run as DOC_USER) Doctor tries to update Billing (should fail)

BEGIN
    UPDATE ADMIN_USER.Billing 
    SET TotalAmount = 999.99 
    WHERE BillID = 'B001';
    DBMS_OUTPUT.PUT_LINE('Test Case Failed: Doctor updated Billing.');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Test Case Passed: Doctor cannot update Billing – ' || SQLERRM);
END;
/
 
 

-- Test Case 5: (Run as DOC_USER) Doctor tries to insert a Visit (should fail)

BEGIN
    INSERT INTO ADMIN_USER.Visit (VisitID, PatientID, DoctorID, VisitDate, VisitReason, VisitStatus)
    VALUES ('V999', 'P001', 'D001', SYSDATE, 'Unauthorized Visit', 'Pending');
    DBMS_OUTPUT.PUT_LINE('Test Case Failed: Doctor inserted Visit.');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Test Case Passed: Unauthorized Visit insert blocked – ' || SQLERRM);
END;
/
 

-- Test Case 6: (Run as DOC_USER) Doctor tries to delete a user (should fail)

BEGIN
    DELETE FROM ADMIN_USER.Users 
    WHERE Username = 'admin_user';
    DBMS_OUTPUT.PUT_LINE('Test Case Failed: Doctor deleted a user.');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Test Case Passed: Doctor cannot delete a user – ' || SQLERRM);
END;
/
 

-- Test Case 7: (Run as BILL_USER) Billing staff tries to update a MedicalRecord (should fail)

BEGIN
    UPDATE ADMIN_USER.MedicalRecord 
    SET ChronicConditions = 'Test Condition'
    WHERE RecordID = 'MR001';
    DBMS_OUTPUT.PUT_LINE('Test Case Failed: Billing staff updated MedicalRecord.');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Test Case Passed: Billing staff cannot update MedicalRecord – ' || SQLERRM);
END;
/
 

-- Test Case 8: (Run as BILL_USER) Billing staff tries to delete a Visit (should fail)

BEGIN
    DELETE FROM ADMIN_USER.Visit
    WHERE VisitID = 'V001';
    DBMS_OUTPUT.PUT_LINE('Test Case Failed: Billing staff deleted a Visit record.');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Test Case Passed: Billing staff cannot delete a Visit record – ' || SQLERRM);
END;
/
