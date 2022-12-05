#!/bin/bash

CLUSTER1_CIDR=172.19.128.0/24
CLUSTER2_CIDR=172.19.129.0/24


if [[ ! -z $CLUSTER1_CIDR ]]; then
    kubectl --kubeconfig=$KUBECONFIG1 apply -f https://raw.githubusercontent.com/metallb/metallb/v0.12.1/manifests/namespace.yaml
    kubectl --kubeconfig=$KUBECONFIG1 apply -f https://raw.githubusercontent.com/metallb/metallb/v0.12.1/manifests/metallb.yaml
    cat > metallb-config.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: metallb-system
  name: config
data:
  config: |
    address-pools:
    - name: default
      protocol: layer2
      addresses:
      - $CLUSTER1_CIDR
EOF
    kubectl --kubeconfig=$KUBECONFIG1 apply -f metallb-config.yaml
    kubectl --kubeconfig=$KUBECONFIG1 wait --for=condition=ready --timeout=5m pod -l app=metallb -n metallb-system
fi

if [[ ! -z $CLUSTER2_CIDR ]]; then
    kubectl --kubeconfig=$KUBECONFIG2 apply -f https://raw.githubusercontent.com/metallb/metallb/v0.12.1/manifests/namespace.yaml
    kubectl --kubeconfig=$KUBECONFIG2 apply -f https://raw.githubusercontent.com/metallb/metallb/v0.12.1/manifests/metallb.yaml
    cat > metallb-config.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: metallb-system
  name: config
data:
  config: |
    address-pools:
    - name: default
      protocol: layer2
      addresses:
      - $CLUSTER2_CIDR
EOF
    kubectl --kubeconfig=$KUBECONFIG2 apply -f metallb-config.yaml
    kubectl --kubeconfig=$KUBECONFIG2 wait --for=condition=ready --timeout=5m pod -l app=metallb -n metallb-system
fi


echo "DNS SETUP"
kubectl --kubeconfig=$KUBECONFIG1 expose service kube-dns -n kube-system --port=53 --target-port=53 --protocol=TCP --name=exposed-kube-dns --type=LoadBalancer

kubectl --kubeconfig=$KUBECONFIG1 get services exposed-kube-dns -n kube-system -o go-template='{{index (index (index (index .status "loadBalancer") "ingress") 0) "ip"}}'
ip1=$(kubectl --kubeconfig=$KUBECONFIG1 get services exposed-kube-dns -n kube-system -o go-template='{{index (index (index (index .status "loadBalancer") "ingress") 0) "ip"}}')
if [[ $ip1 == *"no value"* ]]; then
    ip1=$(kubectl --kubeconfig=$KUBECONFIG1 get services exposed-kube-dns -n kube-system -o go-template='{{index (index (index (index .status "loadBalancer") "ingress") 0) "hostname"}}')
    ip1=$(dig +short $ip1 | head -1)
fi
# if IPv6
if [[ $ip1 =~ ":" ]]; then ip1=[$ip1]; fi

echo Selected externalIP: $ip1 for cluster1



kubectl --kubeconfig=$KUBECONFIG2 expose service kube-dns -n kube-system --port=53 --target-port=53 --protocol=TCP --name=exposed-kube-dns --type=LoadBalancer

kubectl --kubeconfig=$KUBECONFIG2 get services exposed-kube-dns -n kube-system -o go-template='{{index (index (index (index .status "loadBalancer") "ingress") 0) "ip"}}'
ip2=$(kubectl --kubeconfig=$KUBECONFIG2 get services exposed-kube-dns -n kube-system -o go-template='{{index (index (index (index .status "loadBalancer") "ingress") 0) "ip"}}')
if [[ $ip2 == *"no value"* ]]; then
    ip2=$(kubectl --kubeconfig=$KUBECONFIG2 get services exposed-kube-dns -n kube-system -o go-template='{{index (index (index (index .status "loadBalancer") "ingress") 0) "hostname"}}')
    ip2=$(dig +short $ip2 | head -1)
fi
# if IPv6
if [[ $ip2 =~ ":" ]]; then ip2=[$ip2]; fi

echo Selected externalIP: $ip2 for cluster2

cat > configmap.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
data:
  Corefile: |
    .:53 {
        errors
        health {
            lameduck 5s
        }
        ready
        kubernetes cluster.local in-addr.arpa ip6.arpa {
            pods insecure
            fallthrough in-addr.arpa ip6.arpa
            ttl 30
        }
        k8s_external my.cluster1
        prometheus :9153
        forward . /etc/resolv.conf {
            max_concurrent 1000
        }
        loop
        reload 5s
    }
    my.cluster2:53 {
      forward . ${ip2}:53 {
        force_tcp
      }
    }
EOF
kubectl --kubeconfig=$KUBECONFIG1 apply -f configmap.yaml
cat > custom-configmap.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns-custom
  namespace: kube-system
data:
  server.override: |
    k8s_external my.cluster2
  proxy1.server: |
    my.cluster2:53 {
      forward . ${ip2}:53 {
        force_tcp
      }
    }
EOF

kubectl --kubeconfig=$KUBECONFIG1 apply -f custom-configmap.yaml

cat > configmap.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
data:
  Corefile: |
    .:53 {
        errors
        health {
            lameduck 5s
        }
        ready
        kubernetes cluster.local in-addr.arpa ip6.arpa {
            pods insecure
            fallthrough in-addr.arpa ip6.arpa
            ttl 30
        }
        k8s_external my.cluster2
        prometheus :9153
        forward . /etc/resolv.conf {
            max_concurrent 1000
        }
        loop
        reload 5s
    }
    my.cluster1:53 {
      forward . ${ip1}:53 {
        force_tcp
      }
    }
EOF
kubectl --kubeconfig=$KUBECONFIG2 apply -f configmap.yaml
cat > custom-configmap.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns-custom
  namespace: kube-system
data:
  server.override: |
    k8s_external my.cluster1
  proxy1.server: |
    my.cluster1:53 {
      forward . ${ip1}:53 {
        force_tcp
      }
    }
EOF
kubectl --kubeconfig=$KUBECONFIG2 apply -f custom-configmap.yaml

echo "SPIRE SETUP"
kubectl --kubeconfig=$KUBECONFIG1 apply -k https://github.com/networkservicemesh/deployments-k8s/examples/spire/cluster1?ref=bc664867263869d08c9fb616c7c0784b26af9c99


kubectl --kubeconfig=$KUBECONFIG1 wait -n spire --timeout=5m --for=condition=ready pod -l app=spire-server
kubectl --kubeconfig=$KUBECONFIG1 wait -n spire --timeout=5m --for=condition=ready pod -l app=spire-agent


kubectl --kubeconfig=$KUBECONFIG2 apply -k https://github.com/networkservicemesh/deployments-k8s/examples/spire/cluster2?ref=bc664867263869d08c9fb616c7c0784b26af9c99
kubectl --kubeconfig=$KUBECONFIG2 wait -n spire --timeout=5m --for=condition=ready pod -l app=spire-server
kubectl --kubeconfig=$KUBECONFIG2 wait -n spire --timeout=5m --for=condition=ready pod -l app=spire-agent

bundle1=$(kubectl --kubeconfig=$KUBECONFIG1 exec spire-server-0 -n spire -- bin/spire-server bundle show -format spiffe)
bundle2=$(kubectl --kubeconfig=$KUBECONFIG2 exec spire-server-0 -n spire -- bin/spire-server bundle show -format spiffe)

echo $bundle2 | kubectl --kubeconfig=$KUBECONFIG1 exec -i spire-server-0 -n spire -- bin/spire-server bundle set -format spiffe -id "spiffe://nsm.cluster2"
echo $bundle1 | kubectl --kubeconfig=$KUBECONFIG2 exec -i spire-server-0 -n spire -- bin/spire-server bundle set -format spiffe -id "spiffe://nsm.cluster1"

echo "NSM SETUP"
kubectl --kubeconfig=$KUBECONFIG1 apply -k https://github.com/networkservicemesh/deployments-k8s/examples/interdomain/nsm/cluster1?ref=bc664867263869d08c9fb616c7c0784b26af9c99
kubectl --kubeconfig=$KUBECONFIG2 apply -k https://github.com/networkservicemesh/deployments-k8s/examples/interdomain/nsm/cluster2?ref=bc664867263869d08c9fb616c7c0784b26af9c99


WH=$(kubectl --kubeconfig=$KUBECONFIG1 get pods -l app=admission-webhook-k8s -n nsm-system --template '{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}')
kubectl --kubeconfig=$KUBECONFIG1 wait --for=condition=ready --timeout=10m pod ${WH} -n nsm-system

WH=$(kubectl --kubeconfig=$KUBECONFIG2 get pods -l app=admission-webhook-k8s -n nsm-system --template '{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}')
kubectl --kubeconfig=$KUBECONFIG2 wait --for=condition=ready --timeout=10m pod ${WH} -n nsm-system
