# Project: HEAL – Healthcare Entity Access & Logic

HEAL is a role-based healthcare database project designed using Oracle SQL. It supports secure data access and management for Admins, Doctors, and Billing Staff while maintaining healthcare data integrity, privacy, and optimized relational design.

---

## Project Metadata

- **Project Name:** HEAL (Healthcare Entity Access & Logic)
- **Author:** Darshan Patil
- **Created On:** April 16, 2025
- **Platform:** Oracle Database 21c (via SQL Developer on macOS ARM)
- **Schema Owner:** `ADMIN_USER`

---

##  Core Features

###  Role-Based Users
- **`ADMIN_USER`** – Full privileges (DDL, DML, grants)
- **`DOC_USER`** – View and manage visits/patients assigned
- **`BILL_USER`** – View and manage billing data only

###  Core Entities
- `Users`, `UserRoles`
- `Doctor`, `Patient`, `Appointment`, `Visit`
- `MedicalRecord`, `TreatmentHistory`, `Prescription`, `Billing`

###  Views
- `Doctor_Only_Patient_Summary`
- `Billing_Only_View`
- `Patient_Visit_Summary`
- `Doctor_Availability`
- `Billing_Insights`

###  Triggers & Procedures
- Prevent past appointments
- Update timestamps
- Role-based access enforcement
- Centralized `healthcare_pkg` for reusable logic

---

##  File Structure

| File | Purpose |
|------|---------|
| `User_Grants.sql` | Creates users and assigns privileges |
| `Table Creation.sql` | All DDL table definitions and constraints |
| `Insert Sample Data.sql` | Populates initial test data |
| `I_T_V_P_Pk_CT.sql.sql` | Indexes, triggers, views, packages, constraints |
| `README.md` | Project documentation |

---

##  Security Design

- Uses `SYS_CONTEXT('USERENV', 'SESSION_USER')` for access-aware views
- Implements strict `GRANT` and role segregation
- Public synonyms created for cross-user access without schema prefixes

---

##  Testing Strategy

- Includes test blocks to check:
  - Constraint violations
  - Unauthorized operations
  - Trigger validation
  - Procedure functionality
- Follows clean rollback-friendly data blocks

---

##  How to Run

1. **Connect to Oracle SQL Developer** as `ADMIN_USER`
2. Execute files in order:
    1. `User_Grants.sql`
    2. `Table Creation.sql`
    3. `Insert Sample Data.sql`
    4. `I_T_V_P_Pk_CT.sql.sql`
3. Login as different users to test views and procedures

---


