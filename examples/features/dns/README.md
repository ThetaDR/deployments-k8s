# Alpine requests for CoreDNS service

This example demonstrates how an external client configures DNS from the connected endpoint. 
Note: NSE provides DNS by itself. Also, NSE could provide configs for any other external DNS servers(that are not located as sidecar with NSE).

## Requires

Make sure that you have completed steps from [features](../)

## Run

Note: Admission webhook is required and should be started at this moment.
```bash
WH=$(kubectl get pods -l app=admission-webhook-k8s -n nsm-system --template '{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}')
kubectl wait --for=condition=ready --timeout=1m pod ${WH} -n nsm-system
```

1. Create test namespace:
```bash
NAMESPACE=($(kubectl create -f https://raw.githubusercontent.com/networkservicemesh/deployments-k8s/c89573ec0f82ee02c425c43da72b026397cb52fc/examples/features/namespace.yaml)[0])
NAMESPACE=${NAMESPACE:10}
```

2. Get all available nodes to deploy:
```bash
NODES=($(kubectl get nodes -o go-template='{{range .items}}{{ if not .spec.taints  }}{{index .metadata.labels "kubernetes.io/hostname"}} {{end}}{{end}}'))
```

3. Create alpine deployment and set `nodeSelector` to the first node:
```bash
cat > alpine.yaml <<EOF
---
apiVersion: v1
kind: Pod
metadata:
  name: alpine
  annotations:
    networkservicemesh.io: kernel://my-coredns-service/nsm-1
  labels:
    app: alpine
    "spiffe.io/spiffe-id": "true"
spec:
  containers:
  - name: alpine
    image: alpine
    imagePullPolicy: IfNotPresent
    stdin: true
    tty: true
  nodeSelector:
    kubernetes.io/hostname: ${NODES[0]}
EOF
```


4. Add to nse-kernel the corends container and set `nodeSelector` it to the second node:
```bash
cat > patch-nse.yaml <<EOF
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nse-kernel
spec:
  template:
    spec:
      containers:
      - name: nse
        env:
          - name: NSM_SERVICE_NAMES
            value: my-coredns-service
          - name: NSM_CIDR_PREFIX
            value: 172.16.1.100/31
          - name: NSM_DNS_CONFIGS
            value: "[{\"dns_server_ips\": [\"172.16.1.100\"], \"search_domains\": [\"my.coredns.service\"]}]"
      - name: coredns
        image: coredns/coredns:1.8.3
        imagePullPolicy: IfNotPresent
        resources:
          limits:
            memory: 170Mi
          requests:
            cpu: 100m
            memory: 70Mi
        args: [ "-conf", "/etc/coredns/Corefile" ]
        volumeMounts:
        - name: config-volume
          mountPath: /etc/coredns
          readOnly: true
        ports:
        - containerPort: 53
          name: dns
          protocol: UDP
        - containerPort: 53
          name: dns-tcp
          protocol: TCP
      nodeSelector:
        kubernetes.io/hostname: ${NODES[1]}
      volumes:
        - name: config-volume
          configMap:
            name: coredns
            items:
            - key: Corefile
              path: Corefile
EOF
```

5. Create kustomization file:
```bash
cat > kustomization.yaml <<EOF
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: ${NAMESPACE}

bases:
- https://github.com/networkservicemesh/deployments-k8s/apps/nse-kernel?ref=c89573ec0f82ee02c425c43da72b026397cb52fc

resources:
- alpine.yaml
- https://raw.githubusercontent.com/networkservicemesh/deployments-k8s/c89573ec0f82ee02c425c43da72b026397cb52fc/examples/features/dns/coredns-config-map.yaml

patchesStrategicMerge:
- patch-nse.yaml
EOF
```

6. Deploy alpine and nse
```bash
kubectl apply -k .
```

7. Wait for applications ready:
```bash
kubectl wait --for=condition=ready --timeout=5m pod alpine -n ${NAMESPACE}
```
```bash
kubectl wait --for=condition=ready --timeout=5m pod -l app=nse-kernel -n ${NAMESPACE}
```

8. Find NSC and NSE pods by labels:
```bash
NSC=$(kubectl get pods -l app=alpine -n ${NAMESPACE} --template '{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}')
```
```bash
NSE=$(kubectl get pods -l app=nse-kernel -n ${NAMESPACE} --template '{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}')
```

9. Install `nslookup` to alpine:
```bash
kubectl exec ${NSC} -c alpine -n ${NAMESPACE} -- sh -c "apk update && apk add bind-tools"
```

10. Ping from alpine to NSE by domain name:
```bash
kubectl exec ${NSC} -c alpine -n ${NAMESPACE} -- nslookup -nodef -norec my.coredns.service
```
```bash
kubectl exec ${NSC} -c alpine -n ${NAMESPACE} -- ping -c 4 my.coredns.service
```

11. Validate that default DNS server is working:
```bash
kubectl exec ${NSC} -c alpine -n ${NAMESPACE} -- nslookup -nodef google.com
```

## Cleanup

Delete ns:
```bash
kubectl delete ns ${NAMESPACE}
```
