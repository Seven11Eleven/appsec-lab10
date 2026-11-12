# Least-privilege policy for the app: read-only access to its own KV path.
path "secret/data/lab10" {
  capabilities = ["read"]
}
path "secret/metadata/lab10" {
  capabilities = ["read"]
}
