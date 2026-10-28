# Diagnosis: intermittent HTTP 5xx after release (PayTrack API)

## 1. Leading hypothesis and supporting evidence

**A new-release startup dependency check aborts boot when the downstream
reconciliation service is unreachable, so new pods crash-loop and never become
Ready; the rollout is stuck mid-way and traffic health depends on which pods
are currently in Service endpoints.**

Evidence chain (in the order it appears in `incident.md`):

| Evidence | What it tells us |
|---|---|
| 5xx starts 10:08, release at 10:05 | Strong temporal correlation: new release is suspect #1 |
| `Readiness probe failed ... statuscode: 503` at 10:07:41 | The app (or its dependency check) answers /ready with 503 — kubelet correctly keeps the pod **out of Service endpoints**. `Running` ≠ `Ready` ≠ serving |
| `startup_check ... unavailable` then `server startup aborted` | New version fails **fast**: if the dependency is down at boot, the process exits instead of serving |
| `Back-off restarting failed container` + 2 restarts | CrashLoopBackOff pattern: start → dependency check fails → exit → restart with backoff |
| Rollout not completed | Old ReplicaSet still partially serving, new pods never Ready — cluster is in a mixed, degraded state |
| Previous image still available | Rollback is cheap and fast — the decisive argument for rollback (see §4) |

**Why "intermittent" rather than total outage:** readiness gating keeps the
crash-looping pods mostly out of endpoints, so old pods carry most traffic —
but endpoint updates during a stuck rollout (pods flapping Ready/NotReady,
endpoint slices propagating with delay) produce windows where some requests hit
a pod that is not actually able to serve → 5xx, while others succeed.

Secondary hypotheses I cannot yet rule out (and would check, in this order):

- **H2 — liveness kills slow startup:** liveness with a short
  `initialDelaySeconds` can kill a process that is still blocked in its
  startup check, producing the same BackOff loop without the dependency being
  the (only) killer. Evidence needed: container `lastState.terminated.exitCode`
  and whether /health was ever reachable.
- **H3 — resource pressure:** CPU throttling or OOM on small nodes makes the
  startup check time out intermittently even when the dependency is healthy.
- **H4 — downstream really is down** (not just slow): then this is *not* an
  application defect but the app's **reaction** (fail-fast abort) is what turns
  a dependency blip into a deployment outage.

## 2. Next checks / commands

Ordered cheapest-first, each one either confirms or kills a hypothesis:

```bash
# State of every pod: restarts, ready 0/1, age, node
kubectl -n paytrack get pods -o wide

# Events + last state/exit code of the crashing pod (H1 vs H2: exit reason, probe kills)
kubectl -n paytrack describe pod paytrack-api-6b7c9d7f9c-x2m4p

# The gold: logs of the PREVIOUS (crashed) container instance
kubectl -n paytrack logs paytrack-api-6b7c9d7f9c-x2m4p --previous

# Which pod IPs are actually receiving Service traffic right now
kubectl -n paytrack get endpoints paytrack-api -o yaml

# Rollout state and history: which image tag is current, which is pending
kubectl -n paytrack rollout status deploy/paytrack-api
kubectl -n paytrack rollout history deploy/paytrack-api

# Chronological event merge across the namespace (blip vs steady failures)
kubectl -n paytrack get events --sort-by=.lastTimestamp

# Resource view: throttling, memory spikes (H3)
kubectl top pods

# Dependency reachability FROM the pod network (networking vs downstream app):
#   timeout  -> routing/DNS/security group problem
#   refused  -> the downstream app itself is down
kubectl -n paytrack run tmp --rm -it --restart=Never --image=curlimages/curl -- \
  curl -sv http://<reconciliation-service>.paytrack.svc:8080/health

# DNS health (networking layer) + cluster capacity
kubectl -n kube-system get pods -l k8s-app=kube-dns
kubectl describe node | grep -A6 "Allocated resources"
```

## 3. Distinguishing application vs readiness vs resource vs networking

| Layer | Signature that isolates it |
|---|---|
| **Application** | `/health` returns 200 but request paths return 5xx with app stack traces in logs; old image on the same cluster behaves fine; downstream is healthy |
| **Readiness** | `/health` OK, `/ready` 503, pod absent from `get endpoints` → readiness is *correctly exposing* a real problem; the fix is the app/dependency, not the probe |
| **Resource** | `OOMKilled` (exit 137) or throttled CPU in `kubectl top`/describe; failures correlate with load or node pressure, not with the dependency's health |
| **Networking** | curl from inside the cluster times out (route/SG/DNS) while the downstream logs show no request ever arrived; CoreDNS pods unhealthy; failures on old *and* new image alike |

Key discriminator: run the same request from the old image's pod and from a
throwaway curl pod. Same failure everywhere → platform/dependency; only new
image → application.

## 4. When to roll back

**Impact first, root cause second.** The previous image is still available and
this is an internal API blocking operations staff, so:

- 5xx above baseline for **> ~5 minutes** in business hours, or rollout stuck
  longer than its own timeout with no readiness progress → `kubectl rollout
  undo` (or re-deploy the previous tag via CD) **now**, diagnose from logs and
  events afterwards.
- Do not roll back faster than a **2–3 minute** observation window: a single
  blip during a healthy rollout (endpoint propagation) is normal.
- Do not attempt config fixes ("restart the pod") while the crash-loop cause is
  unknown — restarting is exactly what kubelet already does.

## 5. Most valuable preventive improvements

1. **startupProbe** on slow-starting apps (its budget replaces liveness
   `initialDelaySeconds` guessing — liveness must never judge a starting app);
   the very manifests in `k8s/` learned this lesson.
2. **Real readiness semantics**: `/ready` must reflect the dependencies
   actually needed to serve — a static `{"ready": true}` (as in `app/app.py`)
   tells the Service nothing.
3. **Fail *retriable*, not fail-*fast*, at startup**: retry the dependency
   check with backoff for a bounded window (or serve a degraded 503 with
   `Retry-After`) instead of aborting the process — a dependency blip should
   not become a deployment outage.
4. **Progressive delivery**: canary/staged rollout with automatic rollback
   triggered by 5xx rate — turn "roll back within 5 minutes" into a policy the
   platform executes.
5. **Symptom-based alerting**: alert on *5xx rate* and *rollout stuck*
   (user-visible symptoms), not on pod restarts alone.
6. **PodDisruptionBudget + capacity headroom** so a stuck pod never equals a
   capacity crisis on a 2-node group.
