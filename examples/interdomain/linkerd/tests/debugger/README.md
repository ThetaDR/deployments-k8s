# Debugging linkerd-proxy

Motivation: linkerd in working case should sent request to the linkerd-destionation containing service ip of greeting service, but instead it sends only request with ip of kubedns service.
That's why we should connect with debugger to get requests and responses to the coredns and linkerd destination.

Correct logs should look like this (I used custom image with some info logs around the request to the linkerd-destination):
```
[    22.654154s]  INFO ThreadId(01) outbound:proxy{addr=10.244.0.5:9080}: linkerd_service_profiles::client: [Slava] discovery sent address addr=10.244.0.5:9080
[    22.678834s]  INFO ThreadId(01) outbound:proxy{addr=10.244.0.5:9080}: linkerd_service_profiles::client: [Slava] discovery response rsp=Response { ... }
```
Where 10.244.0.5:9080 is a greeting service ip


But instead we have this, when sending the request from alpine pod
```
[    22.654154s]  INFO ThreadId(01) outbound:proxy{addr=10.96.0.10:53}: linkerd_service_profiles::client: [Slava] discovery sent address addr=10.96.0.10:53
[    22.678834s]  INFO ThreadId(01) outbound:proxy{addr=10.96.0.10:53}: linkerd_service_profiles::client: [Slava] discovery response rsp=Response { ... }
```
where 10.96.0.10:53 is a kube dns service ip

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

Replace linkerd image just to get additional info in linkerd proxy containers with these images:
- logs-linux-2-lldb (linkerd with some additional logs)
- logs-linux-debian-sudo (linkerd base image changed to debain, additionally sudo and lldb were installed to the image)
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
    version: logs-linux-debian-sudo  
```
Also on the line 1647 change proxy-injector image - it was changed to set privileged securityContext for the linkerd-proxy container
``image: thetadr/controller-linkerd:privileged``

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

connect debugger server to the proxy (copy pod name like proxy-alpine-86fc94c47-kqdtx manually)
```bash
PROXY_NAME=proxy-alpine-86fc94c47-kqdtx
kubectl --kubeconfig=$KUBECONFIG2 exec $PROXY_NAME -c linkerd-proxy -- lldb-server gdbserver :8001 --attach 1
```

### Debug

Download linkerd2 and linkerd-proxy repositories
Download VSCode
- Add [CodeLLDB](https://marketplace.visualstudio.com/items?itemName=vadimcn.vscode-lldb) extension for vscode
- On linkerd-proxy container run lldb-server platform (https://lldb.llvm.org/man/lldb-server.html)
- expose linerd-proxy through node-port (e.g. kubectl expose deployment hello-world --type=NodePort)
- add configuration to connect to debug server via $nodeIP:$nodePort (https://github.com/vadimcn/vscode-lldb/blob/v1.8.1/MANUAL.md#remote-debugging)
- run the debug


Note: it could not attach to the process probably due to restrictions of the linkerd. I have tried next things:
- built lldb from sources. Result: did not give binary for lldb server.
- made proxy image logs-linux-debian-sudo containing lldb-server, sudo and procps, base image - debian
- made image with privileged mode for proxy (controller image thetadr/controller-linkerd:privileged). 
To do the same change _proxy.tpl file in linkerd2 repository (charts/partials/templates/_proxy.tpl). Result: errors either way.
- tried to run lldb-server gdbserver and attach to the process. Result: could not attach to the process.
- made adjustments to [pod-template.yaml](./nse-auto-scale/pod-template.yaml) to share processes (check commented lines). And attached lldb-server from debian container to linkerd-proxy process (not linkerd-proxy container)
    Result - lldb-server platform crashed
- Attached via gdb (not gdbserver) to the process. Result: it connected, but it's problematic and hard to work in gdb cli. Also after some time linkerd-proxy container stopped.
