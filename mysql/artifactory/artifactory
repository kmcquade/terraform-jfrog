variable "postgresql_hostname" {}
variable "postgresql_version" {}
variable "postgresql_db" {}
variable "postgresql_user" {}
variable "postgresql_password" {}
variable "artifactory_user" {}
variable "artifactory_password" {}
variable "artifactory_db" {}

provider "postgresql" {
  version          = "~> 0.1"
  host             = "${var.postgresql_hostname}"
  port             = 5432
  expected_version = "${var.postgresql_version}"
  database         = "${var.postgresql_db}"
  username         = "${var.postgresql_user}"
  password         = "${var.postgresql_password}"
  sslmode          = "require"
  connect_timeout  = 15
}

resource "postgresql_role" "artifactory" {
  name                = "${var.artifactory_user}"
  login               = true
  password            = "${var.artifactory_password}"
  skip_reassign_owned = true
}

resource "postgresql_database" "artifactory" {
  name              = "${var.artifactory_db}"
  template          = "template0"
  lc_collate        = "C"
  connection_limit  = -1
  allow_connections = true
}
