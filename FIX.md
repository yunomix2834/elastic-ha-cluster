## Get Logs
```shell
kubectl config get-contexts
kubectl config current-context
kubectl config view --minify
kubectl cluster-info
```

## Fix minikube if minikube does not apply config
```shell
minikube status
minikube stop
minikube delete
minikube start --memory=8192 --cpus=4
minikube update-context
```

## Elastic search yaml
```shell
kubectl apply -f elasticsearch.yaml
kubectl -n elastic get elasticsearch
kubectl -n elastic get pods -l elasticsearch.k8s.elastic.co/cluster-name=es-ha
```

## Kibana yaml
```shell
kubectl apply -f kibana.yaml
kubectl -n elastic get kibana
kubectl -n elastic get pods -l kibana.k8s.elastic.co/name=kb-ha
```

## Logs pods events
```shell
kubectl -n elastic describe pod es-ha-es-default-1 | sed -n '/Events/,$p'
kubectl get nodes -o wide
```

### Add Persistent Volume
```shell
minikube addons enable storage-provisioner
minikube addons enable default-storageclass

kubectl get storageclass
kubectl -n elastic get pvc
kubectl -n elastic describe pvc -l elasticsearch.k8s.elastic.co/cluster-name=es-ha
```

### IF NOT APPLY YAML (edit RAM, CPU) 
```shell
kubectl apply -f elasticsearch.yaml
kubectl -n elastic delete pod es-ha-es-default-1 es-ha-es-default-2
kubectl -n elastic get pods -w
```


