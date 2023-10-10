# Protopie Kubernetes Helm Charts

## Usage

```console
helm repo add protopie https://protopie.github.io/helm-charts
```

## Install

**※ We only support [enterprise plan](https://www.protopie.io/plans/enterprise) For license issuance, please contact https://www.protopie.io/form/enterprise-plan-contact-us.**

```console
helm repo update
helm install my-release protopie/cloud -n my-namespace \
    --set-file cloud.config.yml=config.yml \
    --set-file cloud.license.pem=license.pem
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
