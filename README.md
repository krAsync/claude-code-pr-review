# claude-code-pr-review

Automated PR review using Claude Code, driven by a Linux cron job.

## Why

- **Saves tokens.** Each PR's latest commit SHA is recorded after review. On every cron tick the script lists open PRs and skips any whose latest commit it has already reviewed, so Claude is only invoked when there is actually something new to look at.
- **Uses Linux cron, not Claude's scheduler.** Claude Code's built-in scheduling is limited; a regular `crontab` entry gives precise control over frequency, run windows, and logging.
- **Comment-only.** The bot posts a review comment with a verdict. It never approves, requests changes formally, or merges — humans still drive the PR.

## Requirements

- `gh` CLI, authenticated against the org you want to review (`gh auth login`).
- `claude` CLI on `PATH` (Claude Code), able to run non-interactively (`claude -p -`).
- `bash`, `cron`.

## Setup

1. Clone the repo somewhere stable (the script reads `config.sh` next to itself).
2. Edit `config.sh`:
   - `ORG` — the GitHub org or user whose repos should be scanned. Required.
   - `APPROVAL_BIAS` — 1 (strict) … 5 (rubberstamp). See comments in `config.sh`.
3. Make sure the script is executable: `chmod +x review_prs.sh`.
4. Add a cron entry (`crontab -e`):

   ```cron
   */5 * * * * /absolute/path/to/review_prs.sh
   ```

   The script self-limits to 07:00–02:00 Europe/Prague and uses a lock file, so overlapping ticks are safe.

## How it works

1. Lists every non-archived repo in `ORG`.
2. For each open PR, fetches the latest commit SHA.
3. Skips the PR if `REPO#PR@SHA` is already in the reviewed file — this is the token-saver.
4. Otherwise pulls the diff (falling back to file-by-file patches if the diff is too large, capped at ~500 KB).
5. Pipes a prompt to `claude -p -`. The verdict instructions are built from `APPROVAL_BIAS`.
6. Posts the review as a PR comment via `gh pr review --comment` and records the SHA.

## State and logs

- `/tmp/pr-reviews.log` — run log.
- `/tmp/pr-reviewed.txt` — `REPO#PR@SHA` of every reviewed commit. Delete an entry to force a re-review.
- `/tmp/pr-review.lock` — prevents overlapping runs.
- `/tmp/pr-diff-err.txt` — stderr from the last `gh pr diff` attempt.

## Files

- `review_prs.sh` — the script cron runs.
- `config.sh` — `ORG` and `APPROVAL_BIAS`.
