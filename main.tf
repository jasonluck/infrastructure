# ---------------------------------------------------------------------------------------------------------------------
# CI ENVIRONMENT INFRASTRUCTURE
# This environment consists of:
# - Consul Cluster (Handles service discovery, health check, DNS and HA backend for Vault)
# - Vault Cluster  (Secret Storage)
# ---------------------------------------------------------------------------------------------------------------------

provider "aws" {
  region = "${var.aws_region}"
}

resource "aws_key_pair" "auth" {
  key_name   = "${var.ssh_key_name}"
  public_key = "${file(var.ssh_public_key_path)}"
}

# Terraform 0.9.5 suffered from https://github.com/hashicorp/terraform/issues/14399, which causes this template the
# conditionals in this template to fail.
terraform {
  required_version = ">= 0.9.3, != 0.9.5"
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPLOY A CONSUL CLUSTER IN AWS
# These templates show an example of how to use the consul-cluster module to deploy Consul in AWS. We deploy two Auto
# Scaling Groups (ASGs): one with a small number of Consul server nodes and one with a larger number of Consul client
# nodes. Note that these templates assume that the AMI you provide via the ami_id input variable is built from
# the [consul-ami](https://github.com/jasonluck/consul-ami) Packer template.
# ---------------------------------------------------------------------------------------------------------------------

data "aws_ami" "consul" {
  most_recent = true

  owners = ["${var.owner}"]

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "name"
    values = ["consul-amzn-linux-*"]
  }
}

module "consul_cluster" {
  source = "github.com/hashicorp/terraform-aws-consul//modules/consul-cluster?ref=v0.1.0"

  vpc_id = "${var.vpc_id}"
  subnet_ids = ["${data.aws_subnet_ids.private.ids}"]
  ssh_key_name = "${aws_key_pair.auth.key_name}"
  ami_id = "${var.consul_ami_id == "" ? data.aws_ami.consul.image_id : var.consul_ami_id}"
  instance_type = "t2.medium"

  # To make testing easier, we allow requests from any IP address here but in a production deployment, we *strongly*
  # recommend you limit this to the IP address ranges of known, trusted servers inside your VPC.
  allowed_inbound_cidr_blocks = ["0.0.0.0/0"]
  allowed_ssh_cidr_blocks = ["0.0.0.0/0"]

  cluster_name  = "consul-dev"
  cluster_tag_key   = "consul-cluster"
  cluster_tag_value = "development"
  cluster_size = 3


  # Configure and start Consul during boot. It will automatically form a cluster with all nodes that have that same tag. 
  user_data = <<-EOF
              #!/bin/bash
              /opt/consul/bin/run-consul --server --cluster-tag-key consul-cluster --cluster-tag-value development
              EOF
}

# ---------------------------------------------------------------------------------------------------------------------
# THE USER DATA SCRIPT THAT WILL RUN ON EACH CONSUL SERVER WHEN IT'S BOOTING
# This script will configure and start Consul
# ---------------------------------------------------------------------------------------------------------------------

data "template_file" "user_data_consul" {
  template = "${file("${path.module}/scripts/user-data-consul.sh")}"

  vars {
    consul_cluster_tag_key   = "${var.consul_cluster_tag_key}"
    consul_cluster_tag_value = "${var.consul_cluster_name}"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPLOY A VAULT CLUSTER IN AWS
# These templates show an example of how to use the vault-consul-cluster module to deploy Vault in AWS. We deploy two Auto
# Scaling Groups (ASGs): one with a small number of Consul server nodes and one with a larger number of Consul client
# nodes. Note that these templates assume that the AMI you provide via the ami_id input variable is built from
# the [consul-ami](https://github.com/jasonluck/consul-ami) Packer template.
# ---------------------------------------------------------------------------------------------------------------------

data "aws_ami" "vault_consul" {
  most_recent      = true

  owners     = ["${var.owner}"]

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "name"
    values = ["vault-consul-amzn-linux-*"]
  }
}

module "vault_cluster" {
  source = "github.com/hashicorp/terraform-aws-vault.git//modules/vault-cluster?ref=v0.0.8"

  cluster_name  = "vault-dev"
  cluster_size  = 3
  instance_type = "t2.medium"

  ami_id    = "${var.vault_ami_id == "" ? data.aws_ami.vault_consul.image_id : var.vault_ami_id}"
  user_data = "${data.template_file.user_data_vault_cluster.rendered}"

  s3_bucket_name          = "${var.s3_bucket_name}"
  force_destroy_s3_bucket = "${var.force_destroy_s3_bucket}"

  vpc_id     = "${var.vpc_id}"
  subnet_ids = ["${data.aws_subnet_ids.private.ids}"]

  # Tell each Vault server to register in the ELB.
  //load_balancers = ["${module.vault_elb.load_balancer_name}"]

  # Do NOT use the ELB for the ASG health check, or the ASG will assume all sealed instances are unhealthy and
  # repeatedly try to redeploy them.
  health_check_type = "EC2"

  # To make testing easier, we allow requests from any IP address here but in a production deployment, we *strongly*
  # recommend you limit this to the IP address ranges of known, trusted servers inside your VPC.

  allowed_ssh_cidr_blocks            = ["0.0.0.0/0"]
  allowed_inbound_cidr_blocks        = ["0.0.0.0/0"]
  allowed_inbound_security_group_ids = []
  ssh_key_name                       = "${aws_key_pair.auth.key_name}"
}

# ---------------------------------------------------------------------------------------------------------------------
# ATTACH IAM POLICIES FOR CONSUL
# To allow our Vault servers to automatically discover the Consul servers, we need to give them the IAM permissions from
# the Consul AWS Module's consul-iam-policies module.
# ---------------------------------------------------------------------------------------------------------------------

module "consul_iam_policies_servers" {
  source = "github.com/hashicorp/terraform-aws-consul.git//modules/consul-iam-policies?ref=v0.1.0"

  iam_role_id = "${module.vault_cluster.iam_role_id}"
}

# ---------------------------------------------------------------------------------------------------------------------
# THE USER DATA SCRIPT THAT WILL RUN ON EACH VAULT SERVER WHEN IT'S BOOTING
# This script will configure and start Vault
# ---------------------------------------------------------------------------------------------------------------------

data "template_file" "user_data_vault_cluster" {
  template = "${file("${path.module}/scripts/user-data-vault.sh")}"

  vars {
    aws_region               = "${var.aws_region}"
    s3_bucket_name           = "${var.s3_bucket_name}"
    consul_cluster_tag_key   = "${var.consul_cluster_tag_key}"
    consul_cluster_tag_value = "${var.consul_cluster_name}"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# GENERAL VPC CONFIGURATION
# ---------------------------------------------------------------------------------------------------------------------

data "aws_subnet_ids" "private" {
  vpc_id = "${var.vpc_id}"
  tags {
    Visibility = "private"
  }
}