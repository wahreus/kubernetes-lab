# -----------------------------------------------------------------------------
# Provider
# -----------------------------------------------------------------------------

provider "aws" {
  region = var.aws_region
}


# -----------------------------------------------------------------------------
# Local values
# -----------------------------------------------------------------------------

locals {
  nodes = {
    "control-plane" = {
      role          = "control-plane"
      instance_type = var.control_plane_instance_type
    }
    "worker-a" = {
      role          = "worker"
      instance_type = var.worker_instance_type
    }
    "worker-b" = {
      role          = "worker"
      instance_type = var.worker_instance_type
    }
  }
}


# -----------------------------------------------------------------------------
# Ubuntu AMI
# -----------------------------------------------------------------------------

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}


# -----------------------------------------------------------------------------
# Network
# -----------------------------------------------------------------------------

resource "aws_vpc" "lab" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.name_prefix}-vpc"
  }
}

resource "aws_internet_gateway" "lab" {
  vpc_id = aws_vpc.lab.id

  tags = {
    Name = "${var.name_prefix}-igw"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = "10.20.1.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.name_prefix}-public-subnet"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.lab.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lab.id
  }

  tags = {
    Name = "${var.name_prefix}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}


# -----------------------------------------------------------------------------
# Security group
# -----------------------------------------------------------------------------

resource "aws_security_group" "lab" {
  name        = "${var.name_prefix}-sg"
  description = "Kubernetes lab access"
  vpc_id      = aws_vpc.lab.id

  ingress {
    description = "SSH from local machine"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  ingress {
    description = "Kubernetes API from local machine"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  ingress {
    description = "NodePort services from local machine"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  ingress {
    description = "All control, pod, and service traffic between lab nodes"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    description = "Outbound internet access"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name_prefix}-sg"
  }
}


# -----------------------------------------------------------------------------
# SSH key pair
# -----------------------------------------------------------------------------

resource "aws_key_pair" "lab" {
  key_name   = "${var.name_prefix}-key"
  public_key = file(pathexpand(var.public_key_path))

  tags = {
    Name = "${var.name_prefix}-key"
  }
}


# -----------------------------------------------------------------------------
# EC2 instances
# -----------------------------------------------------------------------------

resource "aws_instance" "node" {
  for_each = local.nodes

  ami                         = data.aws_ami.ubuntu.id
  instance_type               = each.value.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.lab.id]
  key_name                    = aws_key_pair.lab.key_name
  associate_public_ip_address = true
  user_data_replace_on_change = true

  user_data = <<-EOF
#!/usr/bin/env bash
set -euxo pipefail

hostnamectl set-hostname ${each.key}

apt-get update -y
apt-get install -y \
  ca-certificates \
  curl \
  gpg \
  lsb-release \
  apt-transport-https \
  tar

cat >/etc/modules-load.d/k8s.conf <<'MODULES'
overlay
br_netfilter
MODULES

modprobe overlay
modprobe br_netfilter

cat >/etc/sysctl.d/k8s.conf <<'SYSCTL'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
SYSCTL

sysctl --system

install -m 0755 -d /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc

chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  >/etc/apt/sources.list.d/docker.list

apt-get update -y
apt-get install -y containerd.io

mkdir -p /etc/containerd
containerd config default >/etc/containerd/config.toml

sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

systemctl enable --now containerd
systemctl restart containerd

CRICTL_VERSION="v1.36.0"
KUBERNETES_MINOR_VERSION="v1.36"

curl -fsSLo /tmp/crictl.tar.gz \
  "https://github.com/kubernetes-sigs/cri-tools/releases/download/$CRICTL_VERSION/crictl-$CRICTL_VERSION-linux-amd64.tar.gz"

tar -C /usr/local/bin -xzf /tmp/crictl.tar.gz
rm -f /tmp/crictl.tar.gz

cat >/etc/crictl.yaml <<'CRICTL_CONFIG'
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
CRICTL_CONFIG

curl -fsSL "https://pkgs.k8s.io/core:/stable:/$KUBERNETES_MINOR_VERSION/deb/Release.key" \
  | gpg --dearmor --batch --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

chmod a+r /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo \
  "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/$KUBERNETES_MINOR_VERSION/deb/ /" \
  >/etc/apt/sources.list.d/kubernetes.list

apt-get update -y
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

systemctl enable --now kubelet

containerd --version
crictl --version
crictl info
kubeadm version
kubelet --version
kubectl version --client=true
EOF

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
  }

  tags = {
    Name = "${var.name_prefix}-${each.key}"
    Role = each.value.role
  }
}