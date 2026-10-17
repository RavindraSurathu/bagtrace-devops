variable "project" {
  description = "Name used as a prefix for every resource"
  type        = string
  default     = "bagtrace"
}

variable "environment" {
  description = "Environment name, e.g. dev or prod"
  type        = string
  default     = "dev"
}

variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-south-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.20.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Public subnets (load balancer, bastion, NAT), one per AZ"
  type        = list(string)
  default     = ["10.20.1.0/24", "10.20.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private subnets for the web and app tiers, one per AZ"
  type        = list(string)
  default     = ["10.20.11.0/24", "10.20.12.0/24"]
}

variable "database_subnet_cidrs" {
  description = "Isolated subnets for the database tier, one per AZ"
  type        = list(string)
  default     = ["10.20.21.0/24", "10.20.22.0/24"]
}

variable "instance_type" {
  description = "EC2 instance type for all tiers"
  type        = string
  default     = "t3.micro"
}

variable "ami_id" {
  description = "Optional AMI override; defaults to the latest RHEL 9 image"
  type        = string
  default     = ""
}

variable "key_name" {
  description = "Existing EC2 key pair used to SSH via the bastion"
  type        = string
}

variable "admin_cidr" {
  description = "Your public IP in CIDR form, allowed to SSH to the bastion (e.g. 203.0.113.10/32)"
  type        = string

  validation {
    condition     = can(cidrhost(var.admin_cidr, 0)) && var.admin_cidr != "0.0.0.0/0"
    error_message = "admin_cidr must be a valid CIDR and must not be 0.0.0.0/0."
  }
}

variable "repo_url" {
  description = "Git repository the instances clone to run the install scripts"
  type        = string
  default     = "https://github.com/RavindraSurathu/bagtrace-devops.git"
}
