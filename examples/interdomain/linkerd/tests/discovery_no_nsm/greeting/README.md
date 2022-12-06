```bash
l1 check --pre
l1 install --crds | k1 apply -f -
l1 install | k1 apply -f -
l1 check
```

```bash
k1 apply -f ./server.yaml
```

```bash
k1 apply -f ./client.yaml
```

```bash
k1 get -n default deploy -o yaml \
  | l1 inject - \
  | k1 apply -f -
```

```bash
kubectl --kubeconfig=$KUBECONFIG1 exec deploy/alpine -c alpine -- apk add curl
kubectl --kubeconfig=$KUBECONFIG1 exec deploy/alpine -c alpine -- apk add tcpdump
```

```bash
kubectl --kubeconfig=$KUBECONFIG1 exec deploy/alpine -c alpine -- tcpdump -w - | wireshark -k -i -
```

```bash
kubectl --kubeconfig=$KUBECONFIG1 exec deploy/alpine -c alpine -- curl greeting.default:9080
```

```bash

```

```bash

```

```bash

```

```bash

```

```bash

```

