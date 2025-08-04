variable "aws_region" {
  default = "eu-north-1"
}

variable "ami_id" {
  description = "Ubuntu AMI ID"
  default     = "ami-07a0715df72e58928" # Ubuntu 22.04 in eu-north-1
}

variable "key_name" {
  description = "Name of your AWS key pair"
}

variable "private_key_path" {
  description = "Path to your private key file"
}
