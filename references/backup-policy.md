# Instance Backup Policy

This policy defines what each instance Git backup repo should include and exclude.

## Required to Track

1. `openclaw.json`
2. `workspace/` (this is the most important data to back up)

## Required to Exclude

1. `.env` (contains tokens/secrets)
2. All backup/bak variants
3. Regenerable runtime/caches (logs, media, browser profile cache, node_modules cache)

## Canonical `.gitignore` Baseline

```gitignore
.env

*.bak
*.bak.*
*.backup
*.backup.*
.backup-*/
openclaw.json.backup*
openclaw.json.*.bak*
openclaw.json.*backup*

logs/
media/
agents/*/qmd/xdg-cache/
browser/openclaw/user-data/
extensions/**/node_modules/

.workspace-embedded-git-backup-*/
workspace-engineer/
```

## Audit Commands

Run inside each instance state dir:

```bash
# .env must not be tracked
git ls-files --error-unmatch .env >/dev/null 2>&1 && echo "BAD: .env tracked" || echo "OK: .env not tracked"

# workspace should be tracked
git ls-files workspace >/dev/null 2>&1 && echo "OK: workspace tracked" || echo "WARN: workspace not tracked"

# openclaw.json should be tracked
git ls-files --error-unmatch openclaw.json >/dev/null 2>&1 && echo "OK: openclaw.json tracked" || echo "WARN: openclaw.json not tracked"

# backup artifacts should not be tracked
git ls-files | grep -E '\\.bak($|\\.)|\\.backup($|\\.)|openclaw\\.json\\..*(bak|backup)' && echo "BAD: backup files tracked" || echo "OK: backup files not tracked"
```

## If `.env` Was Ever Tracked

Immediate actions:

1. `git rm --cached .env`
2. Commit and push
3. Rewrite history to remove `.env` if needed
4. Rotate exposed tokens

History rewrite example:

```bash
git filter-branch --force --index-filter 'git rm --cached --ignore-unmatch .env' --prune-empty --tag-name-filter cat -- --all
git for-each-ref --format='delete %(refname)' refs/original | git update-ref --stdin
git reflog expire --expire=now --all
git gc --prune=now --aggressive
git push --force --all
git push --force --tags
```
