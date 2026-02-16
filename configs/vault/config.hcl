ui            = true
cluster_addr  = "http://vault:8201"
api_addr      = "http://vault:8200"
disable_mlock = true

storage "raft" {
  path    = "/vault/data"
  node_id = "vault-node-1"
 }

listener "tcp" {
  address       = "0.0.0.0:8200"
  cluster_address = "0.0.0.0:8201"
  tls_disable = 1
  #tls_cert_file = "/etc/vault/domain.crt"
  #tls_key_file = "/etc/vault/domain.key"
}