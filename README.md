# Protopie Kubernetes Helm Charts

## ⚠️ Security Notice: Temporary Workaround for CVE-2026-114938 (Java4Shell)

**This applies to API versions 15.0.0 – 16.6.0.** A patched API image is being prepared. Until it is released, we recommend applying the workaround below. You can check your API version in `image.cloud.api.tag`.

1. Add the following to the values you use for your release. If `JAVA_TOOL_OPTIONS` is already set in `cloud.envs`, add the option to the existing value, separated by a space.

```yaml
cloud:
  envs:
    - name: JAVA_TOOL_OPTIONS
      value: "-XX:-UseBASE64Intrinsics"
```

2. Run `helm upgrade` for your release with the same chart version and values you already use, plus the values above. The API pods are recreated with the new environment variable. Your data is stored in volumes and is not affected.

3. Check that the option is applied. The API log should contain the line `Picked up JAVA_TOOL_OPTIONS: -XX:-UseBASE64Intrinsics`.

```console
kubectl logs statefulset/enterprise-cloud-api -n my-namespace
```

Please note:

- **Do not apply this to API 14.x or earlier.** Those versions run on Java 8, which does not recognize this option, so the API will fail to start. They are not affected by this vulnerability and do not need the workaround.
- This workaround only mitigates CVE-2026-114938. Please upgrade to the patched API image once it is released.

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

## Changelog

### 3.0.0

In this release we upgrade the database image from `postgres:10` to `bitnami/postgresql:14`. This is breaking change, and you need to migrate your database before upgrading. Please refer to the [migration guide](/docs/3.x%20database%20migration%20guide.md) before upgrade your chart.

We also optionally include the `bitnami/postgresql` chart, but it is preparation for the future updates. We will leverage it sometime in the future, but for now, it is not used. You can safely ignore it.
