# k8s-cost-review

A read-only look at a Kubernetes cluster you already have. It prints the things that usually explain a cloud bill: requests and limits with no basis, idle namespaces, non-production sized like production, LoadBalancer services with nothing behind them, leftover volumes, images that did not come from an internal mirror, and requests that sit far from observed usage.

It does not price any of that. The questions I walk in a review are in [docs/checklist.md](docs/checklist.md). The same list in Persian is [docs/checklist.fa.md](docs/checklist.fa.md). Both follow [Cloud cost is an engineering problem](https://shafie.dev/notes/cloud-cost-is-an-engineering-problem/).

Hamidreza Shafie. DevOps, DevSecOps, and platform engineering. CKA.

## Install

You need `bash`, `kubectl` pointed at the cluster, and `jq`. Metrics are optional.

```bash
git clone https://github.com/xoz-e/k8s-cost-review.git
cd k8s-cost-review
./bin/k8s-cost-review
```

The script uses your current kubeconfig. It calls `kubectl get`, `kubectl top` when metrics-server answers, and a Prometheus query when Prometheus answers. The account needs get on pods, namespaces, services, endpointslices (or endpoints), persistentvolumes, and persistentvolumeclaims. Metrics and the Prometheus service proxy are optional. If they are missing, that section is skipped and the rest of the report still runs.

## Usage

```bash
./bin/k8s-cost-review --context prod --internal-registry registry.internal.example
./bin/k8s-cost-review --prometheus-url http://127.0.0.1:9090 --prom-range 7d
```

`--internal-registry` may be repeated, or given as a comma-separated list. An image counts as internal when its registry host is that value, or a subdomain of it. Without the flag, the image section only lists well-known public registries.

If `--prometheus-url` is omitted, the script looks for a Service named `prometheus`, `prometheus-k8s`, or `prometheus-operated` and queries it through the API server. The query is an average over the range (default `7d`). If the range query fails, it retries an instant query. If Prometheus is not there, it tries `kubectl top`. `kubectl top` is one sample, and the report says so.

`make check` runs shellcheck and a dry run against the mock cluster in `test/`. That needs shellcheck and jq, and it does not need a cluster.

## How I use this in a review

Visibility first. If a namespace cannot be tied to a team, a service, and an environment, I do not start by resizing it. The first two questions on the checklist are the start of the review. The script will not invent an owner.

Treat non-prod as non-prod. A staging namespace whose requests sit at or above production is the finding. So is a demo that never went away. Non-production can sleep, and it can be smaller. I do not buy a commitment for capacity that is only large because nobody owns the schedule.

Rightsize after measuring. A missing request is something I will say in the review. A request far from usage is only a candidate, and only when metrics-server or Prometheus actually returned data. I want a window, and I want the reliability target in the same conversation. Headroom that keeps a service inside its objective is design. I will not cut it to make this report shorter.

Reserved capacity last. Idle namespaces, unused load balancers, and leftover volumes come off first. Requests get an honest size second. What is still running, all week, is the baseline you might commit to. A reservation on the wrong size locks the waste in.

## Sample output

The full fixture is [examples/sample-report.md](examples/sample-report.md). It is fictional. This is the shape of two sections:

```markdown
## Idle namespaces

| Namespace | Running or pending | Other pods | Note |
| --- | --- | --- | --- |
| dev | 0 | 1 | nothing running |
| sandbox | 0 | 0 | no pods |
```

```markdown
## Workloads never rightsized

| Namespace | Pod | CPU request | CPU observed | Memory request | Memory observed | Note |
| --- | --- | --- | --- | --- | --- | --- |
| legacy | cache-0 | 100m | 180m | 128Mi | 100Mi | cpu usage above request |
| staging | api-bb12 | 2000m | 40m | 4096Mi | 100Mi | request well above usage |
```

## What it does not do

- It does not call a pricing API, and it does not turn CPU, memory, or disk into money.
- It does not change the cluster. There is no create, apply, delete, patch, scale, or exec in the script.
- It does not know which team owns a namespace. Attribution is the checklist.
- It does not see data transfer, unused public IPs, old snapshots, or a forgotten cluster in another account.
- It does not show whether autoscaling scales in. That needs history.
- It does not recommend reserved or committed capacity.
- It does not resize a workload from one sample.

## به فارسی

یک چک‌لیست و یک اسکریپت کوچک برای بازبینی هزینه Kubernetes. از این گزارش قیمت درنمی‌آید، داشبورد ندارد، و در کلاستر فقط می‌خواند.

ده سوال این‌جا است: [docs/checklist.fa.md](docs/checklist.fa.md). وقتی خودم در یک بازبینی از این ابزار استفاده می‌کنم، ترتیب ثابت است. اول باید معلوم باشد هزینه مال کدام تیم و کدام سرویس است. بعد محیط غیر production را کوچک‌تر و، اگر لازم است، خاموش نگه می‌دارم. rightsizing را بعد از اندازه‌گیری می‌گویم. ظرفیت reserved آخرین حرف است، وقتی مصرف دیگر حدسی نیست.

اجرا `bash`، `kubectl` و `jq` می‌خواهد. اگر metrics-server یا Prometheus نباشد، همان بخش rightsizing کنار می‌رود و بقیه گزارش می‌آید.

حمیدرضا شفیعی — [یادداشت](https://shafie.dev/notes/cloud-cost-is-an-engineering-problem/)
