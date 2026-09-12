# Secrets & Credentials Audit Report

## Overview

This audit evaluates the JustUS repository for accidentally committed secrets, hardcoded API keys, environment configuration security, Git tracking risks, and secret-handling practices across the Node.js backend, Flutter mobile app, and Supabase infrastructure.

---

## Executive Summary

| Category | Finding Summary | Risk Level |
| :--- | :--- | :--- |
| **Firebase Web/Mobile API Keys in Git** | `firebase_options.dart`, `google_services.json`, and `GoogleService-Info.plist` contain live Firebase Client API Keys tracked in Git | **MEDIUM** (Client Keys) |
| **Git Tracking Controls** | `.gitignore` properly excludes `.env`, `.env.*` (except `.env.example`), `secrets/`, and `*.key`/`*.pem` | **LOW / PASS** |
| **Test Configuration** | `.env.test` is tracked in Git, but contains safe dummy test placeholders | **LOW / PASS** |

---

## Detailed Secret Findings & Exposure Analysis

### 1. Root `.env` Credentials

* **File**: [`.env`](file:///f:/JustUS/.env)
* **Type of Secret**:
  - `SUPABASE_SERVICE_ROLE_KEY` (Supabase Admin Service Role JWT)
  - `OPENROUTER_API_KEY` (AI OpenRouter API Key)
  - `R2_SECRET_ACCESS_KEY` (Cloudflare R2 Storage Secret Access Key)
  - `TURNSTILE_SECRET_KEY` (Cloudflare Turnstile Secret Key)
  - `SUPABASE_ANON_KEY` (Supabase Anonymous JWT)
* **Appears Live**: **YES** (Valid, live administrative and cloud credentials).
* **Tracked by Git**: **NO** (Excluded by `.gitignore` rules `.env` and `.env.*`).
* **Exposure Impact**:
  - `SUPABASE_SERVICE_ROLE_KEY` bypasses all Row Level Security (RLS) policies in Supabase, granting full database read/write/delete access.
  - `R2_SECRET_ACCESS_KEY` grants full read/write access to Cloudflare R2 storage buckets (`just-us`).
  - `OPENROUTER_API_KEY` enables uninhibited AI model API usage billed to the account.
* **Recommended Remediation**:
  - Never store production credentials on local developer disk unencrypted.
  - Rotate all active keys (`SUPABASE_SERVICE_ROLE_KEY`, `OPENROUTER_API_KEY`, `R2_SECRET_ACCESS_KEY`) immediately if this machine or workspace environment is shared or accessible.
  - Ensure secret rotation mechanisms exist in deployment pipelines (e.g. GitHub Actions Secrets / Vercel / Railway / Docker secrets).

---

### 2. Firebase Client SDK Configuration Keys

* **Files**:
  - [`Flutter/lib/firebase_options.dart`](file:///f:/JustUS/Flutter/lib/firebase_options.dart#L44-L85)
  - [`Flutter/android/app/google-services.json`](file:///f:/JustUS/Flutter/android/app/google-services.json#L18)
  - [`Flutter/ios/Runner/GoogleService-Info.plist`](file:///f:/JustUS/Flutter/macos/Runner/GoogleService-Info.plist)
* **Type of Secret**: Firebase API Keys (`apiKey`), App IDs (`appId`), Messaging Sender ID (`messagingSenderId`).
* **Appears Live**: **YES** (Live Google Firebase project credentials for `justus-9888d`).
* **Tracked by Git**: **YES** (Tracked in Git repository).
* **Exposure Impact**:
  - Firebase Client API Keys are design-inherently public identifiers used by mobile clients to identify the Firebase project.
  - However, tracking `google-services.json` and `firebase_options.dart` exposing project numbers and app IDs increases the attack surface if Firebase Security Rules (Firestore / Realtime DB / Storage) or Firebase App Check are misconfigured.
* **Recommended Remediation**:
  - Enforce Firebase Security Rules and restrict API keys in the Google Cloud Console to specific Android SHA-1 fingerprints and iOS Bundle IDs (`com.fezze.justus`).
  - Enable Firebase App Check to prevent unauthorized API calls from off-target clients using the exposed public client keys.

---

### 3. Test Environment File (`.env.test`)

* **File**: [`.env.test`](file:///f:/JustUS/.env.test)
* **Type of Secret**: Mock/Test environment variables (`SUPABASE_SERVICE_ROLE_KEY=test-service-role-key`, `OPENROUTER_API_KEY=test-openrouter-key`, `R2_SECRET_ACCESS_KEY=test-secret-key`).
* **Appears Live**: **NO** (Contains dummy mock strings).
* **Tracked by Git**: **NO** (Explicitly ignored by `.env.*` in `.gitignore`, though `.env.example` is explicitly allowed via `!.env.example`).
* **Exposure Impact**: None (Mock data).
* **Recommended Remediation**: Maintain `.env.test` with non-sensitive dummy placeholders only.

---

### 4. Hardcoded Server Origins & API Config

* **File**: [`Flutter/lib/core/network/api_config.dart`](file:///f:/JustUS/Flutter/lib/core/network/api_config.dart#L6-L7)
* **Type of Secret**: Server Domain Names (`https://justus-dev.serverfede.eu`, `https://justus.serverfede.eu`).
* **Appears Live**: **YES** (Dev and Prod server domain URLs).
* **Tracked by Git**: **YES**.
* **Exposure Impact**: Exposes backend endpoint infrastructure hostnames in client code.
* **Recommended Remediation**: Inject server origins via environment configuration (`flutter_dotenv` or compile-time `--dart-define`) rather than hardcoding domain strings directly in source code.

---

## Gitignore Rules Audit

An evaluation of [`.gitignore`](file:///f:/JustUS/.gitignore) confirms that sensitive file patterns are properly covered:

```gitignore
# ENV files
.env
.env.*
!.env.example

# Secrets and Credentials
*.key
*.pem
*.p12
*.jks
*.keystore
*.pfx
*.crt
*.cert
secrets.json
service-account.json
firebase-key.json
local.properties
key.properties
```

### Verification Checklist

- [x] Root `.env` is NOT tracked in Git.
- [x] Backend `secrets/` folder is NOT tracked in Git.
- [x] Private keys (`*.pem`, `*.key`, `*.keystore`) are ignored.
- [x] `.env.example` contains only template placeholder strings (`your-service-role-key`, `your-turnstile-secret`).
- [! WARNING] `firebase_options.dart` and `google-services.json` are tracked in Git; while standard for Firebase apps, API key restrictions must be enforced at the provider level.

---

## Summary Table of Audit Findings

| File Path | Secret Type | Live? | Git Tracked? | Exposure Impact | Recommended Remediation |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `.env` | Supabase Service Role JWT, OpenRouter API Key, R2 Secret Key, Turnstile Secret | **YES** | **NO** | Critical if local env compromised | Store in secure secret vault; rotate keys periodically |
| `.env.test` | Mock credentials | **NO** | **NO** | None | Keep placeholders clean |
| `Flutter/lib/firebase_options.dart` | Firebase Client API Key | **YES** | **YES** | Low-Medium (Public client key) | Restrict API keys via Google Cloud Console & App Check |
| `Flutter/android/app/google-services.json` | Firebase Android Config & API Key | **YES** | **YES** | Low-Medium (Public client key) | Enforce Firebase RLS rules and package restriction |
| `Flutter/lib/core/network/api_config.dart` | Dev & Prod Hostnames | **YES** | **YES** | Low | Parameterize via `--dart-define` or `.env` |
