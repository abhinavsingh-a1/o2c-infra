{{/*
The container image: repository@digest when image.digest is set (deployments from
o2c-gitops), else repository:tag. A malformed digest fails the render.
*/}}
{{- define "o2c-service.image" -}}
{{- with .Values.image.digest -}}
{{- if not (regexMatch "^sha256:[a-f0-9]{64}$" .) -}}
{{- fail (printf "image.digest must be sha256:<64 hex>, got %q" .) -}}
{{- end -}}
{{- printf "%s@%s" $.Values.image.repository . -}}
{{- else -}}
{{- printf "%s:%s" .Values.image.repository .Values.image.tag -}}
{{- end -}}
{{- end -}}
