path "secret/data/dev/keycloak" {
  capabilities = ["read"]
}

path "secret/data/pro/keycloak" {
  capabilities = ["read"]
}

path "secret/data/dev/mongodb/users/*" {
  capabilities = ["read"]
}

path "secret/data/pro/mongodb/users/*" {
  capabilities = ["read"]
}
