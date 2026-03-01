output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.frontend.id
}

output "public_ip" {
  description = "Public IP address of the frontend EC2 instance"
  value       = aws_instance.frontend.public_ip
}

output "frontend_url" {
  description = "URL to access the frontend (Streamlit on port 8501)"
  value       = "http://${aws_instance.frontend.public_ip}:8501"
}
