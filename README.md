# Protopie Kubernetes Helm Charts

## Usage

```console
helm repo add protopie https://protopie.github.io/helm-charts
```

## Install

※ 반드시 

```console
helm repo update
helm install my-release protopie/cloud -n my-namespace \
    --set-file config.yml=config.yml \
    --set-file license.pem license.pem
```

### With Ingress

```console
helm repo update
helm install my-release protopie/cloud -n my-namespace \
    --set ingress.enabled=true \
    --set ingress.host=dev-ee.protopie.works
```

### With Analytics Dashboard

```console
helm repo update
helm install my-release protopie/cloud -n my-namespace --set analytics.enabled=true
```
