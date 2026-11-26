{{/*
Expand the name of the chart.
*/}}
{{- define "protopie.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "protopie.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "protopie.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "protopie.labels" -}}
helm.sh/chart: {{ include "protopie.chart" . }}
{{ include "protopie.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "protopie.selectorLabels" -}}
app.kubernetes.io/name: {{ include "protopie.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "protopie.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "protopie.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create imagePullSecrets
*/}}
{{- define "imagePullSecret" }}
{{- with .Values.imageCredentials }}
{{- printf "{\"auths\":{\"%s\":{\"username\":\"%s\",\"password\":\"%s\",\"email\":\"%s\",\"auth\":\"%s\"}}}" .registry .username .password .email (printf "%s:%s" .username .password | b64enc) | b64enc }}
{{- end }}
{{- end }}

{{/*
Get the DB secret name - use existingSecret if provided, otherwise "db-secret"
*/}}
{{- define "protopie.db.secretName" -}}
{{- if .Values.db.existingSecret }}
{{- .Values.db.existingSecret }}
{{- else }}
{{- print "db-secret" }}
{{- end }}
{{- end }}

{{/*
Generate DB_WRITE_PASSWORD - use provided value or generate random
*/}}
{{- define "protopie.db.writePassword" -}}
{{- if .Values.db.env.DB_WRITE_PASSWORD }}
{{- .Values.db.env.DB_WRITE_PASSWORD }}
{{- else }}
{{- randAlphaNum 32 }}
{{- end }}
{{- end }}

{{/*
Generate DB_READ_PASSWORD - use provided value or generate random
*/}}
{{- define "protopie.db.readPassword" -}}
{{- if .Values.db.env.DB_READ_PASSWORD }}
{{- .Values.db.env.DB_READ_PASSWORD }}
{{- else }}
{{- randAlphaNum 32 }}
{{- end }}
{{- end }}

{{/*
Generate Analytics AE_API_USER_PASS - use provided value or generate random
*/}}
{{- define "protopie.analytics.aeApiUserPass" -}}
{{- if .Values.analytics.web.env.AE_API_USER_PASS }}
{{- .Values.analytics.web.env.AE_API_USER_PASS }}
{{- else }}
{{- randAlphaNum 32 }}
{{- end }}
{{- end }}

{{/*
Generate Analytics DJANGO_SECRET_KEY - use provided value or generate random
*/}}
{{- define "protopie.analytics.djangoSecretKey" -}}
{{- if .Values.analytics.api.env.DJANGO_SECRET_KEY }}
{{- .Values.analytics.api.env.DJANGO_SECRET_KEY }}
{{- else }}
{{- randAlphaNum 50 }}
{{- end }}
{{- end }}

{{/*
Compute-tier scheduling (nodeSelector / affinity / tolerations) for stateless
workloads. Reads .Values.compute.* and falls back to the top-level values when
unset, so existing consumers are unaffected. DB/stateful workloads keep using the
top-level .Values.nodeSelector directly and are NOT steered by this helper.
*/}}
{{- define "cloud.computeScheduling" -}}
{{- with (.Values.compute.nodeSelector | default .Values.nodeSelector) }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with (.Values.compute.affinity | default .Values.affinity) }}
affinity:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with (.Values.compute.tolerations | default .Values.tolerations) }}
tolerations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end -}}

{{/*
CoC license slot (PS-2925), shared by cloud-api and connect-server so both read
the same folder. The ConfigMap is mounted as a directory (no subPath) and no
checksum annotation covers it: replacing only connect.lic leaves both pod specs
unchanged and kubelet swaps the file in place. optional: pods start without it.
The path stays outside /app/resources (cloud-api scans license.*pem there) and
outside /data (connect-server's PVC, which holds its own /data/license).
*/}}
{{- define "cloud.connectLicense.dir" -}}
/etc/protopie/connect-license
{{- end -}}

{{/*
Explicit env, so on connect-server it wins over envFrom connect-config.
connect.enabled without organizationId fails the render: a connect-server that
reads its own .lic (PS-2926) refuses to boot in production without
PPC_ORGANIZATION_ID, and a render error is louder than a crash loop.
*/}}
{{- define "cloud.connectLicense.env" -}}
{{- if and .Values.connect.enabled (not .Values.organizationId) }}
{{- fail "connect.enabled requires organizationId (PPC_ORGANIZATION_ID for cloud-api and connect-server, PS-2925)" }}
{{- end }}
- name: PPC_LICENSE_DIR
  value: {{ include "cloud.connectLicense.dir" . | quote }}
{{- with .Values.organizationId }}
- name: PPC_ORGANIZATION_ID
  value: {{ . | quote }}
{{- end }}
{{- end -}}

{{- define "cloud.connectLicense.volumeMount" -}}
- name: connect-license
  mountPath: {{ include "cloud.connectLicense.dir" . }}
  readOnly: true
{{- end -}}

{{- define "cloud.connectLicense.volume" -}}
- name: connect-license
  configMap:
    name: connect-license
    optional: true
{{- end -}}
