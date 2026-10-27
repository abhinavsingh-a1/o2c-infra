# Jenkins: promotion pipelines

Jenkins promotes a release from dev to test, then to prod (o2c-app ADR-018). It runs
locally next to the kind cluster `o2c`. Everything about it is code:
- `ansible/`: the runner image, the playbook `jenkins.yml` and the role `jenkins` (image,
  JCasC, container);
- `jenkins/`: the two Jenkinsfiles, their shell helpers (`lib.sh`) and the k6 script.

## Before you start
- **The kind cluster and the platform are running** (o2c-app `make cluster-up`, then
  `platform/kind/bootstrap.sh`), and so is the Compose stack (o2c-app `make up`).
- **These keys are set in `o2c-app/.env`** (git-ignored; never printed):

  | Key | Used for |
  |---|---|
  | `JENKINS_ADMIN_PASSWORD` | user `abhinav` (administrator) |
  | `JENKINS_APPROVER_PASSWORD` | user `approver` |
  | `JENKINS_GITHUB_TOKEN` | o2c-gitops PRs and merges, attestation checks |

  The GitHub token needs contents and pull requests (read and write) on o2c-gitops, and
  read access to o2c-app's attestations. A fine-grained token for the two repos works.
- **Once per environment** (secrets and Kafka topics):
  ```bash
  platform/kind/secrets.sh o2c-test          # and o2c-prod
  make -C ../o2c-app topics ENV=test         # and ENV=prod
  ```
- **The Jenkinsfiles are read from o2c-infra main.** A pipeline change takes effect after
  its PR is merged.

## Start, stop, log in
```bash
make jenkins-up      # build the image if needed, start Jenkins, wait until the admin can log in
make jenkins-down    # remove the container; the volume o2c-jenkins-home stays
```
`make jenkins-up` is idempotent: run it again after changing the role, the image or a
password in `.env`. A changed secret restarts Jenkins; a changed image recreates the
container.

Then open **http://localhost:18090** and log in as `abhinav` or `approver`, with the
passwords from `o2c-app/.env`. Port 8080 is taken on this machine, so Jenkins listens on
18090, on 127.0.0.1 only.

| User | May |
|---|---|
| `abhinav` | everything (administrator) |
| `approver` | see the jobs, start builds, approve the prod promotion; nothing else |

Configuration made in the UI is lost on the next start: change
`ansible/roles/jenkins/files/image/casc.yaml` and run `make jenkins-up`.

## promote-to-test
Start **promote-to-test** with **Build Now**. The pipeline:
1. verifies the dev images (signature and provenance of o2c-app's release on main) and
   finds their o2c-app commit: the newest one that every image has a build provenance
   for (an image unchanged across releases has one per release);
2. opens a PR in o2c-gitops setting `envs/test` to those images with 1 replica, and
   merges it when its checks pass;
3. syncs the test applications in Argo CD and waits until they are healthy;
4. runs the gates. Any failure fails the build:
   - the integration test;
   - the OWASP ZAP baseline of the ui and the agent API: any high-risk alert, and any
     alert of a FAIL rule in `jenkins/zap-baseline.conf` (the security headers, vulnerable
     or cross-domain scripts); informational rules stay WARN;
   - the k6 load test;
   - `make eval`.
5. scales `o2c-test` back to 0, whatever happened.

It takes about 20 to 40 minutes, mostly `make eval`. The first run also downloads the
ZAP and k6 images and the o2c-app Python environment.

## promote-to-prod
1. **As `abhinav`:** open **promote-to-prod**, then **Build with Parameters**.
   - Leave `SIMULATE_SLO_BREACH` off for a normal promotion.
   - Turn it on to see the rollback: the SLO check fails on purpose.
2. The build verifies the test images and records the change request. Until E13 the
   change request is `SKIPPED (E13 pending)`. Setting `SERVICENOW_URL` (Manage Jenkins,
   System, global properties) and a username/password credential `servicenow` turns it
   on.
3. The build waits at **Approval (four eyes)**.
4. **Log out and log in as `approver`.** Open the build and choose **Approve**: either in
   the stage view, or under **Paused for Input**.
   - The user who started the build cannot approve it: the build fails if they try.
   - It also works the other way round: `approver` starts and `abhinav` approves.
5. The build then:
   - opens and merges the prod PR;
   - syncs prod and waits until it is healthy;
   - runs the smoke test and the SLO check.
6. **If anything fails after the merge, the build rolls back.** It:
   - opens a revert PR in o2c-gitops and merges it;
   - syncs prod back to the previous images and checks them.

   The build stays failed, and `reports/rollback.txt` names both commits.
7. **If the SLO check fails but the build merged no PR** (envs/prod already had the test
   images, e.g. a second `SIMULATE_SLO_BREACH` run), prod was not changed by this build
   and nothing is rolled back. The build stays failed; the log and `reports/rollback.txt`
   say "SLO breached; nothing to roll back: this run did not change prod (envs/prod
   unchanged)".

`make prod-down` scales `o2c-prod` to 0 to free memory. Argo CD then shows prod
OutOfSync; the next promotion syncs it back.

## Reports
Each build archives its reports: open the build, then **Build Artifacts**.

| File | Contents |
|---|---|
| `reports/images-<env>.txt` | the promoted images (service, image by digest, port, health path) |
| `reports/integration-test.txt` | PASS/FAIL lines of the integration test (test) |
| `reports/zap-ui.html`, `zap-agent-api.html` (and `.json`), `zap-baseline.conf` | ZAP baseline reports and the rules they used (test) |
| `reports/k6-test.json`, `k6-prod-slo.json` | k6 summaries: p95, error rate, thresholds |
| `o2c-app/eval/report.md`, `report.json` | `make eval` report (test) |
| `reports/change-request.txt`, `approval.txt` | change request; who started and who approved (prod) |
| `reports/smoke-test.txt`, `rollback.txt` | smoke test (prod); the reverted and the revert commit, or why nothing was rolled back |

The console log shows each stage, with timestamps.

The audit trail is in the volume: logins, configuration changes, builds with their cause,
and approvals.
```bash
docker exec o2c-jenkins sh -c 'tail -n 50 /var/jenkins_home/audit-trail.log.*[0-9]'   # rotated: .0, .1, ...
```

## Troubleshooting
- **`make jenkins-up` fails at "Log in as abhinav":**
  - run `docker logs o2c-jenkins` and look for JCasC errors;
  - check that the three `JENKINS_*` keys are set in `.env`.
- **"no valid signature" or "no o2c-app commit in common":** dev or test is not running
  one complete release (the error lists the commits of each image). Wait for the
  release's gitops PR to merge, or check the images with `scripts/verify_image.sh` in
  o2c-app.
- **"has no scripts/promote_values.py":** the release predates ADR-018. Release o2c-app
  main again, then promote.
- **Argo CD steps fail with `lookup ... on 10.96.0.10:53: i/o timeout` for minutes**
  (for `github.com` and for `argocd-repo-server` alike) and the retries do not help:
  kindnet, kind's CNI, loses the DNS queries of pods that a NetworkPolicy selects. The
  Argo CD chart used to create such policies. `platform/kind/bootstrap.sh` now installs
  Argo CD without them and restarts kindnet if packets are stuck in its queue: run it
  again, then retry the build. Cause, evidence and checks: `platform/README.md`.
- **The integration test times out:** check that the test pods are running and that the
  topics exist (`make topics ENV=test` in o2c-app). Then read the agent's log:
  `kubectl -n o2c-test logs deploy/agent` (the build scales test to 0 afterwards, so
  read the log while the build runs).
