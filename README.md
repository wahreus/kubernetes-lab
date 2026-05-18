# ⎈ Kubernetes Lab

A Kubernetes practice repo built in preparation for the Certified Kubernetes Administrator (CKA) exam, focused on workloads, networking, storage, RBAC, scheduling, and troubleshooting.

## Environment setup

The lab uses local `kubectl` with remote AWS EC2 instances for the Kubernetes control-plane node and worker node. Terraform defines the AWS infrastructure, while the helper scripts handle the setup and teardown workflow.

`build_lab.sh`
- Provisions the AWS resources with Terraform.
- Prepares SSH access.
- Opens terminals to the nodes.

`destroy_lab.sh`
- Removes the AWS resources.
- Cleans up local connection files.

The scripts intentionally omit Kubernetes installation steps to support cluster setup practice. A diagram of the environment setup is shown in Figure 1.

<p align="center">
  <img src="figures/environment_setup_diagram.svg" alt="Diagram showing local kubectl connecting over SSH to two AWS EC2 instances used as Kubernetes nodes.">
  <br>
  <em>Figure 1: Environment setup.</em>
</p>