# Curveballs

Everything that broke (or nearly broke) while taking Notesy from "runs on a laptop" to "running on ECS", in the order it happened. Each entry is written the way I'd tell it in a walkthrough: what I saw, how I found the cause, what I changed, and what I took from it.

---

## CI / scanning

### 1. SonarCloud: "Organization key does not exist"

- **Symptom:** The Sonar job failed with `Organization key 'TheJoker91' does not exist`.
- **Diagnosis:** The scanner was reaching SonarCloud fine, so it wasn't auth or networking. The value in `SONAR_ORGANIZATION` was the org's *display name*. SonarCloud identifies orgs by a separate lowercase *key*, visible in the org URL (`sonarcloud.io/organizations/<key>`).
- **Fix:** Set `SONAR_ORGANIZATION` to the real key and matched `SONAR_PROJECT_KEY` exactly (it's case-sensitive).
- **Takeaway:** Many platforms have a display name and an ID. Tools want the ID.

### 2. SonarCloud quality gate failing the pipeline

- **Symptom:** The scan succeeded but the job exited 3 with `QUALITY GATE STATUS: FAILED`.
- **Diagnosis:** `sonar.qualitygate.wait=true` makes the job block on the gate's verdict. On a first analysis the default gate fails on coverage for new code, which is an app-code issue rather than a pipeline one.
- **Fix:** Set `sonar.qualitygate.wait=false`. The scan and results still upload, and real scanner errors still fail the job. I chose this over `continue-on-error`, which would also hide broken config.
- **Takeaway:** This is a deliberate, documented tradeoff (see DEPLOY.md). A gate that can't fail the build is only acceptable when you say so out loud.

### 3. Proving a failing test actually fails CI

- **Symptom:** Not a failure. Ticket NOTESY-104 hinted at a "silent test failure", so "tests are green" wasn't evidence of anything.
- **Diagnosis:** I pushed a throwaway branch with `assert False` and opened a PR.
- **Result:** `Tests + Coverage` went red (`1 failed, 4 passed`, exit code 1) and Sonar was skipped. Branch deleted afterwards.
- **Takeaway:** A gate is only proven when you've watched it close.

---

## Containers

### 4. `exec ./entrypoint.sh: exec format error`

- **Symptom:** The web container restarted in a loop with exit code 255.
- **Diagnosis:** The kernel couldn't identify the script as executable. That almost always means line 1 isn't exactly `#!/bin/sh`. The heredoc command used to *create* the file (`cat > entrypoint.sh << 'EOF'`) had been pasted *into* the file, so the shebang was on line 2.
- **Fix:** Rewrote the file with the shebang on line 1 and LF line endings, then rebuilt with `--build` because the broken file was baked into the old image.
- **Takeaway:** For `exec format error` on a script, check the first bytes (`head -c 16 file | od -c`). Look for BOMs, blank lines and CRLF.

### 5. Container took ~10 seconds to stop

- **Symptom:** `docker compose down` took 10.9 s for the web container.
- **Diagnosis:** Docker sends SIGTERM, waits 10 s, then SIGKILLs. The compose `command:` wrapped gunicorn in `sh -c`, so the shell was the parent process and never forwarded the signal.
- **Fix:** Added `exec` before `gunicorn`, so gunicorn replaces the shell and receives signals directly. The same idea is used in `entrypoint.sh` (`exec "$@"`).
- **Takeaway:** Slow shutdowns become slow, messy deploys on ECS. Whatever runs in the container should get the signals.

### 6. Gunicorn `WORKER TIMEOUT` with nobody using the app

- **Symptom:** Workers were being killed and rebooted on their own. The traceback ended in `sock.recv` inside gunicorn's HTTP parser.
- **Diagnosis:** A client opened a TCP connection and never sent a request. Browsers do this (speculative pre-connects), and ALBs hold idle connections to targets too. Gunicorn's default **sync** workers handle one connection each, so an idle socket ties up a whole worker until the 30 s timeout.
- **Fix:** Switched to threaded workers: `--worker-class gthread --threads 4`, applied in the Dockerfile, compose and the ECS task definition.
- **Takeaway:** This is also the root of the guide's "summarize times out under concurrency" warning. With sync workers, any slow request blocks a worker, and a few concurrent ones queue everything.

---

## The big one: the app was never on Postgres

### 7. Settings were hardcoded, and everything silently ran on SQLite

- **Symptom:** None. Compose "worked", CI was green, and the Postgres containers were healthy. It surfaced only while reviewing how `ALLOWED_HOSTS` would behave behind the ALB.
- **Diagnosis:** `notesy/settings.py` hardcoded `SECRET_KEY`, `DEBUG = True`, `ALLOWED_HOSTS = ["*"]`, and a SQLite `DATABASES`. Every environment variable we set in Compose, CI and ECS had been ignored. Tests in CI ran on SQLite despite the Postgres service container. On ECS, each task would have had its own throwaway database.
- **Fix (ticket NOTESY-101):**
  - All config comes from the environment. `DEBUG` is off unless explicitly enabled.
  - The app refuses to start without `DJANGO_SECRET_KEY` or `DATABASE_URL` when `DEBUG` is off, so a missing value fails loudly instead of falling back silently.
  - The database comes from `DATABASE_URL` (`dj-database-url` + `psycopg2`).
  - Sessions moved from files inside the container to the database.
  - WhiteNoise was added. It had been referenced in the Dockerfile but never enabled.
- **Proof:** `psql \dt` in the Compose Postgres container showed `auth_user`, `django_session`, `notes_note` and the rest.
- **Takeaway:** Green checks proved the pipeline ran, not that the app used what the pipeline provided. The fix makes misconfiguration impossible to miss.

### 8. ALB health checks vs `ALLOWED_HOSTS`

- **Symptom:** Prevented rather than hit. The generated Terraform "solved" it with `ALLOWED_HOSTS = "*"`.
- **Diagnosis:** ALB health checks send the **task's private IP** as the `Host` header. If `ALLOWED_HOSTS` only lists the ALB's DNS name, Django answers `400`, the target never goes healthy, and ECS keeps replacing the task. `*` avoids that by switching off host-header protection entirely.
- **Fix:** At startup, `settings.py` reads the task's own IP from the ECS metadata endpoint (`ECS_CONTAINER_METADATA_URI_V4`) and appends it. `DJANGO_ALLOWED_HOSTS` is set to the ALB DNS name only.
- **Takeaway:** Read generated infrastructure code before applying it. It will happily trade security for "it works".

---

## AWS auth (OIDC)

### 9. `Not authorized to perform sts:AssumeRoleWithWebIdentity`

- **Symptom:** The first ECR publish failed at the credentials step.
- **Diagnosis:** I ruled out each piece in turn: it was a push to `main`, the provider's audience was `sts.amazonaws.com`, the secret was re-saved, and the trust policy was verified with `get-role`. Then I added a temporary step that decoded the OIDC token and printed only its claims (`sub`, `aud`, `ref`, `repository`, never the token itself). GitHub was sending an **ID-pinned** subject, `repo:Owner@<owner-id>/repo@<repo-id>:ref:refs/heads/main`, not the older `repo:Owner/repo:...` format the trust policy expected.
- **Fix:** Updated the trust policy to the exact `sub` and removed the debug step.
- **Takeaway:** When a trust relationship fails, look at what the token actually says rather than what the docs say it should say. The IDs exist so a deleted-and-recreated repo with the same name can't assume your role.

### 10. Renaming the repo broke OIDC the next day

- **Symptom:** The same `Not authorized` error, on a pipeline that had worked the day before.
- **Diagnosis:** The repo had been renamed to `notesy-app`. The name is part of the `sub` claim (the numeric IDs don't change), so the trust policy no longer matched.
- **Fix:** Updated the name in the trust policy (later moved into Terraform) and updated the local git remote.
- **Takeaway:** Renames and transfers silently break OIDC trust. It's worth a line in any runbook.

---

## JFrog

### 11. Self-hosted Artifactory couldn't host Docker images

- **Symptom:** "Docker" was listed as a package type but couldn't be selected.
- **Diagnosis:** The instance is **Artifactory OSS**, which lists every type but only supports a few. Docker isn't one of them. JFrog Cloud's free tier needed a company email.
- **Fix:** Used a **Generic** repository and pushed the image itself as a tarball (`docker save`). It's the exact image that goes to ECR, byte for byte, and restorable with `docker load`.
- **Takeaway:** The requirement was "the same build in both registries", so the solution kept that property instead of substituting a different artifact.

### 12. A push token was exposed in chat

- **Symptom:** The `ci-notesy` token was pasted into a conversation.
- **Fix:** Revoked it, generated a new one, and from then on only entered tokens via `read -s` or directly into GitHub Secrets.
- **Takeaway:** Treat any secret that leaves its intended home as compromised. Rotating is cheap; guessing is not.

### 13. `403` on the second JFrog upload

- **Symptom:** The SHA-named upload succeeded; the `latest` upload failed with `403`.
- **Diagnosis:** `latest/notesy-latest.tar.gz` already existed. Replacing a file in Artifactory needs **Delete/Overwrite** permission, but `ci-notesy` only had Read and Deploy.
- **Fix:** Granted Delete/Overwrite on `notesy-repo` only.
- **Takeaways:**
  - `curl --fail` is why this surfaced. Without it the step would have gone green with a stale `latest`.
  - This was the guide's "one registry succeeds, the other fails" scenario for real. Because publishing is split into separate jobs with the tarball handed off as an artifact, recovery was **Re-run failed jobs**: no rebuild, no second push to ECR.

---

## Terraform / ECS

### 14. Generated Terraform would have deleted the image registry on every teardown

- **Symptom:** Caught in plan review. The plan imported the existing ECR repository with `force_delete = true` and created a second GitHub OIDC role.
- **Diagnosis:** With per-session `terraform destroy`, that meant wiping the repository and every image each time, plus two roles doing one job.
- **Fix:** A deliberate decision to keep **one stack that destroys everything billable**: ECR and the pipeline role are owned by Terraform, the service starts at 0 tasks, and the pipeline deploys and scales it. The hand-made repository and role were deleted first so Terraform could own the names.
- **Takeaway:** "Destroy everything" is a valid choice, but it's a choice. Image history resets every session, and the role ARN stays stable because the role name is fixed.

### 15. The deployed app had no login

- **Symptom:** The app was live behind the ALB with no working credentials.
- **Diagnosis:** Intended behavior. `run_seed` defaults to `false`, so no known password sits on a public URL.
- **Fix:** Ran `manage.py seed` once as a **one-off ECS task** (same image and network, overridden command) to create `demo/demo` for testing.
- **Takeaway:** Admin commands run as one-off tasks; the running service stays untouched.

---

## Smaller ones

- **`requests==2.20.0`:** a 2018 release with known CVEs, invisible because Trivy runs with `exit-code: "0"`. Upgraded to `>=2.32`.
- **`manage.py check` in CI:** needed `DJANGO_SECRET_KEY` and `DATABASE_URL` once settings started enforcing them. I added throwaway values to the `build` job's env.
- **`collectstatic` at build time:** needs the same, passed inline on the `RUN` line so neither value persists in the image's environment. The build-only secret is visible in `docker history`, which is fine because it's a throwaway. That's the answer to "a value you thought was runtime-only is in the build history".
- **Node 20 deprecation warning** on `aws-actions/configure-aws-credentials@v4`. It's harmless and still runs on Node 24. The fix is to bump the action's major version.

---

## Verification that closed Milestone 4

The commit on `main`, the image tag in ECR, and the image in the running task definition were all `6d0ffa5267beb363d843dc9ae00185c01efac681`. The exact build the pipeline published is the one serving traffic.