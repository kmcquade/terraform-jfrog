variable "vsphere_user" {}
variable "vsphere_password" {}
variable "vsphere_server" {}
variable "vsphere_datacenter" {}
variable "vsphere_datastore" {}
variable "vsphere_resource_pool" {}
variable "vsphere_network" {}
variable "vm_template" {}
variable "vm_name" {}
variable "vm_vcpu" {}
variable "vm_memory" {}
variable "vm_mac_address" {}
variable "vm_disk1_size" {}
variable "vm_domain" {}
variable "vm_time_zone" {}
variable "artifactory_version" {}
variable "postgres_jdbc_version" {}
variable "mysql_jdbc_version" {}
variable "mariadb_jdbc_version" {}
variable "mariadb_password" {}
variable "db_host" {}
variable "db_password" {}
variable "ssh_user" {}

provider "vsphere" {
  version        = "~> 1.6"
  user           = "${var.vsphere_user}"
  password       = "${var.vsphere_password}"
  vsphere_server = "${var.vsphere_server}"

  # if you have a self-signed cert
  allow_unverified_ssl = true
}

provider "template" {
  version = "~> 1.0"
}

# Change artifactory.conf.tpl variables before upload
data "template_file" "nginx" {
  template = "${file("templates/artifactory.conf.tpl")}"

  vars {
    artifactory_url = "${var.vm_name}.${var.vm_domain}"
  }
}

data "vsphere_datacenter" "dc" {
  name = "${var.vsphere_datacenter}"
}

data "vsphere_datastore" "datastore" {
  name          = "${var.vsphere_datastore}"
  datacenter_id = "${data.vsphere_datacenter.dc.id}"
}

data "vsphere_resource_pool" "pool" {
  name          = "${var.vsphere_resource_pool}"
  datacenter_id = "${data.vsphere_datacenter.dc.id}"
}

data "vsphere_network" "network" {
  name          = "${var.vsphere_network}"
  datacenter_id = "${data.vsphere_datacenter.dc.id}"
}

data "vsphere_virtual_machine" "template" {
  name          = "${var.vm_template}"
  datacenter_id = "${data.vsphere_datacenter.dc.id}"
}

resource "vsphere_virtual_machine" "vm" {
  name             = "${var.vm_name}"
  resource_pool_id = "${data.vsphere_resource_pool.pool.id}"
  datastore_id     = "${data.vsphere_datastore.datastore.id}"

  num_cpus = "${var.vm_vcpu}"
  memory   = "${var.vm_memory}"
  guest_id = "${data.vsphere_virtual_machine.template.guest_id}"

  scsi_type = "${data.vsphere_virtual_machine.template.scsi_type}"

  network_interface {
    network_id     = "${data.vsphere_network.network.id}"
    adapter_type   = "${data.vsphere_virtual_machine.template.network_interface_types[0]}"
    use_static_mac = true
    mac_address    = "${var.vm_mac_address}"
  }

  disk {
    label            = "disk0"
    size             = "${data.vsphere_virtual_machine.template.disks.0.size}"
    eagerly_scrub    = "${data.vsphere_virtual_machine.template.disks.0.eagerly_scrub}"
    thin_provisioned = "${data.vsphere_virtual_machine.template.disks.0.thin_provisioned}"
  }

  disk {
    label            = "disk1"
    size             = "${var.vm_disk1_size}"
    eagerly_scrub    = false
    thin_provisioned = true
    unit_number      = 1
  }

  clone {
    template_uuid = "${data.vsphere_virtual_machine.template.id}"

    customize {
      linux_options {
        host_name = "${var.vm_name}"
        domain    = "${var.vm_domain}"
        time_zone = "${var.vm_time_zone}"
      }

      network_interface {}
    }
  }

  # Upload conf for nginx
  provisioner "file" {
    content     = "${data.template_file.nginx.rendered}"
    destination = "/tmp/artifactory.conf"
  }

  # Upload SSL keys for nginx
  provisioner "file" {
    source      = "ssl_keys/"
    destination = "/tmp/"
  }

  # Run commands with remote-exec over ssh
  provisioner "remote-exec" {
    inline = [
      "sudo hostnamectl set-hostname ${var.vm_name}.${var.vm_domain}",
      "sudo apt-get update",
      "sudo apt-get upgrade -y",
      "sudo apt-get autoremove -y",
      "sudo mkdir -p /var/opt/jfrog/artifactory/data/",
      "sudo mkfs.ext4 /dev/sdb",
      "UUID=$(sudo blkid -o value -s UUID /dev/sdb)",
      "echo \"UUID=$UUID /var/opt/jfrog/artifactory/data ext4 defaults 0 0\" | sudo tee -a /etc/fstab",
      "sudo mount -a",
      "sudo groupadd --gid 1001 artifactory",
      "sudo adduser --gid 1001 --uid 1001 --disabled-password -gecos \"Artifactory\" artifactory",
      "sudo chmod 0750 /var/opt/jfrog/artifactory/data/",
      "sudo chown -R artifactory:artifactory /var/opt/jfrog",
      "echo postfix postfix/mailname string '${var.vm_name}.${var.vm_domain}' | sudo debconf-set-selections",
      "echo postfix postfix/main_mailer_type string 'Local only' | sudo debconf-set-selections",
      "sudo apt-get install -y postfix",
      "sudo sed -i 's/inet_protocols = all/inet_protocols = ipv4/' /etc/postfix/main.cf",
      "sudo systemctl enable postfix",
      "sudo systemctl restart postfix",
      "sudo sh -c 'echo deb http://nginx.org/packages/ubuntu/ xenial nginx > /etc/apt/sources.list.d/nginx.list'",
      "sudo sh -c 'echo deb-src http://nginx.org/packages/ubuntu/ xenial nginx >> /etc/apt/sources.list.d/nginx.list'",
      "curl -O https://nginx.org/keys/nginx_signing.key && sudo apt-key add ./nginx_signing.key",
      "rm -f nginx_signing.key",
      "sudo apt-get update",
      "sudo apt-get install -y nginx",
      "sudo rm -f /etc/nginx/conf.d/default.conf",
      "sudo mv -f /tmp/artifactory.conf /etc/nginx/conf.d/artifactory.conf",
      "sudo chown root:root /etc/nginx/conf.d/artifactory.conf",
      "sudo chmod 644 /etc/nginx/conf.d/artifactory.conf",
      "sudo mkdir -p /etc/nginx/ssl",
      "sudo chmod 700 /etc/nginx/ssl",
      "sudo mv -f /tmp/*.crt /etc/nginx/ssl/${var.vm_name}.${var.vm_domain}.crt",
      "sudo mv -f /tmp/*.key /etc/nginx/ssl/${var.vm_name}.${var.vm_domain}.key",
      "sudo systemctl enable nginx",
      "sudo systemctl restart nginx",
      "sudo apt-get install -y openjdk-8-jre-headless",
      # OSS
      "echo 'deb https://jfrog.bintray.com/artifactory-debs xenial main' | sudo tee -a /etc/apt/sources.list",
      "curl https://bintray.com/user/downloadSubjectPublicKey?username=jfrog | sudo apt-key add -",
      "sudo apt-get update -qy",
      "sudo apt-get install -y jfrog-artifactory-oss=${var.artifactory_version}",
      # Pro
      #"echo 'deb https://jfrog.bintray.com/artifactory-pro-debs xenial main' | sudo tee -a /etc/apt/sources.list",
      #"curl https://bintray.com/user/downloadSubjectPublicKey?username=jfrog | sudo apt-key add -",
      #"sudo apt-get update -qy",
      #"sudo apt-get install -y jfrog-artifactory-pro=${var.artifactory_version}",
      # DB Setup
      ### PostgreSQL
      #"wget https://jdbc.postgresql.org/download/postgresql-${var.postgres_jdbc_version}.jar",
      #"sudo mv postgresql-${var.postgres_jdbc_version}.jar /var/opt/jfrog/artifactory/tomcat/lib/",
      #"sudo cp /opt/jfrog/artifactory/misc/db/postgresql.properties /etc/opt/jfrog/artifactory/db.properties",
      ### MySQL
      #"sudo apt-get install -y mysql-client",
      #"wget https://dev.mysql.com/get/Downloads/Connector-J/mysql-connector-java-${var.mysql_jdbc_version}.zip",
      #"unzip mysql-connector-java-${var.mysql_jdbc_version}.zip",
      #"sudo mv mysql-connector-java-${var.mysql_jdbc_version}/mysql-connector-java-${var.mysql_jdbc_version}.jar /var/opt/jfrog/artifactory/tomcat/lib/",
      #"rm -rf mysql-connector-java-*",
      #"sudo cp /opt/jfrog/artifactory/misc/db/mysql.properties /etc/opt/jfrog/artifactory/db.properties",
      ### MariaDB
      "sudo apt-get install -y mariadb-client",
      "wget https://downloads.mariadb.com/Connectors/java/connector-java-${var.mariadb_jdbc_version}/mariadb-java-client-${var.mariadb_jdbc_version}.jar",
      "sudo mv mariadb-java-client-${var.mariadb_jdbc_version}.jar /var/opt/jfrog/artifactory/tomcat/lib/",
      "sudo cp /opt/jfrog/artifactory/misc/db/mariadb.properties /etc/opt/jfrog/artifactory/db.properties",
      "mysql -u root -p'${var.mariadb_password}' -h ${var.db_host} -e \"CREATE DATABASE artifactory CHARACTER SET utf8 COLLATE utf8_bin;\"",
      "mysql -u root -p'${var.mariadb_password}' -h ${var.db_host} -e \"GRANT ALTER, CREATE, CREATE VIEW, DELETE, DROP, INDEX, INSERT, REFERENCES, SELECT, SHOW VIEW, TRIGGER, UPDATE ON artifactory.* TO 'artifactory'@'%' IDENTIFIED BY '${var.db_password}';\"",
      # Post DB
      "sudo chown root:root /var/opt/jfrog/artifactory/tomcat/lib/*.jar",
      "sudo sed -i 's/localhost/${var.db_host}/' /etc/opt/jfrog/artifactory/db.properties",
      "sudo sed -i 's/=password/=${var.db_password}/' /etc/opt/jfrog/artifactory/db.properties",
      "sudo sed -i 's/artdb/artifactory/' /etc/opt/jfrog/artifactory/db.properties",
      "sudo chown artifactory:artifactory /etc/opt/jfrog/artifactory/db.properties",
      "sudo chmod 640 /etc/opt/jfrog/artifactory/db.properties",
      "sudo systemctl start artifactory",
    ]
  }

  connection {
    type        = "ssh"
    private_key = "${file("~/.ssh/id_rsa")}"
    user        = "${var.ssh_user}"
    agent       = false
  }
}
