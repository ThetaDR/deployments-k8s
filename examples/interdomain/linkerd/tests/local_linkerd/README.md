```bash
l1 check --pre
l1 install --crds | k1 apply -f -
k1 apply -f linkerd-arm.yaml
l1 check
```

```bash
kubectl --kubeconfig=$KUBECONFIG3 apply -f ./server.yaml
```

```bash
kubectl --kubeconfig=$KUBECONFIG3 apply -f ./client.yaml
```

```bash
kubectl --kubeconfig=$KUBECONFIG3 get -n default deploy -o yaml \
  | linkerd --kubeconfig=$KUBECONFIG3 inject - \
  | kubectl --kubeconfig=$KUBECONFIG3 apply -f -
```

```bash
kubectl --kubeconfig=$KUBECONFIG3 exec deploy/alpine -c alpine -- apk add curl
kubectl --kubeconfig=$KUBECONFIG3 exec deploy/alpine -c alpine -- apk add tcpdump
```

```bash
kubectl --kubeconfig=$KUBECONFIG3 exec deploy/alpine -c alpine -- tcpdump -i any -w - | wireshark -k -i -
```

```bash
kubectl --kubeconfig=$KUBECONFIG3 exec deploy/alpine -c alpine -- curl greeting.default:9080
```



