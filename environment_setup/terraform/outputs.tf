output "control_plane_public_ip" {
  value = aws_instance.node["control-plane"].public_ip
}

output "worker_public_ip" {
  value = aws_instance.node["worker"].public_ip
}

output "control_plane_private_ip" {
  value = aws_instance.node["control-plane"].private_ip
}

output "worker_private_ip" {
  value = aws_instance.node["worker"].private_ip
}

output "ssh_control_plane" {
  value = "ssh ubuntu@${aws_instance.node["control-plane"].public_ip}"
}

output "ssh_worker" {
  value = "ssh ubuntu@${aws_instance.node["worker"].public_ip}"
}

output "kubeadm_api_endpoint_hint" {
  value = "Use the control-plane public IP as the --control-plane-endpoint if you want kubectl from your local machine: ${aws_instance.node["control-plane"].public_ip}:6443"
}
