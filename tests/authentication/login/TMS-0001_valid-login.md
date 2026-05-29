---
id: TMS-0001                       # <source_key>-<seq>; allocated by allocate-id, never reused
title: Login with valid credentials
priority: critical                 # critical | high | medium | low
type: functional                   # functional | regression | smoke | integration | exploratory
module: authentication             # feature area (OneTest "component")
status: ready                      # draft | ready | deprecated (config-driven)
execution_type: automated          # manual | automated (drives automation coverage)
size: M                            # S | M | L — agent-execution cost (test-sizer); optional
targets: [onetest-ai/app-web]      # repo(s) under test; execution Issues are created there
automation_test_id:                # CI correlation key(s) — file:Class.method, one per line
  - tests/e2e/login.spec.ts:Login.valid
requirements: [REQ-001]            # traceability
tags: [smoke, login, happy-path]
# custom_fields: { jira_ticket: PROJ-99 }
---

# TMS-0001: Login with Valid Credentials

**Module:** Authentication · **Priority:** Critical · **Type:** Functional / Smoke

## Preconditions
- App is accessible at `{{base_url}}`
- Test user exists: email=`test@example.com`, password=`Test1234!`
- Browser cache and cookies are cleared

## Test Data

| Field    | Value            |
|----------|------------------|
| Email    | test@example.com |
| Password | Test1234!        |

## Steps

| # | Action                                          | Expected Result                              |
|---|-------------------------------------------------|----------------------------------------------|
| 1 | Navigate to `{{base_url}}/login`                | Login page loads; Email and Password visible |
| 2 | Fill Email with `test@example.com`              | Email value is set                           |
| 3 | Fill Password with `Test1234!`                  | Password input is masked                     |
| 4 | Click "Sign In"                                 | Redirects to `/dashboard`                    |
| 5 | Check header for "Welcome, Test User"           | Welcome message is visible                   |

## Expected Final State
User is authenticated and on the dashboard. No error messages. URL is `{{base_url}}/dashboard`.

## Teardown
- Navigate to `{{base_url}}/logout`
