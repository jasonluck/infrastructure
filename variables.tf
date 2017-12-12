
variable "vpc_id" {
    description = "ID for the VPC"
    default     = "vpc-ae6ac2cb"
}

variable "subnet_ids" {
    description = "ID for the Utility VPC private subnet"
    default     = "subnet-025d7a67"
}

variable "aws_region" {
  description = "AWS region to launch servers."
  default     = "us-gov-west-1"
}

variable "access_key" {
    description = "AWS Access Key"
}

variable "secret_key" {
    description = "AWS Secret Key"
}

variable "owner" {
    description = "AMI Owner"
    default = "272417811699"
}

variable "ssh_public_key_path" {
  description = <<DESCRIPTION
Path to the SSH public key to be used for authentication.
Ensure this keypair is added to your local SSH agent so provisioners can
connect.

Example: ~/.ssh/terraform.pub
DESCRIPTION
}

variable "ssh_key_name" {
  description = "Desired name of AWS key pair"
}


variable "consul_ami_id" {
  description = "Id of the consul AMI to use."
  default = ""
}