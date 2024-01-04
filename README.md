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

### With Analytics Dashboard (closed beta)

```console
helm repo update
helm install my-release protopie/cloud -n my-namespace --set analytics.enabled=true
```

### HA setup

Check the [sample/cloud-ha](sample/cloud-ha) directory.

```yaml
image:
  cloud:
    api:
      pullPolicy: IfNotPresent
      repository: protopie/enterprise-onpremises
      tag: api-12.0.1 # public docker image
    web:
      pullPolicy: IfNotPresent
      repository: protopie/enterprise-onpremises
      tag: web-11.0.5 # public docker image

cloud:
  api:
    replicas: 2
  web:
    replicas: 2

nginx:
  replicas: 2

analytics:
  enabled: false # This feature is a closed alpha, there are no public images

userResearch:
  enabled: false # This feature is a closed alpha, there are no public images
```
