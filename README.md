# ⎈ Kubernetes Lab

A Kubernetes practice repo built in preparation for the Certified Kubernetes Administrator (CKA) exam, focused on workloads, networking, storage, RBAC, scheduling, and troubleshooting.

## Environment setup

<p align="center">
  <img src="figures/environment_setup_diagram.svg" alt="Diagram showing local machine connecting to two AWS EC2 instances used as Kubernetes nodes.">
</p>

The lab uses local `kubectl` with remote AWS EC2 instances for the Kubernetes control plane node and worker node. Terraform defines the AWS infrastructure, while the helper scripts handle the setup and teardown workflow. The scripts intentionally omit Kubernetes installation steps to support cluster setup practice.

`build_lab.sh`
- Provisions the AWS resources with Terraform.
- Prepares SSH access.
- Opens terminals to the nodes.

`destroy_lab.sh`
- Removes the AWS resources.
- Cleans up local connection files.

> Please note that EC2 instances incur hourly costs. Always run `destroy_lab.sh` when you are finished with a practice session to avoid unnecessary charges.