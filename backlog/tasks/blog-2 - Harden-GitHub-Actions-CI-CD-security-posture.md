---
id: BLOG-2
title: Harden GitHub Actions CI/CD security posture
status: In Progress
assignee: []
created_date: '2026-07-15 11:17'
updated_date: '2026-07-15 11:24'
labels:
  - ci
  - infra
  - security
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Make it structurally impossible for pull requests to affect the GitHub Pages deployment, and lock down the Actions security baseline. Most of this is DONE (see checked ACs); remaining items are verification on a real PR/push and the forward-looking gachix cache guardrail (depends on BLOG-1).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Split workflows: ci.yml triggers on pull_request only (build + just e2e, permissions contents:read, no deploy job, no pages/id-token); deploy.yml triggers on push[master] + workflow_dispatch only with NO pull_request trigger
- [x] #2 Least privilege: workflow-level contents:read, pages/id-token scoped to the deploy job; repo default_workflow_permissions set to read and can_approve_pull_request_reviews disabled
- [x] #3 All actions SHA-pinned and no pull_request_target anywhere
- [x] #4 Fork-PR approval policy set to all_external_contributors; github-pages environment restricted to a master-only deployment branch policy
- [ ] #5 Verified on a real PR that ci.yml runs and exposes no deploy-capable job, and that a push to master still builds+tests+deploys green
- [ ] #6 gachix cache (BLOG-1) is read-only for PR runs: no signing key exposed to pull_request, ideally a separate cache namespace, so a PR cannot poison the artifact production deploys
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Split ci.yml (PR-only, read-only) from deploy.yml (push+dispatch, no pull_request trigger) in commits 18f133e / fa17a0c / 7759c8c (pushed, master at e461b62). Repo settings via gh API: fork-pr-contributor-approval=all_external_contributors; default_workflow_permissions=read + can_approve_pull_request_reviews=false; github-pages env master-only. AC5 PUSH PATH VERIFIED: push of e461b62 triggered only deploy.yml (ci.yml correctly did not run); run 29411177939 build+deploy both green. AC5 PR PATH still pending a real PR. AC6 pending BLOG-1 (gachix read-only for PRs). Revert settings: gh api -X PUT repos/eisbaw/eisbaw.github.com/actions/permissions/fork-pr-contributor-approval -f approval_policy=first_time_contributors ; gh api -X PUT repos/eisbaw/eisbaw.github.com/actions/permissions/workflow -f default_workflow_permissions=write -F can_approve_pull_request_reviews=true
<!-- SECTION:NOTES:END -->
