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
{{- if .Values.analytics.secrets.aeApiUserPass }}
{{- .Values.analytics.secrets.aeApiUserPass }}
{{- else }}
{{- randAlphaNum 32 }}
{{- end }}
{{- end }}

{{/*
Generate Analytics DJANGO_SECRET_KEY - use provided value or generate random
*/}}
{{- define "protopie.analytics.djangoSecretKey" -}}
{{- if .Values.analytics.secrets.djangoSecretKey }}
{{- .Values.analytics.secrets.djangoSecretKey }}
{{- else }}
{{- randAlphaNum 50 }}
{{- end }}
{{- end }}
