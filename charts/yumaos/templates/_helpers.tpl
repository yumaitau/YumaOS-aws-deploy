{{- define "yumaos.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "yumaos.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "yumaos.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | quote }}
app.kubernetes.io/name: {{ include "yumaos.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "yumaos.selectorLabels" -}}
app.kubernetes.io/name: {{ include "yumaos.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "yumaos.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- include "yumaos.fullname" . -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{- define "yumaos.secretName" -}}
{{- default (printf "%s-secrets" (include "yumaos.fullname" .)) .Values.existingSecret -}}
{{- end -}}

{{- define "yumaos.validate" -}}
{{- if gt (int .Values.replicaCount) 1 -}}
{{- fail "replicaCount must be 1. The Marketplace contract dimension is MaxCount=1; a second web container fails CheckoutLicense." -}}
{{- end -}}
{{- $webTag := printf "%s" .Values.image.tag -}}
{{- $hermesTag := printf "%s" .Values.hermes.image.tag -}}
{{- if or (eq $webTag "latest") (eq $webTag "1.0.0") (eq $webTag "1.0.1") (eq $webTag "1.0.2") -}}
{{- fail "image.tag must not be latest, 1.0.0, 1.0.1, or 1.0.2. Pin a Marketplace ECR sha-<7> that already exists." -}}
{{- end -}}
{{- if or (eq $hermesTag "latest") (eq $hermesTag "1.0.0") (eq $hermesTag "1.0.1") (eq $hermesTag "1.0.2") -}}
{{- fail "hermes.image.tag must not be latest, 1.0.0, 1.0.1, or 1.0.2. Pin the same sha-<7> as image.tag." -}}
{{- end -}}
{{- if not (index .Values.env "AWS_REGION") -}}
{{- fail "env.AWS_REGION is required. CheckoutLicense and Bedrock use the task/pod region; IRSA does not set it." -}}
{{- end -}}
{{- end -}}
