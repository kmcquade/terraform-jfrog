variable "mysql_hostname" {}
variable "mysql_port" {}
variable "mysql_user" {}
variable "mysql_password" {}
variable "artifactory_user" {}
variable "artifactory_allow" {}
variable "artifactory_password" {}
variable "artifactory_db" {}

provider "mysql" {
  version  = "~> 0.1"
  endpoint = "${var.mysql_hostname}:${var.mysql_port}"
  username = "${var.mysql_user}"
  password = "${var.mysql_password}"
}

resource "mysql_user" "artifactory" {
  user     = "${var.artifactory_user}"
  host     = "${var.artifactory_allow}"
  password = "${var.artifactory_password}"
}

resource "mysql_grant" "artifactory" {
  user       = "${mysql_user.artifactory.user}"
  host       = "${mysql_user.artifactory.host}"
  database   = "${var.artifactory_db}"
  privileges = ["ALTER", "CREATE", "CREATE VIEW", "DELETE", "DROP", "INDEX", "INSERT", "REFERENCES", "SELECT", "SHOW VIEW", "TRIGGER", "UPDATE"]
}

resource "mysql_database" "artifactory" {
  name                  = "${var.artifactory_db}"
  default_character_set = "utf8"
  default_collation     = "utf8_bin"
}
