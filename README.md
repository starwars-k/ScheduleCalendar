# ScheduleCalendar
A full-stack schedule, task, and part-time income management application built with **Flutter (Dart)** and **Spring Boot(Java)**. Designed to unify personal events, academic schedules, task lists, and shift-based payroll tracking across timezones.

🔗 **Live Web App:** [https://starwars-k.github.io/ScheduleCalendar/](https://starwars-k.github.io/ScheduleCalendar/)  
*(Note: The backend runs on Render's free tier, so the first request after inactivity may take 30–50 seconds to wake up.)*

---

## Tech Stack

* **Frontend:** Flutter (Dart) — Web & Cross-Platform UI (Deployed on GitHub Pages)
* **Backend:** Java, Spring Boot — REST API, Business Logic & JWT Authentication (Deployed on Render)
* **Database:** PostgreSQL — Serverless Cloud Database on Neon *(migrated from H2/MySQL)*

---

## Application Modules & Features

### Implemented
* **Authentication & User Preferences:** Secure registration and login with JWT (`Bearer` token), onboarding setup, language toggle (English / Japanese), and default timezone configuration.
* **Calendar Page (`DailyEvent` Engine):**
  * Full CRUD operations for single and recurring events (`Daily`, `Weekly`, `Biweekly`, `Monthly`, `Yearly`) with single-instance or series deletion.
  * Multi-timezone support (`startTimezone` / `endTimezone`) with automatic UTC storage and local offset conversion.
  * All-day event support and real-time search/filtering by event title or category.
* **Color-Coded Categories:** Visual organization across `Task`, `Job`, `Class`, `Birthday`, and `Personal` event types.

### In Progress / Planned
* **Task List & Reminder Pages:** Integrated to-do lists and reminders connected to calendar schedules.
* **AutoFill Engine:** Automated task-list synchronization triggered by user actions.
* **Job Income (Payroll) Page:** Shift tracking from `Job` calendar events to calculate gross/net income and estimate taxes.

---

## System Architecture & Data Flow

### General & AutoFill Engine Flow
1. **User Action:** The user creates, updates, or completes an event/task in the Flutter UI.
2. **API Call:** Flutter sends an authenticated HTTP JSON request (`GET` / `POST` / `PUT` / `DELETE`) to the Spring Boot REST API.
3. **Backend Processing & Persistence:** Spring Boot validates the JWT, executes calendar/AutoFill business logic, and persists records to Neon PostgreSQL.
4. **API Response:** Spring Boot returns the updated state/confirmation payload to the Flutter client.
5. **UI Synchronization:** Flutter updates the local state and refreshes the Calendar and Task List views.

---

## Project Structure

```text
ScheduleCalendar/
├── lib/
│   ├── main.dart              # App entry, AuthGate, CalendarPage, event creation/edit modal
│   ├── login_page.dart        # User login & registration UI
│   ├── initialSetupPage.dart  # Onboarding settings (language, timezone, module toggles)
│   ├── event_model.dart       # DailyEvent data model & UTC/timezone conversion logic
│   └── EventDetailPage.dart   # Event details, category updates & series deletion
└── ...