```bash
l1 check --pre
l1 install --crds | k1 apply -f -
l1 install | k1 apply -f -
l1 check
```

```bash
curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/emojivoto.yml \
  | k1 apply -f -
```

```bash
k1 get -n emojivoto deploy -o yaml \
  | l1 inject - \
  | k1 apply -f -
```

```bash
l1 -n emojivoto check --proxy
```

```bash
k1 -n emojivoto port-forward svc/web-svc 8080:80
```

```bash
k1 exec -n emojivoto            web-5f86686c4d-xnnhl -c web-svc -- tcpdump  -w - | wireshark -k -i -
```

```bash
k1 exec -n emojivoto            web-5f86686c4d-xnnhl -c web-svc -- curl 
```
