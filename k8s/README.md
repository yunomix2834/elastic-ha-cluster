
## 0) Start minikube (RAM/CPU 3 ES + Kibana)

```shell
minikube start --memory=8192 --cpus=4
```

If you deploy minikube on Docker
```shell
minikube start --memory=8192 --cpus=4 --driver=docker
```

---

## 1) Install ECK Operator (CRDs + Operator) v2.12.1

```shell
kubectl create namespace elastic-system

kubectl apply -f https://download.elastic.co/downloads/eck/2.12.1/crds.yaml
kubectl apply -f https://download.elastic.co/downloads/eck/2.12.1/operator.yaml
```

Check:

```shell
kubectl -n elastic-system get pods
```

---

## 2) Create namespace

```shell
kubectl create namespace elastic
```

---

## 3) Apply Elasticsearch (3 node)

```shell
kubectl apply -f elasticsearch.yaml
```

Check
```shell
kubectl -n elastic get elasticsearch
kubectl -n elastic get pods -w
kubectl -n elastic get pvc
```
---

## 4) Apply Kibana

```shell
kubectl apply -f kibana.yaml
kubectl -n elastic get kibana
kubectl -n elastic get pods -w
```

---

## 5) Expose L4 LoadBalancer (minikube)

On minikube, `Service type=LoadBalancer` needs tunnel.

```shell
kubectl apply -f lb-services.yaml
kubectl -n elastic get svc
```

Tunnel minikube
```shell
minikube tunnel
```
---

## 6) Take password user `elastic` (user root) (ECK generate)

```shell
kubectl -n elastic get secret es-ha-es-elastic-user \
  -o go-template='{{.data.elastic | base64decode}}{{"\n"}}'
```

---

## 7) Test Elasticsearch / Kibana

### Elasticsearch

* If you use LB: Retrieve IP from `kubectl -n elastic get svc es-ha-lb`
* Or port-forward:

```shell
kubectl -n elastic port-forward svc/es-ha-es-http 19200:9200
export ELASTIC_PASS=$(kubectl -n elastic get secret es-ha-es-elastic-user -o go-template='{{.data.elastic | base64decode}}')
curl -u "elastic:$ELASTIC_PASS" http://localhost:9200/_cluster/health?pretty
```

### Kibana

```shell
kubectl -n elastic port-forward svc/kb-ha-kb-http 15601:5601
```

> Test kibana on localhost:15601

---

## 8) If you want to uninstall fast

```shell
kubectl delete ns elastic
kubectl delete ns elastic-system
```