{{- define "content-factory.name" -}}
content-factory
{{- end }}

{{- define "content-factory.image" -}}
{{- $root := index . 0 -}}
{{- $repository := index . 1 -}}
{{- if $root.Values.global.imageRegistry -}}
{{ $root.Values.global.imageRegistry }}/{{ $repository }}:{{ $root.Values.global.imageTag }}
{{- else -}}
{{ $repository }}:{{ $root.Values.global.imageTag }}
{{- end -}}
{{- end }}

{{- define "content-factory.labels" -}}
app.kubernetes.io/part-of: content-factory
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

