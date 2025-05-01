-- DATA for DMDD PROJECT

-- Insert Sample Data for Testing

-- Insert Data for UserRoles
INSERT INTO UserRoles VALUES ('R001', 'Admin');
INSERT INTO UserRoles VALUES ('R002', 'Doctor');
INSERT INTO UserRoles VALUES ('R003', 'BillingStaff');

-- Insert Data for Users
INSERT INTO Users (UserID, Username, PasswordHash, RoleID, CreatedAt, UpdatedAt) 
VALUES ('U001', 'admin_user', 'hashed_password', 'R001', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

INSERT INTO Users (UserID, Username, PasswordHash, RoleID, CreatedAt, UpdatedAt) 
VALUES ('U002', 'doctor_smith', 'hashed_password', 'R002', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

INSERT INTO Users (UserID, Username, PasswordHash, RoleID, CreatedAt, UpdatedAt) 
VALUES ('U003', 'billing_staff', 'hashed_password', 'R003', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

INSERT INTO Users (UserID, Username, PasswordHash, RoleID, CreatedAt, UpdatedAt) 
VALUES ('U004', 'doctor_jane', 'hashed_password', 'R002', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

INSERT INTO Users (UserID, Username, PasswordHash, RoleID, CreatedAt, UpdatedAt) 
VALUES ('U005', 'billing_mary', 'hashed_password', 'R003', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

-- Add Users for Patients & New Doctor
INSERT INTO Users (UserID, Username, PasswordHash, RoleID, CreatedAt, UpdatedAt) 
VALUES ('U006', 'bob_miller', 'hashed_password', NULL, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

INSERT INTO Users (UserID, Username, PasswordHash, RoleID, CreatedAt, UpdatedAt) 
VALUES ('U007', 'emma_wilson', 'hashed_password', NULL, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

INSERT INTO Users (UserID, Username, PasswordHash, RoleID, CreatedAt, UpdatedAt) 
VALUES ('U008', 'michael_johnson', 'hashed_password', NULL, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

INSERT INTO Users (UserID, Username, PasswordHash, RoleID, CreatedAt, UpdatedAt) 
VALUES ('U009', 'sophia_lee', 'hashed_password', NULL, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

INSERT INTO Users (UserID, Username, PasswordHash, RoleID, CreatedAt, UpdatedAt) 
VALUES ('U010', 'robert_brown', 'hashed_password', 'R002', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

-- Insert Data for Doctors
INSERT INTO Doctor VALUES ('D001', 'U002', 'John', 'Smith', 'Cardiology', 'DOC12345', 10, 'Available');
INSERT INTO Doctor VALUES ('D002', 'U004', 'Jane', 'Doe', 'Pediatrics', 'DOC67890', 8, 'Available');
INSERT INTO Doctor VALUES ('D003', 'U010', 'Robert', 'Brown', 'Neurology', 'DOC78901', 15, 'Available');

-- Insert Data for Patients
INSERT INTO Patient VALUES ('P001', 'U003', 'Alice', 'Johnson', TO_DATE('1990-05-10', 'YYYY-MM-DD'), 'Female', 'alice@example.com', '1234567890', 'Emergency Contact', CURRENT_TIMESTAMP);

INSERT INTO Patient VALUES ('P002', 'U006', 'Bob', 'Miller', TO_DATE('1985-02-14', 'YYYY-MM-DD'), 'Male', 'bob@example.com', '9876543210', 'Spouse Contact', CURRENT_TIMESTAMP);

INSERT INTO Patient VALUES ('P003', 'U007', 'Emma', 'Wilson', TO_DATE('1995-08-21', 'YYYY-MM-DD'), 'Female', 'emma@example.com', '7894561230', 'Mother Contact', CURRENT_TIMESTAMP);

INSERT INTO Patient VALUES ('P004', 'U008', 'Michael', 'Johnson', TO_DATE('1982-07-03', 'YYYY-MM-DD'), 'Male', 'michael@example.com', '4567891230', 'Brother Contact', CURRENT_TIMESTAMP);

INSERT INTO Patient VALUES ('P005', 'U009', 'Sophia', 'Lee', TO_DATE('1998-12-15', 'YYYY-MM-DD'), 'Female', 'sophia@example.com', '8529637410', 'Father Contact', CURRENT_TIMESTAMP);

-- Insert Data for Appointments 
INSERT INTO Appointment VALUES ('A001', 'D001', TO_DATE('2024-03-20', 'YYYY-MM-DD'), 'Scheduled');
INSERT INTO Appointment VALUES ('A002', 'D002', TO_DATE('2024-03-21', 'YYYY-MM-DD'), 'Completed');
INSERT INTO Appointment VALUES ('A003', 'D003', TO_DATE('2024-03-22', 'YYYY-MM-DD'), 'Scheduled'); 
INSERT INTO Appointment VALUES ('A004', 'D001', TO_DATE('2024-03-23', 'YYYY-MM-DD'), 'Scheduled');
INSERT INTO Appointment VALUES ('A005', 'D002', TO_DATE('2024-03-24', 'YYYY-MM-DD'), 'Scheduled');


-- Insert Data for Visits 
INSERT INTO Visit VALUES ('V001', 'P001', 'D001', TO_DATE('2024-03-20', 'YYYY-MM-DD'), CURRENT_TIMESTAMP, 'Regular Checkup', 'A001', 'Pending');
INSERT INTO Visit VALUES ('V002', 'P002', 'D002', TO_DATE('2024-03-21', 'YYYY-MM-DD'), CURRENT_TIMESTAMP, 'Annual Checkup', 'A002', 'Completed');
INSERT INTO Visit VALUES ('V003', 'P003', 'D003', TO_DATE('2024-03-22', 'YYYY-MM-DD'), CURRENT_TIMESTAMP, 'Neurology Consultation', 'A003', 'Pending'); 
INSERT INTO Visit VALUES ('V004', 'P004', 'D001', TO_DATE('2024-03-23', 'YYYY-MM-DD'), CURRENT_TIMESTAMP, 'Follow-up', 'A004', 'Pending');
INSERT INTO Visit VALUES ('V005', 'P005', 'D002', TO_DATE('2024-03-24', 'YYYY-MM-DD'), CURRENT_TIMESTAMP, 'General Consultation', 'A005', 'Pending');

-- Insert Data for Billing 
INSERT INTO Billing VALUES ('B001', 'P001', 'V001', 250.00, 'Pending');
INSERT INTO Billing VALUES ('B002', 'P002', 'V002', 180.00, 'Paid');
INSERT INTO Billing VALUES ('B003', 'P003', 'V003', 300.00, 'Pending'); 
INSERT INTO Billing VALUES ('B004', 'P004', 'V004', 150.00, 'Pending');
INSERT INTO Billing VALUES ('B005', 'P005', 'V005', 200.00, 'Pending');
