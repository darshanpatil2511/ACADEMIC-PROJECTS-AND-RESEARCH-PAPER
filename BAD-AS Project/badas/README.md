# BAD-AS — Boston Aid and Dispatch Assistant System

A Java Swing desktop application for hospital network management and emergency ambulance dispatch. Supports six role-based dashboards, a 3-step dispatch wizard, automated symptom analysis, and SQLite-backed persistence.

---

## Features

| Role | Capabilities |
|---|---|
| Admin | Add / edit / delete hospitals, view fleet statistics |
| Dispatcher | Create emergency dispatches (3-step wizard), manage active dispatches, auto-generate reports |
| Doctor | View and update patient diagnosis and prescriptions, search patients |
| Nurse | Update patient status with preset or custom values |
| Receptionist | Register new patients, view patient list |
| Coordinator | Manage emergency cases, assign resources, open/close cases |
| IT Support | Add/edit/delete user accounts, reset passwords, change roles |

**Cross-cutting**
- Dark / light theme toggle (FlatLaf), preference persisted across sessions
- SHA-256 password hashing — no plaintext passwords stored anywhere
- Role-specific color-coded UI badges and severity indicators
- Live clock in status bar
- Dispatch reports auto-saved to `reports/` on confirm

---

## Prerequisites

| Requirement | Version |
|---|---|
| Java JDK | 17 or later (tested on JDK 22) |
| sqlite-jdbc | 3.51.3.0 |
| FlatLaf | 3.7.1 |

Both JARs must be present in the `lib/` folder before compiling or running.

### Download the JARs

**sqlite-jdbc-3.51.3.0.jar**
```
https://repo1.maven.org/maven2/org/xerial/sqlite-jdbc/3.51.3.0/sqlite-jdbc-3.51.3.0.jar
```

**flatlaf-3.7.1.jar**
```
https://repo1.maven.org/maven2/com/formdev/flatlaf/3.7.1/flatlaf-3.7.1.jar
```

Place both files inside the `lib/` directory:
```
lib/
  sqlite-jdbc-3.51.3.0.jar
  flatlaf-3.7.1.jar
```

---

## Build and Run

All commands are run from the `badas/` project root.

### Compile

```bash
javac -cp "lib/sqlite-jdbc-3.51.3.0.jar:lib/flatlaf-3.7.1.jar" \
      -d out \
      $(find src -name "*.java")
```

On Windows (Command Prompt) replace `:` with `;`:
```cmd
javac -cp "lib/sqlite-jdbc-3.51.3.0.jar;lib/flatlaf-3.7.1.jar" -d out ^
      (Get-ChildItem -Recurse src -Filter *.java | % FullName)
```

### Run

```bash
java -cp "out:lib/sqlite-jdbc-3.51.3.0.jar:lib/flatlaf-3.7.1.jar" com.badas.Main
```

On Windows:
```cmd
java -cp "out;lib/sqlite-jdbc-3.51.3.0.jar;lib/flatlaf-3.7.1.jar" com.badas.Main
```

### Run as JAR (after packaging)

If you build a JAR using the included `manifest.mf`:
```bash
jar cfm badas.jar manifest.mf -C out .
java -jar badas.jar
```

---

## VS Code / Cursor Setup

The `.vscode/` folder already contains the correct configuration.

**settings.json** tells the Java extension where sources and libraries live:
```json
{
  "java.project.sourcePaths": ["src"],
  "java.project.referencedLibraries": ["lib/**/*.jar"]
}
```

**launch.json** provides a ready-to-use debug configuration named **BADAS**. If the JARs are not picked up automatically, update the `classPaths` entries to absolute paths:
```json
"classPaths": [
  "$Auto",
  "/absolute/path/to/lib/sqlite-jdbc-3.51.3.0.jar",
  "/absolute/path/to/lib/flatlaf-3.7.1.jar"
]
```

> **Tip:** If the IDE launcher fails to find SQLite, run the project from the terminal using the commands above — this bypasses classpath resolution issues in unmanaged Java projects.

---

## Default Login Credentials

The database is seeded automatically on first run. Use these accounts to log in:

| Username | Password | Role |
|---|---|---|
| `admin` | `admin123` | Admin |
| `dispatcher1` | `disp123` | Dispatcher |
| `doctor1` | `doc123` | Doctor |
| `nurse1` | `nurse123` | Nurse |
| `receptionist1` | `recep123` | Receptionist |
| `coordinator1` | `coord123` | Coordinator |
| `itsupport1` | `it123` | IT Support |

---

## Project Structure

```
badas/
├── src/
│   └── com/badas/
│       ├── Main.java                        # Entry point
│       ├── model/                           # Plain data objects
│       │   ├── User.java
│       │   ├── Patient.java
│       │   ├── Hospital.java
│       │   ├── DispatchRequest.java
│       │   └── EmergencyCase.java
│       ├── dao/                             # Database access layer
│       │   ├── DatabaseManager.java         # SQLite init + seeding
│       │   ├── UserDAO.java
│       │   ├── PatientDAO.java
│       │   ├── HospitalDAO.java
│       │   ├── DispatchDAO.java
│       │   └── EmergencyDAO.java
│       ├── service/                         # Business logic
│       │   ├── AuthService.java             # Session management
│       │   ├── SymptomAnalyzer.java         # Keyword-based triage
│       │   └── ReportService.java           # Dispatch report writer
│       └── ui/
│           ├── common/
│           │   ├── BaseFrame.java           # Shared header/sidebar/statusbar
│           │   ├── UIConstants.java         # Colors, fonts, dimensions
│           │   └── ThemeManager.java        # FlatLaf dark/light toggle
│           ├── auth/
│           │   └── LoginFrame.java
│           ├── dashboard/
│           │   ├── AdminDashboard.java
│           │   ├── DoctorDashboard.java
│           │   ├── NurseDashboard.java
│           │   ├── ReceptionistDashboard.java
│           │   ├── CoordinatorDashboard.java
│           │   └── ITSupportDashboard.java
│           └── dispatcher/
│               └── DispatcherDashboard.java
├── lib/
│   ├── sqlite-jdbc-3.51.3.0.jar
│   └── flatlaf-3.7.1.jar
├── out/                                     # Compiled .class files (git-ignored)
├── reports/                                 # Auto-generated dispatch reports
├── badas.db                                 # SQLite database (created on first run)
├── manifest.mf
└── .vscode/
    ├── settings.json
    └── launch.json
```

---

## Architecture

```
UI Layer  (Swing / FlatLaf)
    │
    ▼
Service Layer  (AuthService · SymptomAnalyzer · ReportService)
    │
    ▼
DAO Layer  (JDBC PreparedStatement — one class per table)
    │
    ▼
SQLite  (badas.db — single file, auto-created on startup)
```

- **BaseFrame** is the abstract superclass for every dashboard. It builds the shared chrome (header, sidebar, content area, status bar) and defers `showPanel()` via `SwingUtilities.invokeLater()` to avoid subclass field initialization race conditions.
- **ThemeManager** stores the chosen theme in `java.util.prefs.Preferences` so it survives restarts.
- **SecurityUtils** hashes passwords with SHA-256 — passwords are never stored or logged in plaintext.
- **SymptomAnalyzer** scores free-text symptoms against CRITICAL / MODERATE / MINOR keyword sets and factors patient age into the ambulance recommendation.

---

## Dispatch Workflow

The Dispatcher dashboard provides a 3-step wizard:

1. **Patient Intake** — name, age, contact number, pickup location
2. **Symptom Analysis** — free-text description, inline triage button returns severity (Critical / Moderate / Minor) and ambulance type recommendation
3. **Confirm Dispatch** — summary grid, hospital assignment, one-click confirm saves the record to the database and writes a timestamped report file to `reports/`

Active dispatches can be marked as Dispatched, Cancelled, or deleted from the Active Dispatches table.

---

## Data Persistence

The SQLite database (`badas.db`) is created in the working directory on first launch. Tables:

| Table | Purpose |
|---|---|
| `users` | Accounts with hashed passwords and roles |
| `patients` | Patient records with diagnosis and status |
| `hospitals` | Hospital fleet data (total and available ambulances) |
| `dispatch_requests` | All dispatch events |
| `emergency_cases` | Coordinator-managed emergency cases |

No external database server is required — the file is self-contained and portable.
