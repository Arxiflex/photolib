{{- define "photolib.labels" -}}
app.kubernetes.io/name: photolib
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/* The photolibd container, shared by the Deployments and the migration Job; `args` and `roles` set. */}}
{{- define "photolib.container" -}}
name: photolibd
image: {{ .root.Values.image.repository }}:{{ .root.Values.image.tag | default .root.Chart.AppVersion }}
{{- with .args }}
args: {{ toJson . }}
{{- end }}
env:
  - name: PHOTOLIB_ROLES
    value: {{ .roles | quote }}
  - name: PHOTOLIB_PUBLIC_URL
    value: {{ required "set publicUrl and database.secret" .root.Values.publicUrl | quote }}
  - name: PHOTOLIB_DATABASE__URL
    valueFrom:
      secretKeyRef:
        name: {{ required "set publicUrl and database.secret" .root.Values.database.secret }}
        key: url
  - name: PHOTOLIB_OPAQUE_KEY_FILE
    value: /keys/opaque.key
  {{- with .root.Values.env }}
  {{- toYaml . | nindent 2 }}
  {{- end }}
securityContext:
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false
  capabilities:
    drop: [ALL]
{{- with .root.Values.resources }}
resources: {{- toYaml . | nindent 2 }}
{{- end }}
volumeMounts:
  - name: data
    mountPath: /data
  - name: keys
    mountPath: /keys
  - name: tmp
    mountPath: /tmp
{{- end }}

{{- define "photolib.pod" -}}
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 1000
  fsGroup: 1000
volumes:
  - name: data
    persistentVolumeClaim:
      claimName: {{ .Release.Name }}-data
  - name: keys
    persistentVolumeClaim:
      claimName: {{ .Release.Name }}-keys
  - name: tmp
    emptyDir: {}
{{- end }}
