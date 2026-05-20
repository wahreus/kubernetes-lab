output "control_plane_public_ip" {
  value = aws_instance.node["control-plane"].public_ip
}

output "worker_a_public_ip" {
  value = aws_instance.node["worker-a"].public_ip
}

output "worker_b_public_ip" {
  value = aws_instance.node["worker-b"].public_ip
}

output "node_public_ips" {
  value = {
    for name, node in aws_instance.node : name => node.public_ip
  }
}

output "worker_public_ips" {
  value = {
    worker-a = aws_instance.node["worker-a"].public_ip
    worker-b = aws_instance.node["worker-b"].public_ip
  }
}

output "control_plane_private_ip" {
  value = aws_instance.node["control-plane"].private_ip
}

output "worker_a_private_ip" {
  value = aws_instance.node["worker-a"].private_ip
}

output "worker_b_private_ip" {
  value = aws_instance.node["worker-b"].private_ip
}

output "node_private_ips" {
  value = {
    for name, node in aws_instance.node : name => node.private_ip
  }
}

output "ssh_control_plane" {
  value = "ssh ubuntu@${aws_instance.node["control-plane"].public_ip}"
}

output "ssh_worker_a" {
  value = "ssh ubuntu@${aws_instance.node["worker-a"].public_ip}"
}

output "ssh_worker_b" {
  value = "ssh ubuntu@${aws_instance.node["worker-b"].public_ip}"
}

output "kubeadm_api_endpoint_hint" {
  value = "Use the control-plane public IP as the --control-plane-endpoint if you want kubectl from your local machine: ${aws_instance.node["control-plane"].public_ip}:6443"
}
