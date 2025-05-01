-- Enable DBMS_OUTPUT for logging messages
SET SERVEROUTPUT ON;

-------------------------------------------------------------
-- SECTION 1: Drop Existing Users (if they exist)
-------------------------------------------------------------
BEGIN
    FOR user_rec IN (SELECT username FROM dba_users 
                     WHERE username IN ('ADMIN_USER', 'DOC_USER', 'BILL_USER')) LOOP
        BEGIN
            EXECUTE IMMEDIATE 'DROP USER ' || user_rec.username || ' CASCADE';
            DBMS_OUTPUT.PUT_LINE('Dropped user: ' || user_rec.username);
        EXCEPTION
            WHEN OTHERS THEN
                DBMS_OUTPUT.PUT_LINE('Error dropping user ' || user_rec.username || ': ' || SQLERRM);
        END;
    END LOOP;
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error in dropping users block: ' || SQLERRM);
END;
/

-------------------------------------------------------------
-- SECTION 2: Create Users with Strong Passwords
-------------------------------------------------------------
BEGIN
    EXECUTE IMMEDIATE 'CREATE USER ADMIN_USER IDENTIFIED BY "Admin@Secure#1234"';
    DBMS_OUTPUT.PUT_LINE('Created user: ADMIN_USER');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error creating ADMIN_USER: ' || SQLERRM);
END;
/

BEGIN
    EXECUTE IMMEDIATE 'CREATE USER DOC_USER IDENTIFIED BY "Doctor@Secure#1234"';
    DBMS_OUTPUT.PUT_LINE('Created user: DOC_USER');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error creating DOC_USER: ' || SQLERRM);
END;
/

BEGIN
    EXECUTE IMMEDIATE 'CREATE USER BILL_USER IDENTIFIED BY "Billing@Secure#1234"';
    DBMS_OUTPUT.PUT_LINE('Created user: BILL_USER');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error creating BILL_USER: ' || SQLERRM);
END;
/

-------------------------------------------------------------
-- SECTION 3: Grant Basic Database Access (CONNECT, RESOURCE)
-------------------------------------------------------------
BEGIN
    EXECUTE IMMEDIATE 'GRANT CONNECT, RESOURCE TO ADMIN_USER';
    DBMS_OUTPUT.PUT_LINE('Granted CONNECT, RESOURCE to ADMIN_USER');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error granting CONNECT, RESOURCE to ADMIN_USER: ' || SQLERRM);
END;
/

BEGIN
    EXECUTE IMMEDIATE 'GRANT CONNECT, RESOURCE TO DOC_USER';
    DBMS_OUTPUT.PUT_LINE('Granted CONNECT, RESOURCE to DOC_USER');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error granting CONNECT, RESOURCE to DOC_USER: ' || SQLERRM);
END;
/

BEGIN
    EXECUTE IMMEDIATE 'GRANT CONNECT, RESOURCE TO BILL_USER';
    DBMS_OUTPUT.PUT_LINE('Granted CONNECT, RESOURCE to BILL_USER');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error granting CONNECT, RESOURCE to BILL_USER: ' || SQLERRM);
END;
/

-------------------------------------------------------------
-- SECTION 4: Grant Administrative Privileges to ADMIN_USER
-------------------------------------------------------------
BEGIN
    EXECUTE IMMEDIATE 'GRANT CREATE SESSION, CREATE TABLE, CREATE VIEW, CREATE SEQUENCE, CREATE PROCEDURE, CREATE TRIGGER TO ADMIN_USER';
    DBMS_OUTPUT.PUT_LINE('Granted DDL privileges to ADMIN_USER');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error granting DDL privileges to ADMIN_USER: ' || SQLERRM);
END;
/

BEGIN
    EXECUTE IMMEDIATE 'GRANT CREATE USER, ALTER USER, DROP USER TO ADMIN_USER';
    DBMS_OUTPUT.PUT_LINE('Granted user management privileges to ADMIN_USER');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error granting user management privileges to ADMIN_USER: ' || SQLERRM);
END;
/

BEGIN
    EXECUTE IMMEDIATE 'GRANT CREATE ROLE, GRANT ANY ROLE TO ADMIN_USER';
    DBMS_OUTPUT.PUT_LINE('Granted role management privileges to ADMIN_USER');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error granting role management privileges to ADMIN_USER: ' || SQLERRM);
END;
/

ALTER USER admin_user QUOTA UNLIMITED ON DATA;
GRANT CREATE PUBLIC SYNONYM TO ADMIN_USER;

-------------------------------------------------------------
-- SECTION 5: Grant Privileges to DOC_USER (Doctor Role)
-------------------------------------------------------------
BEGIN
    EXECUTE IMMEDIATE 'GRANT CREATE SESSION TO DOC_USER';
    DBMS_OUTPUT.PUT_LINE('Granted CREATE SESSION to DOC_USER');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error granting CREATE SESSION to DOC_USER: ' || SQLERRM);
END;
/

BEGIN
    EXECUTE IMMEDIATE 'GRANT SELECT, INSERT, UPDATE ON ADMIN_USER.Patient TO DOC_USER';
    DBMS_OUTPUT.PUT_LINE('Granted DML privileges on Patient to DOC_USER');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error granting privileges on Patient to DOC_USER: ' || SQLERRM);
END;
/

BEGIN
    EXECUTE IMMEDIATE 'GRANT SELECT, INSERT, UPDATE ON ADMIN_USER.Appointment TO DOC_USER';
    DBMS_OUTPUT.PUT_LINE('Granted DML privileges on Appointment to DOC_USER');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error granting privileges on Appointment to DOC_USER: ' || SQLERRM);
END;
/

BEGIN
    EXECUTE IMMEDIATE 'GRANT SELECT, INSERT, UPDATE ON ADMIN_USER.MedicalRecord TO DOC_USER';
    DBMS_OUTPUT.PUT_LINE('Granted DML privileges on MedicalRecord to DOC_USER');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error granting privileges on MedicalRecord to DOC_USER: ' || SQLERRM);
END;
/

BEGIN
    EXECUTE IMMEDIATE 'GRANT SELECT ON ADMIN_USER.Doctor TO DOC_USER';
    DBMS_OUTPUT.PUT_LINE('Granted SELECT on Doctor to DOC_USER');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error granting SELECT on Doctor to DOC_USER: ' || SQLERRM);
END;
/

-------------------------------------------------------------
-- SECTION 6: Grant Privileges to BILL_USER (Billing Role)
-------------------------------------------------------------
BEGIN
    EXECUTE IMMEDIATE 'GRANT CREATE SESSION TO BILL_USER';
    DBMS_OUTPUT.PUT_LINE('Granted CREATE SESSION to BILL_USER');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error granting CREATE SESSION to BILL_USER: ' || SQLERRM);
END;
/

BEGIN
    EXECUTE IMMEDIATE 'GRANT SELECT, INSERT, UPDATE ON ADMIN_USER.Billing TO BILL_USER';
    DBMS_OUTPUT.PUT_LINE('Granted DML privileges on Billing to BILL_USER');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error granting privileges on Billing to BILL_USER: ' || SQLERRM);
END;
/

-------------------------------------------------------------
-- SECTION 7: Prevent Unassigned Privileges (Revoke DROP ANY TABLE if granted)
-------------------------------------------------------------
DECLARE
    v_count NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_count FROM DBA_SYS_PRIVS 
    WHERE GRANTEE = 'DOC_USER' AND PRIVILEGE = 'DROP ANY TABLE';
    IF v_count > 0 THEN
        EXECUTE IMMEDIATE 'REVOKE DROP ANY TABLE FROM DOC_USER';
        DBMS_OUTPUT.PUT_LINE('Revoked DROP ANY TABLE from DOC_USER');
    ELSE
        DBMS_OUTPUT.PUT_LINE('No DROP ANY TABLE privilege found for DOC_USER');
    END IF;
    
    SELECT COUNT(*) INTO v_count FROM DBA_SYS_PRIVS 
    WHERE GRANTEE = 'BILL_USER' AND PRIVILEGE = 'DROP ANY TABLE';
    IF v_count > 0 THEN
        EXECUTE IMMEDIATE 'REVOKE DROP ANY TABLE FROM BILL_USER';
        DBMS_OUTPUT.PUT_LINE('Revoked DROP ANY TABLE from BILL_USER');
    ELSE
        DBMS_OUTPUT.PUT_LINE('No DROP ANY TABLE privilege found for BILL_USER');
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error in revoking privileges: ' || SQLERRM);
END;
/

-------------------------------------------------------------
-- SECTION 8: Create Public Synonyms (Accessible by all users)
-------------------------------------------------------------
-- These commands must be executed while connected as ADMIN_USER
BEGIN
    EXECUTE IMMEDIATE 'CREATE PUBLIC SYNONYM Patient FOR ADMIN_USER.Patient';
    DBMS_OUTPUT.PUT_LINE('Created public synonym: Patient');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error creating public synonym for Patient: ' || SQLERRM);
END;
/

BEGIN
    EXECUTE IMMEDIATE 'CREATE PUBLIC SYNONYM Doctor FOR ADMIN_USER.Doctor';
    DBMS_OUTPUT.PUT_LINE('Created public synonym: Doctor');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error creating public synonym for Doctor: ' || SQLERRM);
END;
/

BEGIN
    EXECUTE IMMEDIATE 'CREATE PUBLIC SYNONYM Appointment FOR ADMIN_USER.Appointment';
    DBMS_OUTPUT.PUT_LINE('Created public synonym: Appointment');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error creating public synonym for Appointment: ' || SQLERRM);
END;
/

BEGIN
    EXECUTE IMMEDIATE 'CREATE PUBLIC SYNONYM MedicalRecord FOR ADMIN_USER.MedicalRecord';
    DBMS_OUTPUT.PUT_LINE('Created public synonym: MedicalRecord');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error creating public synonym for MedicalRecord: ' || SQLERRM);
END;
/

BEGIN
    EXECUTE IMMEDIATE 'CREATE PUBLIC SYNONYM Billing FOR ADMIN_USER.Billing';
    DBMS_OUTPUT.PUT_LINE('Created public synonym: Billing');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error creating public synonym for Billing: ' || SQLERRM);
END;
/

