# Kubernetes cost review

These are the ten questions I walk when I review a cloud or Kubernetes estate. The invoice is late evidence. The causes sit in architecture, defaults, and habit.

The questions are the ones in [Cloud cost is an engineering problem](https://shafie.dev/notes/cloud-cost-is-an-engineering-problem/). Under each question is what `k8s-cost-review` can see in one cluster, and what it cannot.

1. **Can you attribute most of the bill to a team, a service, and an environment?**
   If resources are not labelled that way, the bill is a single number, and a single number gets a single reaction: cut something. The script cannot invent an owner from a namespace name.

2. **Is there a single owner for each large line item, and do they see the cost without asking finance?**
   I want showback before any argument about chargeback. People change what they can see next to the service they run. They do not change a spreadsheet that arrives once a quarter. kubectl cannot answer this.

3. **Are non-production environments sized and scheduled as non-production, or do they run like production all week?**
   Production, staging, development, and sandbox should not cost as if they were the same thing. Non-production can sleep at night and on weekends. The script flags a namespace whose name says non-production and whose requests are at least as high as production. It does not know the schedule. That part lives in Git, or in a console.

4. **Do you have unattached disks, unused IPs, idle load balancers, old snapshots, or forgotten clusters?**
   This is the waste you can see from across the room. In the cluster you point it at, the script looks for LoadBalancer services with no ready backend, and for persistent volumes and claims that are unbound or unused. IPs, snapshots, and a second forgotten cluster are outside kubectl.

5. **Are Kubernetes requests and limits based on observed use, or copied from a template that felt safe?**
   Requests copied "just to be safe" are the waste you do not see from across the room. The script lists containers with missing requests or limits, and containers where the limit sits far from the request. When metrics exist, it also lists workloads whose requests sit far from observed usage. A guess is not a measurement.

6. **Does autoscaling scale in as reliably as it scales out?**
   Autoscaling that only grows is a habit, not a design. One pod list cannot show that history. Look at the scaler.

7. **Is data transfer a visible number, and do you know which services cause it?**
   Traffic between zones, or out to the internet, often never appears on the diagram. The script does not see the network bill.

8. **Have you measured before buying reserved or committed capacity?**
   A commitment on the wrong size locks the waste in. Make the usage honest first. The script will not recommend a reservation.

9. **Do cost controls have a reliability check: what is the objective, and what happens at peak?**
   I will not squeeze a service so a report looks tidy. Headroom that holds a latency target is part of the design. A permanent surplus, bought because autoscaling is not trusted, is a habit. Keep the objective in the room before anyone removes capacity.

10. **Is the desired size and schedule of infrastructure in Git, or only in a console from last year?**
    If you already use infrastructure as code and GitOps, the desired state can include a size, a schedule, and a lifetime. The script reads the live cluster, not the repository that should have defined it.

If you cannot answer the first two, start there. Optimising a bill you cannot explain is guesswork.

The script is a way to walk questions 3, 4, and 5 against one cluster. It is not a substitute for the rest. The order I follow in a review is in the README, under "How I use this in a review".
