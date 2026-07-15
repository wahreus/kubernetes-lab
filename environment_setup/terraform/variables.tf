variable "aws_region" {
  description = "AWS region where the lab will be created."
  type        = string
  default     = "eu-north-1"
}

variable "name_prefix" {
  description = "Name prefix for all lab resources."
  type        = string
  default     = "k8s-lab"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.name_prefix))
    error_message = "name_prefix may contain only lowercase letters, numbers, and hyphens."
  }
}

variable "control_plane_instance_type" {
  description = "EC2 instance type for the Kubernetes control-plane node."
  type        = string
  default     = "t3.medium"
}

variable "worker_instance_type" {
  description = "EC2 instance type for each Kubernetes worker node."
  type        = string
  default     = "t3.small"
}

variable "ssh_public_key" {
  description = "SSH public key material installed on the EC2 nodes."
  type        = string
  nullable    = false
  validation {
    condition     = length(trimspace(var.ssh_public_key)) > 0
    error_message = "ssh_public_key must not be empty."
  }
}

variable "allowed_access_cidr" {
  description = "CIDR allowed to reach SSH, the Kubernetes API, and NodePorts. Prefer your public IP as x.x.x.x/32."
  type        = string
  nullable    = false
  validation {
    condition     = can(cidrhost(var.allowed_access_cidr, 0))
    error_message = "allowed_access_cidr must be a valid CIDR block, for example 203.0.113.10/32."
  }
}

variable "root_volume_size" {
  description = "Root disk size in GiB for each EC2 instance."
  type        = number
  default     = 30
  validation {
    condition     = var.root_volume_size >= 20 && floor(var.root_volume_size) == var.root_volume_size
    error_message = "root_volume_size must be a whole number of at least 20 GiB."
  }
}

variable "kubernetes_minor_version" {
  description = "Kubernetes minor release channel used by pkgs.k8s.io, for example v1.36."
  type        = string
  default     = "v1.36"
  validation {
    condition     = can(regex("^v1\\.[0-9]+$", var.kubernetes_minor_version))
    error_message = "kubernetes_minor_version must use the form v1.36."
  }
}

variable "crictl_version" {
  description = "crictl release installed on each node, for example v1.36.0."
  type        = string
  default     = "v1.36.0"
  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.crictl_version))
    error_message = "crictl_version must use the form v1.36.0."
  }
}
