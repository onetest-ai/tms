---
id: TMS-0001
title: Login with valid credentials
priority: critical
type: functional
module: authentication
status: ready
execution_type: automated
size: M
targets: [onetest-ai/app-web]
automation_test_id:
  - tests/e2e/login.spec.ts:Login.valid
requirements: [REQ-001]
tags: [smoke, login, happy-path]
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
