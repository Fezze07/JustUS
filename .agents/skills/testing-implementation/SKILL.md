---
name: testing-implementation
description: Testing infrastructure and environment for JustUS. Includes centralized tests for backend integration, Flutter unit tests, and a mock AI service. Details on running unified tests and infrastructure setup.
risk: unknown
source: local
version: "1.0"
tags: [testing, infrastructure, backend, flutter, docker, mock-ai, jest, supertest]
---

# JustUs Testing Environment

This document describes the structure, configuration, and usage of the JustUs testing environment. The environment is designed to be reproducible, isolated from production services, and easy to run locally or in CI.

## 📁 Testing Structure

The testing artifacts are centralized at the project root to provide a unified view of the system's integrity.

```text
/
├── test/                       # Centralized Test Directory
│   ├── backend/                # Backend Integration & E2E Tests
│   │   ├── ai.routes.test.js
│   │   ├── auth.routes.test.js
│   │   ├── media.routes.test.js
│   │   ├── env-integrity.test.js # Verifies mock services are UP
│   │   ├── setupEnv.js         # Test environment initialization
│   │   └── support/            # Shared test utilities & mocks
│   ├── flutter/                # Flutter Unit & Widget Tests
│   │   ├── app_test.dart
│   │   ├── mood_state_test.dart
│   │   └── ...
│   └── mock-ai/                # Mock Ollama/AI Service
│       └── server.js           # Lightweight Node.js mock server
├── scripts/                    # Automation Scripts
│   ├── test-all.sh             # Unified test runner
│   └── docker-compose.test.yml # Infrastructure for tests
└── .env.test                   # Test-specific environment variables
```

## 🚀 Running Tests

### 1. Unified Run (Recommended)
The simplest way to run all tests (Backend + Flutter) is using the unified script. This script automatically starts the required Docker containers, runs the tests, and cleans up afterward.

```bash
bash scripts/test-all.sh
```

### 2. Running Backend Tests Individually
If you want to run only backend tests, ensure the mock infrastructure is running first:

```bash
# Start mock services
docker compose -f scripts/docker-compose.test.yml up -d mock-ai

# Run tests from the Backend directory
cd Backend
npm test
```

## 🛠 Infrastructure & Mocking

### Docker Compose
We use a lightweight Docker stack (`scripts/docker-compose.test.yml`) to provide dependencies that the backend expects:
- **mock-ai**: Emulates an Ollama server on port `11434`. It returns deterministic JSON responses to verify AI flows without consuming real tokens or requiring a GPU.

### Backend Mocking Strategy
The backend tests use **Jest** and **Supertest**. We mock external dependencies at the module boundary to avoid side effects:
- **Supabase**: Mocked via `jest.mock` in each test suite.
- **Cloudflare R2**: `r2Service` is mocked to return deterministic "signed" URLs.
- **AI**: Routed to the local `mock-ai` container.

## ✅ Environment Integrity
The `Backend/test/env-integrity.test.js` is a special test case that runs first. It verifies that:
1. The `ENV` and `NODE_ENV` are correctly set to `test`.
2. The Mock AI service is reachable and responding with the expected Ollama-style NDJSON protocol.

## 📝 Configuration Files

- **Backend/jest.config.js**: Configured to look for tests in `Backend/test` (colocated with the backend) and resolve modules from `Backend/node_modules`.
- **Backend/package.json**: Includes a `test` script that runs `npm run lint` (which covers both production code and `Backend/test`) before Jest.
- **scripts/test-all.sh**: Handles path resolution and Docker orchestration.

---
> [!TIP]
> Always ensure Docker is running before executing `test-all.sh`. If you encounter line-ending issues on Windows (e.g., `bash\r` errors), run the script using a bash-compatible terminal like Git Bash or WSL.
