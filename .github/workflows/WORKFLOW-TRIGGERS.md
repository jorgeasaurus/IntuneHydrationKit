# CI/CD Workflow Triggers

How to trigger the CI/CD pipeline from the command line.

## Prerequisites

- Git installed and configured
- GitHub CLI (`gh`) installed (optional, for manual triggers)

## Trigger Scenarios

### 1. Push to Any Branch

Runs the **build** job (test + build on all 3 OS platforms).

```bash
git add .
git commit -m "Your commit message"
git push origin <branch-name>
```

### 2. Create a Pull Request

Runs the **build** job.

```bash
# Create a new branch and push it
git checkout -b feature/my-feature
git add .
git commit -m "Add new feature"
git push -u origin feature/my-feature

# Create PR via GitHub CLI
gh pr create --base main --title "My Feature" --body "Description of changes"
```

### 3. Push a Version Tag (Full Release)

Runs **build**, **publish** (to PSGallery), and **create-release** (GitHub release) jobs.

```bash
# Ensure you're on main with latest changes
git checkout main
git pull origin main

# Create and push a version tag
git tag v0.2.6
git push origin v0.2.6
```

Annotated tag with a message:

```bash
git tag -a v0.2.3 -m "Release v0.2.3 - Description of changes"
git push origin v0.2.3
```

### 4. Manual Trigger

Runs the **build** job.

```bash
# Using GitHub CLI
gh workflow run "CI/CD Pipeline" --ref main

# Run from a specific branch
gh workflow run "CI/CD Pipeline" --ref feature/my-branch
```

## Quick Reference

| Scenario | Command | Jobs Run |
|----------|---------|----------|
| Push to any branch | `git push origin <branch>` | build |
| Open PR | `gh pr create --base main` | build |
| Release | `git tag v1.0.0 && git push origin v1.0.0` | build, publish, release |
| Manual | `gh workflow run "CI/CD Pipeline"` | build |

## Monitoring Workflow Runs

```bash
# List recent workflow runs
gh run list

# Watch a specific run
gh run watch

# View run details
gh run view <run-id>
```
