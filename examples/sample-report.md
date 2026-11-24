# Sample report

**Fictional.** This file is the output of `k8s-cost-review` against the fake cluster in `test/fixtures`. There is no such cluster. The names and quantities show the shape of each section. They are not measurements, and they are not from a real environment.

```bash
REVIEW_TIMESTAMP=2026-11-24T09:00:00Z \
  ./bin/k8s-cost-review --context demo --internal-registry registry.internal.example
```

The dry run points `KUBECTL` at `test/mock/kubectl`, which only serves those fixtures.

<!-- BEGIN REPORT -->
# Kubernetes cost review

| | |
| --- | --- |
| Context | demo |
| Collected | 2026-11-24T09:00:00Z |
| Mirror | registry.internal.example |
| Metrics | Prometheus monitoring/prometheus, average over 7d |
| Access | read-only |

Thresholds live at the top of the script. This report does not price anything.

## Pods with missing or extreme requests and limits

Running and pending containers. A CPU request at or above 8000m, or a memory request at or above 16Gi, is large. A limit at least 8 times its request is far apart.

| Namespace | Pod | Container | What is wrong |
| --- | --- | --- | --- |
| legacy | cache-0 | cache | cpu limit far above request, memory limit far above request |
| legacy | forgotten-0 | app | no cpu request, no memory request, no cpu limit, no memory limit |
| staging | batch-2k9 | batch | no cpu request, no memory request, no cpu limit, no memory limit |

## Idle namespaces

No Running or Pending pods. kube-system, kube-public, and kube-node-lease are skipped.

| Namespace | Running or pending | Other pods | Note |
| --- | --- | --- | --- |
| dev | 0 | 1 | nothing running |
| sandbox | 0 | 0 | no pods |

## Non-production namespaces sized like production

Production names use the token prod, production, prd, or live. Non-production names use dev, staging, stage, test, qa, uat, sandbox, demo, lab, preview, or ci. A name with nonprod is non-production. A non-production namespace is listed when the CPU requests and the memory requests of its running pods are both at least as high as the smallest production namespace.

| Namespace | CPU requests | Memory requests | Baseline | Baseline CPU | Baseline memory |
| --- | --- | --- | --- | --- | --- |
| staging | 2000m, some pods have no request | 4096Mi, some pods have no request | production | 500m | 512Mi |

## Unused LoadBalancer services

Services of type LoadBalancer with no ready backend. Load balancers that have one are omitted.

| Namespace | Service | Address | Note |
| --- | --- | --- | --- |
| legacy | old-edge | 203.0.113.30 | no ready backends |
| legacy | retired | 203.0.113.31 | no ready backends |

## Unbound or unused volumes

Available, Released, and Failed volumes. Pending and Lost claims. Bound claims that no Running or Pending pod mounts.

| Name | Kind | State | Size | Note |
| --- | --- | --- | --- | --- |
| pv-orphan | PV | Available | 50Gi | no claim |
| pv-released | PV | Released | 100Gi | was legacy/old-data |
| dev/job-tmp | PVC | Bound | 1Gi | no running pod mounts it |
| legacy/cache-data | PVC | Bound | 5Gi | no running pod mounts it |
| legacy/import | PVC | Pending | 20Gi | unbound |
| legacy/lost-disk | PVC | Lost | 10Gi | lost its volume |

## Images pulled from public registries

Internal mirror: registry.internal.example. Any other registry is listed. Public registries are marked as such.

| Namespace | Pod | Container | Image | Registry | Note |
| --- | --- | --- | --- | --- | --- |
| kube-system | coredns-a | coredns | registry.k8s.io/coredns/coredns:v1.11.1 | registry.k8s.io | public registry |
| legacy | forgotten-0 | app | quay.io/example/forgotten:0.1.0 | quay.io | public registry |
| staging | api-bb12 | api | ghcr.io/example/api:1.4.2 | ghcr.io | public registry |
| staging | batch-2k9 | batch | nginx:1.25 | docker.io | public registry |

## Workloads never rightsized

Source: Prometheus monitoring/prometheus, average over 7d.

Listed when the request is at least 4 times the observed value, and the request is at least 200m of CPU or 256Mi of memory. Also listed when observed usage exceeds the request by at least 50m of CPU or 64Mi of memory. A missing request on that dimension is left out. Do not resize from this table alone.

| Namespace | Pod | CPU request | CPU observed | Memory request | Memory observed | Note |
| --- | --- | --- | --- | --- | --- | --- |
| legacy | cache-0 | 100m | 180m | 128Mi | 100Mi | cpu usage above request |
| staging | api-bb12 | 2000m | 40m | 4096Mi | 100Mi | request well above usage |

---

Read-only. No prices. Questions about ownership, data transfer, scale-in, reservations, and what is in Git are in the checklist, not in this output.
