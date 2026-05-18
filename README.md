# ⎈ Kubernetes Lab

A Kubernetes practice repo built in preparation for the Certified Kubernetes Administrator (CKA) exam, focused on workloads, networking, storage, RBAC, scheduling, and troubleshooting.

## Environment setup

The lab uses local `kubectl` with remote AWS EC2 instances for the Kubernetes control plane and a worker node. Terraform defines the AWS infrastructure, while the helper scripts handle setup and teardown.

- `build_lab.sh` provisions the AWS resources with Terraform, prepares SSH access, and opens terminals to the nodes.
- `destroy_lab.sh` removes the AWS resources and cleans up local connection files.