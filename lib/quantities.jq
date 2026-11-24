# Kubernetes CPU quantities as millicores, memory quantities as bytes.
# Null means missing or not a quantity we understand.

def cpu_m:
  if . == null then null
  elif type == "number" then . * 1000
  elif type != "string" or length == 0 then null
  elif test("^[0-9]+([.][0-9]+)?n$") then (sub("n$"; "") | tonumber) / 1000000
  elif test("^[0-9]+([.][0-9]+)?u$") then (sub("u$"; "") | tonumber) / 1000
  elif test("^[0-9]+([.][0-9]+)?m$") then (sub("m$"; "") | tonumber)
  elif test("^[0-9]+([.][0-9]+)?$") then (tonumber * 1000)
  else null
  end;

def mem_bytes:
  if . == null then null
  elif type == "number" then .
  elif type != "string" or length == 0 then null
  elif test("^[0-9]+([.][0-9]+)?Ki$") then (sub("Ki$"; "") | tonumber) * 1024
  elif test("^[0-9]+([.][0-9]+)?Mi$") then (sub("Mi$"; "") | tonumber) * 1048576
  elif test("^[0-9]+([.][0-9]+)?Gi$") then (sub("Gi$"; "") | tonumber) * 1073741824
  elif test("^[0-9]+([.][0-9]+)?Ti$") then (sub("Ti$"; "") | tonumber) * 1099511627776
  elif test("^[0-9]+([.][0-9]+)?Pi$") then (sub("Pi$"; "") | tonumber) * 1125899906842624
  elif test("^[0-9]+([.][0-9]+)?Ei$") then (sub("Ei$"; "") | tonumber) * 1152921504606846976
  elif test("^[0-9]+([.][0-9]+)?[kK]$") then (sub("[kK]$"; "") | tonumber) * 1000
  elif test("^[0-9]+([.][0-9]+)?M$") then (sub("M$"; "") | tonumber) * 1000000
  elif test("^[0-9]+([.][0-9]+)?G$") then (sub("G$"; "") | tonumber) * 1000000000
  elif test("^[0-9]+([.][0-9]+)?T$") then (sub("T$"; "") | tonumber) * 1000000000000
  elif test("^[0-9]+([.][0-9]+)?$") then tonumber
  else null
  end;
