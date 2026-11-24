# Contributing Guidelines

Thank you for contributing to this project!

## Getting Started

1. **Fork and clone** this repository to your local machine.
2. Ensure you have **Docker Desktop** (or Docker Engine with Docker Compose) installed and running.
3. On Windows, ensure **Git for Windows** (Git Bash) is installed so that `stack.cmd` and `stack.sh` operate properly.

## Local Development Workflow

1. Create a branch for your feature or bugfix:
   ```bash
   git checkout -b feature/your-feature-name
   ```
2. Copy `.env.example` to `.env` if you have not already:
   ```bash
   cp .env.example .env
   ```
3. Test your changes locally:
   - On Windows (PowerShell / Command Prompt):
     ```cmd
     .\stack.cmd up
     ```
   - On Linux / macOS / Git Bash:
     ```bash
     bash stack.sh up
     ```
4. Verify configuration and script syntax:
   ```bash
   docker compose --env-file .env.example config --quiet
   bash -n stack.sh
   ```

## Guidelines

- Keep shell scripts POSIX/Bash compatible and ensure line endings remain `LF` as specified in `.gitattributes`.
- Avoid committing passwords, API keys, personal config, or database dumps in `.env` or project directories.
- Keep default ports and configurations backward compatible whenever possible.
- Update `README.md` or `GUIDE.md` if any commands, options, or environment variables are altered.

## Submitting Pull Requests

1. Commit your changes with clear, descriptive commit messages.
2. Push your branch to GitHub.
3. Open a Pull Request referencing any related issues and detailing the testing performed.
