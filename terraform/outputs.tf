output "app_url" {
  description = "Open this in a browser once the instances finish bootstrapping (about 5 minutes)"
  value       = "http://${aws_lb.web.dns_name}"
}

output "bastion_public_ip" {
  description = "SSH jump host: ssh -J ec2-user@<this> ec2-user@<private-ip>"
  value       = aws_instance.bastion.public_ip
}

output "private_ips" {
  description = "Private IPs of each tier"
  value = {
    frontend = aws_instance.frontend.private_ip
    backend  = aws_instance.backend.private_ip
    mysql    = aws_instance.mysql.private_ip
  }
}

output "db_app_password" {
  description = "Generated MySQL password for the bagtrace user (terraform output -raw db_app_password)"
  value       = random_password.db_app.result
  sensitive   = true
}
