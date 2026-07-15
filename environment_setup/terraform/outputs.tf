output "control_plane_public_ip" {
  description = "Public IPv4 address of the control-plane node."
  value       = aws_instance.node["control-plane"].public_ip
}

output "worker_a_public_ip" {
  description = "Public IPv4 address of worker-a."
  value       = aws_instance.node["worker-a"].public_ip
}

output "worker_b_public_ip" {
  description = "Public IPv4 address of worker-b."
  value       = aws_instance.node["worker-b"].public_ip
}

output "node_public_ips" {
  description = "Public IPv4 addresses keyed by node name."
  value = {
    for name, node in aws_instance.node : name => node.public_ip
  }
}

output "worker_public_ips" {
  description = "Public IPv4 addresses of the worker nodes."
  value = {
    worker-a = aws_instance.node["worker-a"].public_ip
    worker-b = aws_instance.node["worker-b"].public_ip
  }
}

output "control_plane_private_ip" {
  description = "Private IPv4 address of the control-plane node."
  value       = aws_instance.node["control-plane"].private_ip
}

output "worker_a_private_ip" {
  description = "Private IPv4 address of worker-a."
  value       = aws_instance.node["worker-a"].private_ip
}

output "worker_b_private_ip" {
  description = "Private IPv4 address of worker-b."
  value       = aws_instance.node["worker-b"].private_ip
}

output "node_private_ips" {
  description = "Private IPv4 addresses keyed by node name."
  value = {
    for name, node in aws_instance.node : name => node.private_ip
  }
}

output "ssh_control_plane" {
  description = "Direct SSH command for the control-plane node."
  value       = "ssh ubuntu@${aws_instance.node["control-plane"].public_ip}"
}

output "ssh_worker_a" {
  description = "Direct SSH command for worker-a."
  value       = "ssh ubuntu@${aws_instance.node["worker-a"].public_ip}"
}

output "ssh_worker_b" {
  description = "Direct SSH command for worker-b."
  value       = "ssh ubuntu@${aws_instance.node["worker-b"].public_ip}"
}

output "kubeadm_api_endpoint_hint" {
  description = "Suggested public control-plane endpoint for kubeadm and local kubectl access."
  value       = "${aws_instance.node["control-plane"].public_ip}:6443"
}
