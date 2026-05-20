variable "aws_region" {
  description = "AWS region where the lab will be created."
  type        = string
  default     = "eu-north-1"
}

variable "name_prefix" {
  description = "Name prefix for all lab resources."
  type        = string
  default     = "k8s-lab"
}

variable "control_plane_instance_type" {
  description = "EC2 instance type for the Kubernetes control plane node."
  type        = string
  default     = "t3.medium"
}

variable "worker_instance_type" {
  description = "EC2 instance type for each Kubernetes worker node."
  type        = string
  default     = "t3.small"
}

variable "public_key_path" {
  description = "Path to your local SSH public key."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed to SSH to the nodes and reach the Kubernetes API/NodePorts. Prefer your public IP as x.x.x.x/32."
  type        = string
  nullable    = false
  validation {
    condition     = can(cidrhost(var.allowed_ssh_cidr, 0))
    error_message = "allowed_ssh_cidr must be a valid CIDR block, for example 203.0.113.10/32."
  }
}

variable "root_volume_size" {
  description = "Root disk size in GiB for each EC2 instance."
  type        = number
  default     = 30
}
