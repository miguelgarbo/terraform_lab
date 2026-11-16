output "public_ip_access" {
  description = "IP público da instância Nginx utilizada como ponto de acesso à aplicação"

  value = aws_instance.ec2-nginx-pi.public_ip
}


output "public_ip_nat" {
  description = "IP público utilizado pelo NAT Gateway para saída das tarefas privadas para a internet"

  value = aws_eip.nat_eip.public_ip
}

# IP privado da instância de acesso
output "private_ip_nginx" {
  description = "IP privado da instância Nginx dentro da VPC"

  value = aws_instance.ec2-nginx-pi.private_ip
}

output "url_app" {
  description = "URL pública para acessar a aplicação Miguel Aluguel"

  value = "http://${aws_instance.ec2-nginx-pi.public_ip}/welcome"
}