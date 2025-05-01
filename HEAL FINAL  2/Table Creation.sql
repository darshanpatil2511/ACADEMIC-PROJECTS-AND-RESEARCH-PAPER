-- Drop existing tables if they exist to ensure re-execution does not fail
DROP TABLE Users CASCADE CONSTRAINTS;
DROP TABLE UserRoles CASCADE CONSTRAINTS;
DROP TABLE Doctor CASCADE CONSTRAINTS;
DROP TABLE Patient CASCADE CONSTRAINTS;
DROP TABLE Appointment CASCADE CONSTRAINTS;
DROP TABLE Visit CASCADE CONSTRAINTS;
DROP TABLE MedicalRecord CASCADE CONSTRAINTS;
DROP TABLE TreatmentHistory CASCADE CONSTRAINTS;
DROP TABLE Prescription CASCADE CONSTRAINTS;
DROP TABLE Billing CASCADE CONSTRAINTS;

-- UserRoles Table
CREATE TABLE UserRoles (
    RoleID VARCHAR2(50) PRIMARY KEY,
    RoleName VARCHAR2(50) CHECK (RoleName IN ('Admin', 'Doctor', 'BillingStaff'))
);

-- Users Table
CREATE TABLE Users (
    UserID VARCHAR2(50) PRIMARY KEY,
    Username VARCHAR2(50) UNIQUE NOT NULL,
    PasswordHash VARCHAR2(256) NOT NULL,
    RoleID VARCHAR2(50),
    CreatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT FK_Users_Role FOREIGN KEY (RoleID) REFERENCES UserRoles(RoleID)
);

-- Doctor Table
CREATE TABLE Doctor (
    DoctorID VARCHAR2(50) PRIMARY KEY,
    UserID VARCHAR2(50) UNIQUE NOT NULL,
    FirstName VARCHAR2(50) NOT NULL,
    LastName VARCHAR2(50) NOT NULL,
    Specialization VARCHAR2(50) NOT NULL,
    LicenseNumber VARCHAR2(50) UNIQUE NOT NULL,
    YearsOfExperience NUMBER(3,1) CHECK (YearsOfExperience >= 0),
    Availability VARCHAR2(50) NOT NULL,
    CONSTRAINT FK_Doctor_User FOREIGN KEY (UserID) REFERENCES Users(UserID)
);

-- Patient Table
CREATE TABLE Patient (
    PatientID VARCHAR2(50) PRIMARY KEY,
    UserID VARCHAR2(50) UNIQUE NOT NULL,
    FirstName VARCHAR2(50) NOT NULL,
    LastName VARCHAR2(50) NOT NULL,
    DOB DATE NOT NULL,
    Gender VARCHAR2(10) CHECK (Gender IN ('Male', 'Female', 'Other')),
    Email VARCHAR2(100) UNIQUE NOT NULL,
    PhoneNumber VARCHAR2(20) NOT NULL,
    EmergencyContact VARCHAR2(100) NOT NULL,
    CreatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT FK_Patient_User FOREIGN KEY (UserID) REFERENCES Users(UserID)
);

-- Appointment Table
CREATE TABLE Appointment (
    AppointmentID VARCHAR2(50) PRIMARY KEY,
    DoctorID VARCHAR2(50) NOT NULL,
    AppointmentDate DATE NOT NULL,
    AppointmentStatus VARCHAR2(50) CHECK (AppointmentStatus IN ('Scheduled', 'Completed', 'Canceled')),
    CONSTRAINT FK_Appointment_Doctor FOREIGN KEY (DoctorID) REFERENCES Doctor(DoctorID)
);

-- Visit Table
CREATE TABLE Visit (
    VisitID VARCHAR2(50) PRIMARY KEY,
    PatientID VARCHAR2(50) NOT NULL,
    DoctorID VARCHAR2(50) NOT NULL,
    VisitDate DATE NOT NULL,
    VisitTime TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    VisitReason VARCHAR2(500) NOT NULL,
    AppointmentID VARCHAR2(50) UNIQUE,
    VisitStatus VARCHAR2(50) CHECK (VisitStatus IN ('Pending', 'Completed', 'Canceled')),
    CONSTRAINT FK_Visit_Appointment FOREIGN KEY (AppointmentID) REFERENCES Appointment(AppointmentID),
    CONSTRAINT FK_Visit_Doctor FOREIGN KEY (DoctorID) REFERENCES Doctor(DoctorID),
    CONSTRAINT FK_Visit_Patient FOREIGN KEY (PatientID) REFERENCES Patient(PatientID)
);

-- MedicalRecord Table
CREATE TABLE MedicalRecord (
    RecordID VARCHAR2(50) PRIMARY KEY,
    PatientID VARCHAR2(50) NOT NULL,
    ChronicConditions VARCHAR2(500),
    RecordDate DATE NOT NULL,
    CONSTRAINT FK_MedicalRecord_Patient FOREIGN KEY (PatientID) REFERENCES Patient(PatientID)
);

-- TreatmentHistory Table
CREATE TABLE TreatmentHistory (
    TreatmentID VARCHAR2(50) PRIMARY KEY,
    VisitID VARCHAR2(50) NOT NULL,
    Description VARCHAR2(500) NOT NULL,
    TreatmentDate TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT FK_TreatmentHistory_Visit FOREIGN KEY (VisitID) REFERENCES Visit(VisitID)
);

-- Prescription Table
CREATE TABLE Prescription (
    PrescriptionID VARCHAR2(50) PRIMARY KEY,
    TreatmentID VARCHAR2(50) NOT NULL,
    Medication VARCHAR2(100) NOT NULL,
    Dosage VARCHAR2(50) NOT NULL,
    CONSTRAINT FK_Prescription_Treatment FOREIGN KEY (TreatmentID) REFERENCES TreatmentHistory(TreatmentID)
);

-- Billing Table
CREATE TABLE Billing (
    BillID VARCHAR2(50) PRIMARY KEY,
    PatientID VARCHAR2(50) NOT NULL,
    VisitID VARCHAR2(50) NOT NULL,
    TotalAmount NUMBER(10,2) CHECK (TotalAmount >= 0) NOT NULL,
    PaymentStatus VARCHAR2(50) CHECK (PaymentStatus IN ('Paid', 'Pending', 'Failed')) NOT NULL,
    CONSTRAINT FK_Billing_Patient FOREIGN KEY (PatientID) REFERENCES Patient(PatientID),
    CONSTRAINT FK_Billing_Visit FOREIGN KEY (VisitID) REFERENCES Visit(VisitID)
);
