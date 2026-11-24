include "quantities";

def series($doc):
  [ ($doc[0].data.result // [])[]
    | {
        namespace: (.metric.namespace // null),
        pod: (.metric.pod // null),
        value: (try (.value[1] | tonumber) catch null)
      }
    | select(.namespace != null and .pod != null and .value != null)
  ];

def join_series($cpu; $mem):
  reduce ($cpu[] | . + {k: (.namespace + "\u0000" + .pod)}) as $r
    ({};
      .[$r.k] = {
        namespace: $r.namespace,
        pod: $r.pod,
        cpu_m: (($r.value * 1000) | round),
        mem_bytes: null
      }
    )
  | reduce ($mem[] | . + {k: (.namespace + "\u0000" + .pod)}) as $r
    (.;
      if .[$r.k] == null then
        .[$r.k] = {
          namespace: $r.namespace,
          pod: $r.pod,
          cpu_m: null,
          mem_bytes: ($r.value | round)
        }
      else
        .[$r.k].mem_bytes = ($r.value | round)
      end
    )
  | [ .[] ];

def from_top($text):
  [ $text
    | split("\n")[]
    | select(length > 0)
    | split(" ")
    | map(select(length > 0))
    | select(length >= 4)
    | select(.[0] != "NAMESPACE")
    | {
        namespace: .[0],
        pod: .[1],
        cpu_m: (.[2] | cpu_m | if . == null then null else round end),
        mem_bytes: (.[3] | mem_bytes | if . == null then null else round end)
      }
  ];

if $source == "prom" then
  join_series(series($cpu); series($mem))
elif $source == "top" then
  from_top($top)
else
  error("unknown metrics source")
end
