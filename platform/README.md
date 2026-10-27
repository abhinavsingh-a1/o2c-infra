# platform: the local kind cluster

`platform/kind/` installs the platform on the kind cluster `o2c` (o2c-app ADR-017). The
cluster itself comes from o2c-app (`make cluster-up`).

| Script | Does |
|---|---|
| `bootstrap.sh` | Kyverno, Argo CD (pinned charts), a kindnet check, the root Application from o2c-gitops. Idempotent. |
| `secrets.sh <namespace>` | the credentials of one environment, from `o2c-app/.env` |
| `argocd-ui.sh` | port-forward to Argo CD: http://localhost:18081 |
| `teardown.sh` | removes the platform; the cluster stays |

Charts and their digests are pinned in `kind/lib.sh`; their settings are in
`kind/*-values.yaml`.

## No NetworkPolicies: kindnet loses DNS queries

**Symptom.** Argo CD fails DNS for minutes, for cluster names and external ones alike,
while a new pod resolves fine and CoreDNS logs nothing:
```
lookup github.com on 10.96.0.10:53: read udp 10.244.0.41:48571->10.96.0.10:53: i/o timeout
lookup argocd-repo-server on 10.96.0.10:53: dial udp 10.96.0.10:53: i/o timeout
```

**Cause.** kind's CNI, kindnet, enforces NetworkPolicies in userspace. For each pod that a
NetworkPolicy selects, the nftables table `inet kindnet-network-policies` sends every UDP
DNS query (chain `prerouting`) and the first packet of every new connection (chain
`postrouting`) to netfilter queue 101. The packet waits in the kernel until kindnet, a
userspace process, returns a verdict. Two things go wrong:
- kindnet loses verdicts: 665 to 882 packets sat in the queue without one, and its log
  shows `netlink receive: recvmsg: no buffer space available`. Each such query times out.
- kindnet stalls when the node is busy (on Docker Desktop/WSL2 its loop slipped from 10 s
  to almost 30 s). While it stalls, no queued packet gets a verdict, so all DNS of the
  selected pods stops. Under heavy lookups, verdicts stopped for about 15 s, with another
  `no buffer space` in the log. In one window (09:56-10:17 on 2026-10-27) even kindnet's
  own calls to the API server timed out. A promotion (hard refreshes, syncs, image pulls)
  is exactly that kind of load.

Pods without a policy never pass through the queue: the kernel answers their packets
alone. That is why a new busybox pod resolves fine. The Argo CD chart creates a policy per component by default, so exactly the Argo CD
pods were affected. o2c-app's `kfp-install` removes the kubeflow `seaweedfs` policy for
the same reason.

Not the cause: CoreDNS (no errors, no restarts; the queries never reached it), kube-proxy
(iptables mode, rules in place) and stale conntrack entries (none for old CoreDNS IPs;
UDP entries expire after 30 s).

**Fix (bootstrap.sh).**
- `argocd-values.yaml` sets `global.networkPolicy.create: false`: the Argo CD pods are no
  longer in kindnet's set of selected pods (`podips-v4`), so their traffic skips the queue.
  Trade-off: any pod in the cluster may reach the Argo CD components. That is acceptable on
  a local single-node cluster, not on a shared one.
- After Argo CD, `bootstrap.sh` prints a warning for every remaining NetworkPolicy, and
  restarts kindnet if packets without a verdict wait in its queue. The restart empties
  the queue.

Measured on 2026-10-27: 200 internal (`argocd-repo-server`) and 200 external
(`github.com`) lookups from each of argocd-repo-server and argocd-server, while every dev
app was hard-refreshed and synced three times (resolver timeout 2 s, 2 attempts):

| | failed | over 1 s | packets through kindnet's queue |
|---|---|---|---|
| before | 12 of 800 | 22 | 4979 (94 left without a verdict) |
| after (two runs) | 0 of 1600 | 0 | 0 |

**Check by hand.**
```bash
kubectl get networkpolicy -A        # expect: none
docker exec o2c-control-plane nft list set inet kindnet-network-policies podips-v4  # expect: no elements
docker exec o2c-control-plane cat /proc/net/netfilter/nfnetlink_queue
#   101 <portid> <waiting> 2 128 <dropped> <user_dropped> <id_sequence> 1
#   <waiting> should stay 0; if it grows, a NetworkPolicy is back
```
