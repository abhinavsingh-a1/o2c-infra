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

{{/*
The service's environment (o2c-app ADR-017): "", dev, test or prod.
*/}}
{{- define "o2c-service.o2cEnv" -}}
{{- $env := .Values.o2cEnv | default "" -}}
{{- if not (has $env (list "" "dev" "test" "prod")) -}}
{{- fail (printf "o2cEnv must be dev, test, prod or empty, got %q" $env) -}}
{{- end -}}
{{- $env -}}
{{- end -}}
