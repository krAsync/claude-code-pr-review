#!/bin/bash
# Svarog PR Reviewer — runs via cron every 5 minutes (7am-2am Prague time)

ORG="Svarog-tech"
DISCORD_CHANNEL="1490391080225472584"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REVIEW_LOG="/tmp/svarog-pr-reviews.log"
REVIEWED_FILE="/tmp/svarog-pr-reviewed.txt"

log() {
    echo "$(date) — $1" >> "$REVIEW_LOG"
}

# Create reviewed file if it doesn't exist
touch "$REVIEWED_FILE"

# Lock file to prevent overlapping runs
LOCKFILE="/tmp/svarog-pr-review.lock"
if [ -f "$LOCKFILE" ]; then
    LOCK_PID=$(cat "$LOCKFILE" 2>/dev/null)
    if kill -0 "$LOCK_PID" 2>/dev/null; then
        echo "$(date) — Another review run is active (PID $LOCK_PID), exiting" >> "$REVIEW_LOG"
        exit 0
    fi
fi
echo $$ > "$LOCKFILE"
trap 'rm -f "$LOCKFILE"' EXIT

# Only run between 7:00 and 2:00 Prague time
HOUR=$(TZ="Europe/Prague" date +%H)
if [ "$HOUR" -ge 2 ] && [ "$HOUR" -lt 7 ]; then
    exit 0
fi

log "Starting PR review run"

# Get all repos
REPOS=$(gh repo list "$ORG" --no-archived --limit 100 --json nameWithOwner -q '.[].nameWithOwner' 2>>"$REVIEW_LOG")

if [ -z "$REPOS" ]; then
    log "ERROR: Failed to fetch repo list"
    exit 1
fi

for REPO in $REPOS; do
    # Get open PRs
    PRS=$(gh pr list -R "$REPO" --state open --json number,title,author --jq '.[] | "\(.number)|\(.title)|\(.author.login)"' 2>>"$REVIEW_LOG")

    [ -z "$PRS" ] && continue

    while IFS='|' read -r PR_NUM PR_TITLE PR_AUTHOR; do
        [ -z "$PR_NUM" ] && continue

        # Get latest commit SHA for this PR
        LATEST_SHA=$(gh pr view -R "$REPO" "$PR_NUM" --json commits --jq '.commits[-1].oid' 2>>"$REVIEW_LOG")

        if [ -z "$LATEST_SHA" ]; then
            log "ERROR: Could not get latest commit SHA for $REPO#$PR_NUM"
            continue
        fi

        # Skip if we already reviewed this exact commit
        REVIEW_KEY="$REPO#$PR_NUM@$LATEST_SHA"
        if grep -qF "$REVIEW_KEY" "$REVIEWED_FILE" 2>/dev/null; then
            log "Skipping $REPO#$PR_NUM (already reviewed commit $LATEST_SHA)"
            continue
        fi

        log "Reviewing $REPO#$PR_NUM: $PR_TITLE"

        # Try full diff first
        DIFF=$(gh pr diff -R "$REPO" "$PR_NUM" 2>/tmp/svarog-pr-diff-err.txt)
        DIFF_ERR=$(cat /tmp/svarog-pr-diff-err.txt)

        if [ -z "$DIFF" ] && [ -n "$DIFF_ERR" ]; then
            log "Full diff failed for $REPO#$PR_NUM: $DIFF_ERR"

            # Diff too large — fetch changed files list and review file-by-file
            log "Falling back to file-by-file review for $REPO#$PR_NUM"

            FILES=$(gh pr view -R "$REPO" "$PR_NUM" --json files --jq '.files[].path' 2>>"$REVIEW_LOG")

            if [ -z "$FILES" ]; then
                log "ERROR: Could not get changed files for $REPO#$PR_NUM"
                continue
            fi

            FILE_COUNT=$(echo "$FILES" | wc -l)
            log "Found $FILE_COUNT changed files in $REPO#$PR_NUM"

            # Build a summary of changes per file (fetch patches individually)
            COMBINED_DIFF=""
            FILE_NUM=0
            while IFS= read -r FILE_PATH; do
                FILE_NUM=$((FILE_NUM + 1))
                # Use gh api to get individual file patch
                PATCH=$(gh api "repos/$REPO/pulls/$PR_NUM/files" --jq ".[] | select(.filename == \"$FILE_PATH\") | \"--- \(.filename) (\(.status), +\(.additions)/-\(.deletions))\\n\(.patch // \"[binary or too large]\")\"" 2>>"$REVIEW_LOG")
                if [ -n "$PATCH" ]; then
                    COMBINED_DIFF="$COMBINED_DIFF
$PATCH
"
                fi
                # Cap at ~500KB to avoid overwhelming Claude
                if [ ${#COMBINED_DIFF} -gt 500000 ]; then
                    log "Truncating diff at file $FILE_NUM/$FILE_COUNT (hit 500KB limit)"
                    COMBINED_DIFF="$COMBINED_DIFF
... [truncated — $FILE_COUNT files total, showing first $FILE_NUM]"
                    break
                fi
            done <<< "$FILES"

            if [ -z "$COMBINED_DIFF" ]; then
                log "ERROR: Could not fetch any file patches for $REPO#$PR_NUM"
                continue
            fi

            DIFF="$COMBINED_DIFF"
        elif [ -z "$DIFF" ]; then
            log "ERROR: Empty diff and no error for $REPO#$PR_NUM — skipping"
            continue
        fi

        DIFF_SIZE=${#DIFF}
        log "Diff size for $REPO#$PR_NUM: $DIFF_SIZE bytes"

        # Use Claude Code to review (non-interactive, piped via stdin to avoid arg limit)
        PROMPT="You are a senior code reviewer. Review this PR diff for security vulnerabilities, bugs, and performance issues. Be specific with file names and line numbers.

At the end give exactly one of these verdicts:
- APPROVE — no critical issues found, safe to merge
- REQUEST_CHANGES — only if there are CRITICAL security vulnerabilities (e.g. SQL injection, hardcoded secrets in code, authentication bypass). Minor suggestions, style nits, missing docs, or nice-to-haves are NOT reasons to request changes.

Default to APPROVE unless there is a genuine critical security flaw. Be pragmatic, not pedantic.

PR: $REPO#$PR_NUM — $PR_TITLE by $PR_AUTHOR

Diff:
$DIFF"
        REVIEW=$(echo "$PROMPT" | claude -p - 2>>"$REVIEW_LOG")

        if [ -z "$REVIEW" ]; then
            log "ERROR: Claude returned empty review for $REPO#$PR_NUM"
            continue
        fi

        REVIEW_SIZE=${#REVIEW}
        log "Claude review for $REPO#$PR_NUM: $REVIEW_SIZE bytes"

        # Post review as comment only — no approvals, no merges
        if echo "$REVIEW" | grep -qi "REQUEST_CHANGES"; then
            VERDICT="⚠️ Issues found (comment only)"
        else
            VERDICT="✅ Looks good (comment only)"
        fi

        GH_OUTPUT=$(gh pr review -R "$REPO" "$PR_NUM" --comment --body "$REVIEW

🤖 Automated review by Claude" 2>&1)
        GH_EXIT=$?

        if [ $GH_EXIT -ne 0 ]; then
            log "ERROR: gh pr review failed for $REPO#$PR_NUM (exit $GH_EXIT): $GH_OUTPUT"
            continue
        fi

        log "Posted review comment on $REPO#$PR_NUM"

        # Mark as reviewed
        echo "$REVIEW_KEY" >> "$REVIEWED_FILE"

        # Send Discord notification
        SHORT_REVIEW=$(echo "$REVIEW" | head -20)
        DISCORD_OUTPUT=$(python3 "$SCRIPT_DIR/krysa_pr.py" \
            --channel "$DISCORD_CHANNEL" \
            --title "PR Review: ${REPO##*/}#$PR_NUM — $PR_TITLE" \
            --message "**Repo:** $REPO
**Author:** $PR_AUTHOR
**Verdict:** $VERDICT

$SHORT_REVIEW" 2>&1)
        DISCORD_EXIT=$?

        if [ $DISCORD_EXIT -ne 0 ]; then
            log "ERROR: Discord notification failed for $REPO#$PR_NUM (exit $DISCORD_EXIT): $DISCORD_OUTPUT"
        else
            log "Sent Discord notification for $REPO#$PR_NUM"
        fi

        log "Done reviewing $REPO#$PR_NUM ($VERDICT)"

    done <<< "$PRS"
done

log "PR review run complete"
