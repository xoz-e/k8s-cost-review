include "quantities";

def items($doc): $doc[0].items // [];
def pods: items($pods);
def namespaces: items($namespaces);
def services: items($services);
def endpoints: items($endpoints);
def pvs: items($pvs);
def pvcs: items($pvcs);
def metric_rows: $metrics[0] // [];

def cell($v):
  ($v | tostring) | gsub("\\|"; "/") | gsub("[\n\r\t]"; " ");

def rule($header):
  $header
  | split("|")
  | map(select(length > 0))
  | map("| --- ")
  | join("")
  | . + "|";

def table($header; $rows):
  if ($rows | length) == 0 then
    "None."
  else
    ([ $header, rule($header) ] + $rows) | join("\n")
  end;

def active_phase($p):
  ($p.status.phase // "") as $phase
  | ($phase == "Running" or $phase == "Pending" or $phase == "Unknown");

def req_of($c; $side; $key):
  (($c.resources // {}) | .[$side] // {}) | .[$key] // null
  | if . == "" then null else . end;

def ns_class($name):
  ($name | ascii_downcase) as $n
  | if ($n | test("(^|[-_])non-?prod([-_]|$)")) then "nonprod"
    elif ($n | test("(^|[-_])(dev|develop|development|staging|stage|stg|test|testing|qa|uat|sandbox|demo|lab|preview|ephemeral|ci)([-_]|$)")) then "nonprod"
    elif ($n | test("(^|[-_])(prod|production|prd|live)([-_]|$)")) then "prod"
    else "other"
    end;

def system_ns($name):
  $name == "kube-system" or $name == "kube-public" or $name == "kube-node-lease";

def fmt_cpu($m):
  if $m == null then "-"
  else "\($m | round)m"
  end;

def fmt_mem($b):
  if $b == null then "-"
  else "\((($b / 1048576) | round))Mi"
  end;

def parsed_cpu($raw):
  if $raw == null then {state: "missing"}
  else
    ($raw | cpu_m) as $v
    | if $v == null then {state: "bad", raw: $raw}
      else {state: "ok", value: ($v | round)}
      end
  end;

def parsed_mem($raw):
  if $raw == null then {state: "missing"}
  else
    ($raw | mem_bytes) as $v
    | if $v == null then {state: "bad", raw: $raw}
      else {state: "ok", value: ($v | round)}
      end
  end;

def resource_issues($c):
  parsed_cpu(req_of($c; "requests"; "cpu")) as $cr
  | parsed_mem(req_of($c; "requests"; "memory")) as $mr
  | parsed_cpu(req_of($c; "limits"; "cpu")) as $cl
  | parsed_mem(req_of($c; "limits"; "memory")) as $ml
  | [
      (if $cr.state == "missing" then "no cpu request"
       elif $cr.state == "bad" then "unparsed cpu request"
       elif $cr.value == 0 then "cpu request is zero"
       elif $cr.value >= $large_cpu then "cpu request is large"
       else empty end),
      (if $mr.state == "missing" then "no memory request"
       elif $mr.state == "bad" then "unparsed memory request"
       elif $mr.value == 0 then "memory request is zero"
       elif $mr.value >= $large_mem then "memory request is large"
       else empty end),
      (if $cl.state == "missing" then "no cpu limit"
       elif $cl.state == "bad" then "unparsed cpu limit"
       elif $cl.value == 0 then "cpu limit is zero"
       else empty end),
      (if $ml.state == "missing" then "no memory limit"
       elif $ml.state == "bad" then "unparsed memory limit"
       elif $ml.value == 0 then "memory limit is zero"
       else empty end),
      (if ($cr.state == "ok" and $cl.state == "ok" and $cr.value > 0 and $cl.value >= ($ratio * $cr.value))
       then "cpu limit far above request" else empty end),
      (if ($mr.state == "ok" and $ml.state == "ok" and $mr.value > 0 and $ml.value >= ($ratio * $mr.value))
       then "memory limit far above request" else empty end)
    ];

def pod_dim($p; $kind):
  reduce ($p.spec.containers // [])[] as $c (
    {sum: 0, complete: true};
    (if $kind == "cpu" then parsed_cpu(req_of($c; "requests"; "cpu"))
     else parsed_mem(req_of($c; "requests"; "memory")) end) as $q
    | if $q.state == "ok" then .sum += $q.value
      else .complete = false
      end
  );

def ns_dim($ns; $kind):
  reduce (pods[] | select(.metadata.namespace == $ns and active_phase(.))) as $p (
    {sum: 0, complete: true};
    pod_dim($p; $kind) as $d
    | .sum += $d.sum
    | if $d.complete then . else .complete = false end
  );

def fmt_dim($sum; $complete; $kind):
  (if $kind == "cpu" then fmt_cpu($sum) else fmt_mem($sum) end) as $text
  | if $complete then $text else "\($text), some pods have no request" end;

def resources_section:
  [
    pods[]
    | select(active_phase(.))
    | . as $p
    | ($p.spec.containers // [])[]
    | resource_issues(.) as $issues
    | select(($issues | length) > 0)
    | {
        namespace: $p.metadata.namespace,
        pod: $p.metadata.name,
        container: .name,
        issues: ($issues | join(", "))
      }
  ]
  | sort_by(.namespace, .pod, .container)
  | map("| \(cell(.namespace)) | \(cell(.pod)) | \(cell(.container)) | \(cell(.issues)) |");

def idle_section:
  [
    namespaces[].metadata.name
    | select(system_ns(.) | not)
    | . as $ns
    | [ pods[] | select(.metadata.namespace == $ns and active_phase(.)) ] as $running
    | [ pods[] | select(.metadata.namespace == $ns and (active_phase(.) | not)) ] as $other
    | select(($running | length) == 0)
    | {
        namespace: $ns,
        running: ($running | length),
        other: ($other | length),
        note: (if ($other | length) == 0 then "no pods" else "nothing running" end)
      }
  ]
  | sort_by(.namespace)
  | map("| \(cell(.namespace)) | \(.running) | \(.other) | \(cell(.note)) |");

def classed($name):
  ns_dim($name; "cpu") as $cpu
  | ns_dim($name; "mem") as $mem
  | {
      name: $name,
      class: ns_class($name),
      cpu: $cpu.sum,
      mem: $mem.sum,
      cpu_ok: $cpu.complete,
      mem_ok: $mem.complete
    };

def nonprod_section:
  [ namespaces[].metadata.name | classed(.) | select(.class == "prod") ]
  | sort_by(.cpu, .mem, .name) as $prods
  | [ namespaces[].metadata.name | classed(.) | select(.class == "nonprod") ]
  | sort_by(.name) as $nonprods
  | if ($prods | length) == 0 then
      "No namespace matches the production name heuristic (prod, production, prd, live), so nothing is marked as sized like production."
    elif ($prods[0].cpu == 0 and $prods[0].mem == 0) then
      "The smallest production namespace has no CPU or memory requests, so nothing is marked as sized like production."
    else
      $prods[0] as $base
      | [
          $nonprods[]
          | select((.cpu > 0 or .mem > 0) and .cpu >= $base.cpu and .mem >= $base.mem)
          | "| \(cell(.name)) | \(cell(fmt_dim(.cpu; .cpu_ok; "cpu"))) | \(cell(fmt_dim(.mem; .mem_ok; "mem"))) | \(cell($base.name)) | \(cell(fmt_cpu($base.cpu))) | \(cell(fmt_mem($base.mem))) |"
        ] as $rows
      | table("| Namespace | CPU requests | Memory requests | Baseline | Baseline CPU | Baseline memory |"; $rows)
    end;

def ready_backends($ns; $name):
  if $epkind == "slices" then
    [ endpoints[]
      | select(.metadata.namespace == $ns)
      | select((.metadata.labels["kubernetes.io/service-name"] // "") == $name)
      | (.endpoints // [])[]
      | select((.conditions.ready // false) == true)
    ] | length
  elif $epkind == "endpoints" then
    [ endpoints[]
      | select(.metadata.namespace == $ns and .metadata.name == $name)
      | (.subsets // [])[]
      | (.addresses // [])[]
    ] | length
  else
    null
  end;

def lb_ips($svc):
  [ ($svc.status.loadBalancer.ingress // [])[] | (.ip // .hostname // empty) ]
  | unique
  | if length == 0 then "-" else join(", ") end;

def lb_section:
  [
    services[]
    | select((.spec.type // "") == "LoadBalancer")
    | . as $svc
    | ($svc.metadata.namespace) as $ns
    | ($svc.metadata.name) as $name
    | ready_backends($ns; $name) as $ready
    | select($ready == 0)
    | "| \(cell($ns)) | \(cell($name)) | \(cell(lb_ips($svc))) | no ready backends |"
  ]
  | sort;

def pv_rows:
  [
    pvs[]
    | . as $pv
    | ($pv.status.phase // "") as $phase
    | select($phase == "Available" or $phase == "Released" or $phase == "Failed")
    | ($pv.spec.claimRef) as $ref
    | {
        kind: "PV",
        name: $pv.metadata.name,
        state: $phase,
        size: ($pv.spec.capacity.storage // "-"),
        note: (
          if $ref == null or ($ref.name // "") == "" then "no claim"
          else "was \($ref.namespace // "-")/\($ref.name)"
          end
        )
      }
  ];

def used_claim($ns; $name):
  any(
    pods[];
    active_phase(.)
    and .metadata.namespace == $ns
    and any(
      (.spec.volumes // [])[];
      ((.persistentVolumeClaim // null) != null) and .persistentVolumeClaim.claimName == $name
    )
  );

def pvc_rows:
  [
    pvcs[]
    | . as $pvc
    | ($pvc.metadata.namespace) as $ns
    | ($pvc.metadata.name) as $name
    | ($pvc.status.phase // "") as $phase
    | ($pvc.spec.resources.requests.storage // "-") as $size
    | if ($phase == "Pending" or $phase == "Lost" or ($phase == "Bound" and (used_claim($ns; $name) | not))) then
        {
          kind: "PVC",
          name: "\($ns)/\($name)",
          state: (if $phase == "" then "-" else $phase end),
          size: $size,
          note: (
            if $phase == "Pending" then "unbound"
            elif $phase == "Lost" then "lost its volume"
            else "no running pod mounts it"
            end
          )
        }
      else
        empty
      end
  ];

def volume_rows:
  (if $pv_ok == 1 then pv_rows else [] end)
  + (if $pvc_ok == 1 then pvc_rows else [] end)
  | sort_by(.kind, .name)
  | map("| \(cell(.name)) | \(.kind) | \(cell(.state)) | \(cell(.size)) | \(cell(.note)) |");

def image_registry($image):
  ($image
    | if test("@") then sub("@.*$"; "") else . end
  ) as $no_digest
  | (if ($no_digest | test(":[^/]+$")) then ($no_digest | sub(":[^/]+$"; "")) else $no_digest end) as $ref
  | ($ref | split("/")[0]) as $first
  | if ($ref | contains("/")) and (($first | test("[.:]")) or $first == "localhost") then
      $first | ascii_downcase
    else
      "docker.io"
    end;

def is_public($reg):
  ($reg == "docker.io"
    or $reg == "index.docker.io"
    or $reg == "registry-1.docker.io"
    or $reg == "ghcr.io"
    or $reg == "quay.io"
    or $reg == "gcr.io"
    or $reg == "k8s.gcr.io"
    or $reg == "registry.k8s.io"
    or $reg == "public.ecr.aws"
    or $reg == "mcr.microsoft.com"
    or ($reg | test("(^|[.])gcr[.]io$")));

def is_internal($reg):
  any($registries[]; . as $allowed | $reg == $allowed or ($reg | endswith("." + $allowed)));

def image_rows:
  [
    pods[]
    | select(active_phase(.))
    | . as $p
    | ($p.spec.containers // [])[]
    | . as $c
    | image_registry($c.image) as $reg
    | select(
        if ($registries | length) == 0 then is_public($reg)
        else (is_internal($reg) | not)
        end
      )
    | {
        namespace: $p.metadata.namespace,
        pod: $p.metadata.name,
        container: $c.name,
        image: $c.image,
        registry: $reg,
        note: (if is_public($reg) then "public registry" else "outside the configured mirror" end)
      }
  ]
  | sort_by(.namespace, .pod, .container)
  | map("| \(cell(.namespace)) | \(cell(.pod)) | \(cell(.container)) | \(cell(.image)) | \(cell(.registry)) | \(cell(.note)) |");

def metric_for($ns; $pod):
  first(metric_rows[] | select(.namespace == $ns and .pod == $pod));

def rightsizing_rows:
  [
    pods[]
    | select(active_phase(.))
    | . as $p
    | metric_for($p.metadata.namespace; $p.metadata.name) as $m
    | select($m != null)
    | pod_dim($p; "cpu") as $cpu
    | pod_dim($p; "mem") as $mem
    | (if $cpu.complete then $cpu.sum else null end) as $cpu_req
    | (if $mem.complete then $mem.sum else null end) as $mem_req
    | $m.cpu_m as $cpu_obs
    | $m.mem_bytes as $mem_obs
    | ($cpu_req != null and $cpu_obs != null and $cpu_req >= $over_min_cpu and $cpu_req >= ($over_ratio * $cpu_obs)) as $cpu_over
    | ($mem_req != null and $mem_obs != null and $mem_req >= $over_min_mem and $mem_req >= ($over_ratio * $mem_obs)) as $mem_over
    | ($cpu_req != null and $cpu_obs != null and $cpu_obs >= ($cpu_req + $under_cpu)) as $cpu_under
    | ($mem_req != null and $mem_obs != null and $mem_obs >= ($mem_req + $under_mem)) as $mem_under
    | select($cpu_over or $mem_over or $cpu_under or $mem_under)
    | [
        (if $cpu_over and $mem_over then "request well above usage"
         elif $cpu_over then "cpu request well above usage"
         elif $mem_over then "memory request well above usage"
         else empty end),
        (if $cpu_under and $mem_under then "usage above request"
         elif $cpu_under then "cpu usage above request"
         elif $mem_under then "memory usage above request"
         else empty end)
      ] as $notes
      | {
          namespace: $p.metadata.namespace,
          pod: $p.metadata.name,
          cpu_req: $cpu_req,
          cpu_obs: $cpu_obs,
          mem_req: $mem_req,
          mem_obs: $mem_obs,
          note: ($notes | map(select(. != null)) | join(", "))
        }
  ]
  | sort_by(.namespace, .pod)
  | map("| \(cell(.namespace)) | \(cell(.pod)) | \(cell(fmt_cpu(.cpu_req))) | \(cell(fmt_cpu(.cpu_obs))) | \(cell(fmt_mem(.mem_req))) | \(cell(fmt_mem(.mem_obs))) | \(cell(.note)) |");

def resources_intro:
  "Running and pending containers. A CPU request at or above \($large_cpu)m, or a memory request at or above \($large_mem_gi)Gi, is large. A limit at least \($ratio) times its request is far apart.";

def idle_intro:
  "No Running or Pending pods. kube-system, kube-public, and kube-node-lease are skipped.";

def nonprod_intro:
  "Production names use the token prod, production, prd, or live. Non-production names use dev, staging, stage, test, qa, uat, sandbox, demo, lab, preview, or ci. A name with nonprod is non-production. A non-production namespace is listed when the CPU requests and the memory requests of its running pods are both at least as high as the smallest production namespace.";

def lb_intro:
  "Services of type LoadBalancer with no ready backend. Load balancers that have one are omitted.";

def volume_intro:
  "Available, Released, and Failed volumes. Pending and Lost claims. Bound claims that no Running or Pending pod mounts.";

def image_intro:
  if ($registries | length) == 0 then
    "No internal mirror was configured. Well-known public registries are listed."
  else
    "Internal mirror: \($registries | join(", ")). Any other registry is listed. Public registries are marked as such."
  end;

def rightsizing_intro:
  "Listed when the request is at least \($over_ratio) times the observed value, and the request is at least \($over_min_cpu)m of CPU or \($over_min_mem_mi)Mi of memory. Also listed when observed usage exceeds the request by at least \($under_cpu)m of CPU or \($under_mem_mi)Mi of memory. A missing request on that dimension is left out. Do not resize from this table alone.";

def section_block($title; $intro; $body):
  if $body == "" then
    "## \($title)\n\n\($intro)"
  else
    "## \($title)\n\n\($intro)\n\n\($body)"
  end;

def errline($what; $err):
  "Could not list \($what) (\(cell($err))).";

if $section == "resources" then
  section_block(
    "Pods with missing or extreme requests and limits";
    resources_intro;
    table("| Namespace | Pod | Container | What is wrong |"; resources_section)
  )
elif $section == "idle" then
  section_block(
    "Idle namespaces";
    idle_intro;
    table("| Namespace | Running or pending | Other pods | Note |"; idle_section)
  )
elif $section == "nonprod" then
  section_block(
    "Non-production namespaces sized like production";
    nonprod_intro;
    nonprod_section
  )
elif $section == "lb" then
  section_block(
    "Unused LoadBalancer services";
    lb_intro;
    if $svc_ok == 0 then errline("services"; $svc_err)
    elif $ep_ok == 0 then errline("endpoints"; $ep_err) + " LoadBalancer services were not classified."
    else table("| Namespace | Service | Address | Note |"; lb_section)
    end
  )
elif $section == "volumes" then
  section_block(
    "Unbound or unused volumes";
    volume_intro;
    (
      [
        (if $pv_ok == 0 then errline("persistent volumes"; $pv_err) else empty end),
        (if $pvc_ok == 0 then errline("persistent volume claims"; $pvc_err) else empty end),
        (if $pv_ok == 0 and $pvc_ok == 0 then empty
         else table("| Name | Kind | State | Size | Note |"; volume_rows)
         end)
      ] | join("\n\n")
    )
  )
elif $section == "images" then
  section_block(
    "Images pulled from public registries";
    image_intro;
    table("| Namespace | Pod | Container | Image | Registry | Note |"; image_rows)
  )
elif $section == "rightsizing" then
  if $have_metrics == 0 then
    section_block(
      "Workloads never rightsized";
      "Skipped. metrics-server did not return pod metrics, and Prometheus was not reachable. Rightsizing waits on a measurement.";
      ""
    )
  else
    section_block(
      "Workloads never rightsized";
      ($metrics_note + "\n\n" + rightsizing_intro);
      table("| Namespace | Pod | CPU request | CPU observed | Memory request | Memory observed | Note |"; rightsizing_rows)
    )
  end
else
  error("unknown section \($section)")
end
