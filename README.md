# ScheduleCalendar

A full-stack schedule, task, and part-time income management application built with **Flutter (Dart)** and **Spring Boot (Java)**. Designed to unify personal events, academic schedules, linked to-do lists, and upcoming shift-based payroll tracking across timezones.

🔗 **Live Web App:** [https://starwars-k.github.io/ScheduleCalendar/](https://starwars-k.github.io/ScheduleCalendar/)  
*(Note: The backend runs on Render's free tier, so the first request after inactivity may take 30–50 seconds to wake up.)*

---

## Tech Stack

* **Frontend:** [Flutter](https://flutter.dev/) (Dart) – Web & Cross-Platform UI (Deployed on GitHub Pages)
* **Backend:** [Spring Boot](https://spring.io/projects/spring-boot) (Java 17) – REST API, Business Logic & Token Authentication (Deployed on Render)
* **Database:** [PostgreSQL](https://www.postgresql.org/) – Serverless Cloud Database on [Neon](https://neon.tech/) *(migrated from H2/MySQL)*
* **External Integrations:** [Nager.Date Public Holiday API](https://date.nager.at/) & [Resend](https://resend.com/) (optional password reset emails)

---

## Key Features

### Multi-Timezone Calendar & Recurring Events
* **Timezone-Aware Scheduling:** Set independent start and end timezones per event; timestamps are normalized to UTC in PostgreSQL and rendered in the user's configured timezone.
* **Recurring Series Management:** Supports `Daily`, `Weekly`, `Biweekly`, `Monthly`, and `Yearly` repeats with optional repeat end dates, single-occurrence edits, and bulk future deletion.
* **Automatic Public Holidays:** Automatically populates localized public holidays (`US`, `JP`, `GB`, `KR`, `AU`) based on your timezone and language settings.
* **Browser Notifications:** Configurable pre-event reminder alerts with browser notification support.

### Integrated To-Do List
* **Optional Module:** Enable or disable the To-Do List during initial setup or anytime in Settings.
* **Task & Calendar Sync:** Track tasks with categories, priorities (`LOW`, `MEDIUM`, `HIGH`), favorites, and optional due times, with two-way linking to calendar events.

### Account, Profile & Localization
* **Guided Initial Setup:** First-time onboarding flow to configure display language, timezone, and optional modules.
* **Bilingual Support:** Full English (`en`) and Japanese (`ja`) support across both the UI and backend-generated events.
* **Profile & Automatic Birthday Events:** Read-only profile view with a dedicated **Edit Account** modal (username and email updates without requiring a password). Saving a birthday automatically creates a non-duplicating, yearly all-day birthday event on your calendar.
* **Account Security:** PBKDF2-HMAC-SHA256 password hashing, HMAC-SHA256 signed Bearer tokens, password change/reset flows, confirmation-guarded logout, and permanent account deletion.

### Payroll Tracking *(Coming Soon)*
* Modular preferences and currency settings (`USD` / `JPY`) are built into the backend and user profile, ready for upcoming shift-based wage calculation.

---

## Project Architecture

```text
ScheduleCalendar/
├── calendar_frontend/          # Flutter (Dart) web & cross-platform client
│   └── lib/
│       ├── main.dart               # Calendar views, navigation & app state
│       ├── login_page.dart         # Login, registration & password reset
│       ├── initialSetupPage.dart   # First-time onboarding & UserAppSettings model
│       ├── settings_page.dart      # Profile, preferences, security & account controls
│       ├── event_detail_page.dart  # Event creation, editing & recurrence options
│       ├── todo_list_page.dart     # Task list, filters & event linking
│       └── notification_service.dart
└── calendar_backend/           # Spring Boot (Java 17) REST API
    └── src/main/java/com/keito/calendar_backend/
        ├── AuthController.java     # Auth, password management & profile settings endpoints
        ├── AuthService.java        # Token signing, password hashing & birthday event helper
        ├── EventController.java    # Event CRUD, recurrence expansion & holiday sync
        ├── TodoController.java     # To-Do CRUD & linked event synchronization
        ├── UserController.java     # Initial setup & user preferences endpoints
        └── WebConfig.java          # CORS configuration
```

---

## Core API Endpoints

| Domain | Method & Endpoint | Description |
| :--- | :--- | :--- |
| **Auth** | `POST /api/auth/register`, `POST /api/auth/login` | Create an account or authenticate with username/email |
| **Auth** | `POST /api/auth/change-password`, `POST /api/auth/reset-password` | Update or reset account password |
| **Account** | `PUT /api/auth/settings`, `DELETE /api/auth/account` | Update profile/preferences or permanently delete account |
| **User** | `GET /api/user/settings`, `PUT /api/user/settings` | Retrieve or save onboarding & general settings |
| **Events** | `GET /api/events`, `POST /api/events` | Fetch user events (with yearly/holiday/birthday sync) or create events |
| **Events** | `PUT /api/events/{id}`, `DELETE /api/events/{id}`, `DELETE /api/events/future/{id}` | Update an event, delete a single event, or delete future occurrences |
| **Todos** | `GET /api/todos`, `POST /api/todos`, `PUT /api/todos/{id}`, `DELETE /api/todos/{id}` | Manage to-do items and synced calendar tasks |
| **Health** | `GET /api/health` | Service health check |

---

## Local Development Setup

### 1. Backend (`calendar_backend`)
1. Configure a `.env` file in `calendar_backend/` with your PostgreSQL and app secrets:
   ```env
   SPRING_DATASOURCE_URL=jdbc:postgresql://<your-neon-host>/neondb?sslmode=require
   SPRING_DATASOURCE_USERNAME=<your-db-user>
   SPRING_DATASOURCE_PASSWORD=<your-db-password>
   APP_AUTH_SECRET=<your-hmac-secret>
   APP_MAIL_RESEND_API_KEY=<optional-resend-api-key>
   ```
2. Start the Spring Boot server on `http://localhost:8080`:
   ```bash
   cd calendar_backend
   set -a && source .env && set +a
   ./mvnw spring-boot:run
   ```

### 2. Frontend (`calendar_frontend`)
Run the Flutter web client pointed at your local backend:
```bash
cd calendar_frontend
flutter pub get
flutter run -d chrome --dart-define=BACKEND_BASE_URL=http://localhost:8080
```
