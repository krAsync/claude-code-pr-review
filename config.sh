# PR Reviewer config — sourced by review_prs.sh

# GitHub organization (or user) to scan for open PRs. Required.
ORG=""

# How strongly the bot leans toward APPROVE vs REQUEST_CHANGES.
# Scale: 1 (very strict) … 5 (very lenient)
#   1 — Strict:    request changes for any real bug, security issue, or notable code-quality problem.
#   2 — Cautious:  request changes for bugs and security issues; tolerate style/quality nits.
#   3 — Balanced:  request changes for clear bugs or security issues; otherwise approve.
#   4 — Lenient:   request changes only for critical security vulnerabilities (default).
#   5 — Rubberstamp: approve unless the diff is outright malicious or destructive.
APPROVAL_BIAS=4
