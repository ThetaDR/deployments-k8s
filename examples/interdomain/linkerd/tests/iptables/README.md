# NSM + linkerd interdomain example over kind clusters



This diagram shows that we have 2 clusters with NSM and also linkerd deployed on the Cluster-2.

In this example, we deploy an http-server (**Workload-2**) on the Cluster-2 and show how it can be reached from Cluster-1.

The client will be `alpine` (**Workload-1**), we will use curl.

## Requires

- [Load balancer](../../loadbalancer)
- [Interdomain DNS](../../dns)
- [Interdomain spire](../../spire)
- [Interdomain nsm](../../nsm)

Or you can run [interdomain script](../../../interdomain.sh)

## Run

Install linkerd for second cluster:
```bash
linkerd --kubeconfig=$KUBECONFIG2 check --pre
linkerd --kubeconfig=$KUBECONFIG2 install --crds | kubectl --kubeconfig=$KUBECONFIG2 apply -f -
linkerd --kubeconfig=$KUBECONFIG2 install > linkerd.yaml
```

Replace linkerd image just to get additional info in linkerd proxy containers
```
proxy:
  accessLog: ""
  await: true
  capabilities: null
  defaultInboundPolicy: all-unauthenticated
  enableExternalProfiles: false
  image:
    name: thetadr/linkerd-proxy
    pullPolicy: ""
    version: logs-linux
```

```bash
kubectl --kubeconfig=$KUBECONFIG2 apply -f linkerd.yaml
linkerd --kubeconfig=$KUBECONFIG2 check
```

Install networkservice for the second cluster:
```bash
kubectl --kubeconfig=$KUBECONFIG2 create ns ns-nsm-linkerd
kubectl --kubeconfig=$KUBECONFIG2 apply -f ./networkservice.yaml
```

Start `alpine` with networkservicemesh client on the first cluster:

```bash
kubectl --kubeconfig=$KUBECONFIG1 apply -f ./greeting/client.yaml
```

Start `auto-scale` networkservicemesh endpoint:
```bash
kubectl --kubeconfig=$KUBECONFIG2 apply -k ./nse-auto-scale
```

Install http-server for the second cluster:
```bash
kubectl --kubeconfig=$KUBECONFIG2 apply -f ./greeting/server.yaml
kubectl --kubeconfig=$KUBECONFIG2 get deploy greeting -o yaml | linkerd --kubeconfig=$KUBECONFIG2 inject - | kubectl --kubeconfig=$KUBECONFIG2 apply -f -
```


Wait for the `alpine` client to be ready:
```bash
kubectl --kubeconfig=$KUBECONFIG1 wait --timeout=2m --for=condition=ready pod -l app=alpine
```

Get curl for nsc:
```bash
kubectl --kubeconfig=$KUBECONFIG1 exec deploy/alpine -c cmd-nsc -- apk add curl
```

Add iptables to nse (copy pod name like proxy-alpine-86fc94c47-kqdtx manually)
```bash
PROXY_NAME=
kubectl --kubeconfig=$KUBECONFIG2 exec $PROXY_NAME -c nse -- apk add iptables
```

Add this iptables to proxy nse container. (1)
Don't forget to get interface for third rule
```
-N NSM_PREROUTE
-A NSM_PREROUTE -j DNAT --to-destination 127.0.0.1
-I PREROUTING 1 -p tcp -i nsm-linker-4d5a -j NSM_PREROUTE
```

Verify connectivity:
```bash
kubectl --kubeconfig=$KUBECONFIG1 exec deploy/alpine -c cmd-nsc -- curl -s greeting.default:9080 | grep -o "hello world from linkerd"
```
**Expected output** is "hello world from linkerd"

-N NSM_OUTPUT
-A NSM_OUTPUT -j DNAT --to-destination 10.244.1.9
-A OUTPUT -p tcp -s 127.0.0.6 -j NSM_OUTPUT
# ^ should be fine
-N NSM_POSTROUTING
-A NSM_POSTROUTING -j SNAT --to-source {{ index .NsmDstIPs 0 }}
-A POSTROUTING -p tcp -o {{ .NsmInterfaceName }} -j NSM_POSTROUTING


- -I PREROUTING 1 -p tcp -i nsm-linker-d049 -j DNAT --to-destination 127.0.0.1
- -N NSM_OUTPUT
- -A NSM_OUTPUT -j DNAT --to-destination {{ index .NsmSrcIPs 0 }}
- -A OUTPUT -p tcp -d 127.0.0.1 -j NSM_OUTPUT
- -N NSM_POSTROUTING
- -A NSM_POSTROUTING -j SNAT --to-source {{ index .NsmDstIPs 0 }}
- -A POSTROUTING -p tcp -o nsm-linker-d049 -j NSM_POSTROUTING
