# NSM + linkerd interdomain example over kind clusters



This diagram shows that we have 2 clusters with NSM and also linkerd deployed on the Cluster-2.

In this example, we deploy an http-server (**Workload-2**) on the Cluster-2 and show how it can be reached from Cluster-1.

The client will be `alpine` (**Workload-1**), we will use curl.

## Requires

- [Load balancer](../../loadbalancer)
- [Interdomain DNS](../../dns)
- [Interdomain spire](../../spire)
- [Interdomain nsm](../../nsm)


## Run

Install linkerd for second cluster:
```bash
l2 check --pre
l2 install --crds | k2 apply -f -
l2 install | k2 apply -f -
l2 check
```

Install networkservice for the second cluster:
```bash
k2 create ns ns-nsm-linkerd
kubectl --kubeconfig=$KUBECONFIG2 apply -f ./networkservice.yaml
```

Start `alpine` with networkservicemesh client on the first cluster:

```bash
kubectl --kubeconfig=$KUBECONFIG1 apply -f ./greeting/server.yaml
```

Start `auto-scale` networkservicemesh endpoint:
```bash
kubectl --kubeconfig=$KUBECONFIG2 apply -k ./nse-auto-scale
```

Install http-server for the second cluster:
```bash
#k2 get -n ns-nsm-linkerd deploy web-local -o yaml | l2 inject --enable-debug-sidecar - | k2 apply -f -

kubectl --kubeconfig=$KUBECONFIG2 apply -f ./greeting/client.yaml
k2 get deploy alpine -o yaml | l2 inject - | k2 apply -f -
```


Wait for the `alpine` client to be ready:
```bash
kubectl --kubeconfig=$KUBECONFIG2 wait --timeout=2m --for=condition=ready pod -l app=alpine
```

Get curl for nsc:
```bash
kubectl --kubeconfig=$KUBECONFIG2 exec deploy/alpine  -- apk add curl
```

Verify connectivity:
```bash
kubectl --kubeconfig=$KUBECONFIG2 exec deploy/alpine -- curl -s greeting.default:9080 | grep -o "hello world from linkerd"
```
**Expected output** is "hello world from linkerd"

Congratulations! 
You have made a interdomain connection between two clusters via NSM + linkerd!

## Cleanup

```bash

```
