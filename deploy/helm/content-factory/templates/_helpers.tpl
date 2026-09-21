{{- define "content-factory.name" -}}
content-factory
{{- end }}

{{- define "content-factory.image" -}}
{{- $root := index . 0 -}}
{{- $repository := index . 1 -}}
{{- $tag := $root.Values.global.imageTag -}}
{{- if gt (len .) 2 -}}
{{- $tag = default $tag (index . 2) -}}
{{- end -}}
{{- if $root.Values.global.imageRegistry -}}
{{ $root.Values.global.imageRegistry }}/{{ $repository }}:{{ $tag }}
{{- else -}}
{{ $repository }}:{{ $tag }}
{{- end -}}
{{- end }}

{{- define "content-factory.labels" -}}
app.kubernetes.io/part-of: content-factory
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}
