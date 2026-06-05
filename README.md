# ⎈ Kubernetes Lab

A Kubernetes practice repo built in preparation for the Certified Kubernetes Administrator (CKA) exam, focused on workloads, networking, storage, RBAC, scheduling, and troubleshooting.

It currently contains two practice components:

- An EC2-based Kubernetes lab environment for hands-on practice
- KubeRun, a command-speed practice game

## Environment setup

<p align="center">
  <img src="figures/environment_setup_diagram.svg" alt="Diagram showing local machine connecting to three AWS EC2 instances used as Kubernetes nodes.">
</p>

The lab uses local `kubectl` with remote AWS EC2 instances for the Kubernetes control plane node and worker nodes. Terraform defines the AWS infrastructure, while the helper scripts handle the setup and teardown workflow.

### build_lab.sh

* Provisions the AWS resources with Terraform
* Installs `containerd`, `crictl`, `kubeadm`, `kubelet`, and `kubectl` on each node
* Prepares SSH access
* Opens terminals to the nodes

After `build_lab.sh` has finished, the EC2 instances are ready for Kubernetes bootstrap, but the cluster has not been initialized yet. This is intentional: `kubeadm init`, CNI installation, `kubeadm join`, and local kubeconfig setup are left as manual practice steps.

### destroy_lab.sh
- Removes the AWS resources
- Cleans up local connection files

> **Note:** EC2 instances incur hourly costs. Always run `destroy_lab.sh` when you are finished with a practice session to avoid unnecessary charges.

### Requirements

- AWS account with EC2 and VPC permissions
- AWS CLI configured
- Terraform installed
- Ed25519 SSH key pair available for EC2 access
- `kubectl` installed

## KubeRun

KubeRun is a command-speed game for Kubernetes and CKA practice. It helps you build speed with common `kubectl` and `kubeadm` commands for administration, troubleshooting, node maintenance, RBAC checks, and cluster setup.

You are shown task descriptions in a randomized order, and the goal is to type as many correct commands as possible within 5 minutes. No commands are executed, KubeRun is only for practice. The game covers 35 common Kubernetes and CKA-style commands for:

- inspecting and troubleshooting resources
- applying and editing resources
- managing deployments and rollouts
- exposing workloads with services
- checking endpoints and cluster events
- working with ConfigMaps and Secrets
- inspecting PVCs and StorageClasses
- opening shell sessions in pods
- switching contexts
- checking permissions
- maintaining nodes with drain, cordon, uncordon, taints, and labels
- managing cluster lifecycle with `kubeadm`


> **Disclaimer:** KubeRun is an independently developed practice tool and is not affiliated with CNCF, The Linux Foundation, or the Kubernetes project. It is intended for command-recall practice only and does not cover the full CKA curriculum.

### Requirements

- Python 3
- macOS/Linux terminal