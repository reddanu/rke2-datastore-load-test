# RKE2 datastore load test

A standalone Kubernetes lab harness for bounded HTTP CRUD traffic through
Traefik. A small Python API stores test records in SQLite on a dedicated PVC.
It does **not** benchmark raw disks, prove VM datastore placement, or measure
maximum datastore IOPS. No raw-device or host-filesystem stress test is included.

Use only on a lab cluster you are authorized to test. Writes can affect other
workloads sharing the storage backend. This API has no authentication and must
not be exposed publicly or used for real data.

## Requirements

- Bash, `kubectl` with Kustomize support, and a reachable lab context.
- Metrics Server (`kubectl top nodes`).
- A default StorageClass supporting `ReadWriteOnce`, or an explicitly selected
  StorageClass in [manifests/api.yaml](./manifests/api.yaml).
- Traefik with IngressClass `traefik` and an HTTP service at
  `rke2-traefik.kube-system.svc.cluster.local:80`.
  Change `TRAEFIK_URL` in [manifests/loadtest.js](./manifests/loadtest.js) if needed.
- At least one Ready, schedulable, untainted worker with
  `node-role.kubernetes.io/worker=true`. Both test pods require that label and
  exclude nodes labeled as control-plane, master, or etcd. They have no
  control-plane or system-worker taint tolerations.

## Run

Review [manifests/](./manifests/) before applying. The script requires an explicit
context and refuses to take over a namespace without its ownership label.

```sh
./scripts/run-load-test.sh YOUR_LAB_CONTEXT
```

The runner creates the `datastore-load-test` namespace, one API deployment, a
1-GiB PVC, an internal Traefik Ingress, and a one-off k6 Job.

- 10 CRUD iterations per second for 10 minutes (about 40 HTTP requests/second).
- Four requests per iteration: create, read, update, delete.
- Maximum 20 virtual users, bounded CPU/memory, and a 750-second Job deadline.
- Abort thresholds: HTTP failure rate >= 1% after 30 seconds or p95 latency
  >= 2 seconds after 60 seconds. Content checks must also pass.
- Static request names avoid per-record URL metric cardinality.

Traffic uses `Host: api.loadtest.test` against the internal Traefik service.
External DNS and an external load balancer are not required.

The runner records before/after node metrics, the Job status, and the k6 summary
under ignored `results/`. Review your own node and datastore monitoring during
the run. No environment reports or previous results ship with this project.
Local manifest/syntax and API smoke tests are not a substitute for validation
in your environment.

## Stop and cleanup

To stop only test load generation:

```sh
kubectl --context YOUR_LAB_CONTEXT -n datastore-load-test \
  delete job -l app.kubernetes.io/name=load-generator
```

After collecting metrics:

```sh
./scripts/cleanup-test.sh YOUR_LAB_CONTEXT
```

Cleanup verifies namespace ownership and requires typing the namespace name.
It deletes only the test namespace, including its PVC and data. PV deletion
depends on your StorageClass reclaim policy; inspect it before running.

This project contains generic examples only, with no company infrastructure
names, internal addresses, historical reports, or inherited Git history.
