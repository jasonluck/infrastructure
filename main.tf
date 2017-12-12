# ---------------------------------------------------------------------------------------------------------------------
# CI ENVIRONMENT INFRASTRUCTURE
# This environment consists of:
# - Consul Cluster (Handles service discovery, health check, DNS and HA backend for Vault)
# - Vault Cluster  (Secret Storage)
# ---------------------------------------------------------------------------------------------------------------------

provider "aws" {
  access_key = "${var.access_key}"
  secret_key = "${var.secret_key}"
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

module "consul_server" {
  source = "github.com/hashicorp/terraform-aws-consul//modules/consul-cluster?ref=v0.1.0"

  vpc_id = "${var.vpc_id}"
  subnet_ids = ["${data.aws_subnet_ids.private.ids}"]
  ssh_key_name = "${aws_key_pair.auth.key_name}"
  ami_id = "${var.consul_ami_id == "" ? data.aws_ami.consul.image_id : var.consul_ami_id}"
  instance_type = "t2.medium"
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

data "aws_subnet_ids" "private" {
  vpc_id = "${var.vpc_id}"
  tags {
    Visibility = "private"
  }
}