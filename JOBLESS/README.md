How to run:
1. open project in Eclipse
2. ensure sqlite-jdbc dependency is added to your Module build path and (jdatepicker-1.3.4,flatlaf-3.5.4) are added to Cllasspath
3. run LoginScreen.java from src/ui/auth



JOBLESS
Job Organization & Balancing Logic for Efficient Scheduling Systems
A Java Swing Desktop Application for Job Management

Project Overview

JOBLESS is a role-based desktop application designed to streamline job postings and applications. It helps bridge the gap between job seekers and employers by offering a lightweight, centralized platform that is accessible offline and built entirely in Java using the Swing framework and SQLite database.

This project is ideal for use in regions with limited cloud infrastructure and is perfect for academic or practical demonstration of MVC-based Java desktop development.

Tech Stack

Frontend: Java Swing

Backend: Java

Database: SQLite

IDE: Eclipse

Architecture: Model-View-Controller (MVC)

Features

Authentication

Login for Admin and User roles

Registration with role selection

Forgot Password screen (reset simulation)

Admin Functionalities

Post new job listings

Schedule jobs using priority comparators

View and manage posted jobs

View job category analytics

User Functionalities

Browse and filter available jobs

Apply to jobs with resume upload

Track previously applied jobs

Job Scheduling

Jobs prioritized using custom comparator logic based on deadline or importance

Project Structure

pgsql
ArrayOfHope/
├── src/
│   ├── model/                Core models: User, Job, Application
│   ├── ui/
│   │   ├── auth/             Login, Register, Forgot Password screens
│   │   ├── main/             Dashboards for Admin/User
│   │   └── views/            Post, View, Schedule, Apply job screens
│   ├── data/                 DAOs for DB operations (UserDAO, JobDAO, etc.)
│   ├── scheduler/            JobScheduler with Comparator logic
│   └── util/                 SessionManager and utility classes
├── array_of_hope.db          SQLite Database
├── README.md

How to Run

Open the project in Eclipse or any Java IDE

Ensure the sqlite-jdbc dependency is added to your build path

Run LoginScreen.java from src/ui/auth

Default credentials (for demo):

Admin:
Username: admin
Password: admin123

User:
Username: user
Password: user123

Future Enhancements
Feature					Description
Email Notifications		Alert users on new job postings
Cloud Database Support	Firebase or MongoDB integration
Resume Parsing Engine	Suggest jobs based on resume contents
Analytics Dashboard		Visual admin insights for job categories
OAuth Login				Google or LinkedIn-based sign-in
2FA Support				Two-factor authentication for enhanced security
Job Referral System		Allow users to share job links or refer friends



License

This project is for academic and demonstration purposes. For any external use or distribution, please contact the authors.