
# Grupos de Segurança

#criação do security group para liberar o acesso a porta 22 apenas para meu IP
resource "aws_security_group" "ssh" {
  name        = "libera-ssh"
  description = "Libera SSH apenas para meu IP"
  vpc_id      = aws_vpc.vpc_miguel_aluguel.id
  # liberando acesso apenas do meu ip
  ingress {
    description = "SSH do meu IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  #permite total trafego de saida sem validação, pois é uma regra default do security group, mas é bom deixar explicito

  egress {
    description = "Permite trafego de saida"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "libera-ssh"
  }
}



resource "aws_security_group" "front-pi" {
  name        = "front-pi"
  description = "Permite acesso ao frontend apenas para o nginx"
  vpc_id      = aws_vpc.vpc_miguel_aluguel.id

  ingress {
    description     = "HTTP do nginx"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.app_access.id]
  }

  egress {
    description = "HTTPS para servicos externos"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_security_group" "back-pi" {
  name        = "back-pi"
  description = "Permite acesso ao backend apenas para o nginx"
  vpc_id      = aws_vpc.vpc_miguel_aluguel.id

  ingress {
    description     = "HTTP do Nginx"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.app_access.id]
  }

  egress {
    description     = "Acesso ao Banco"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.rds-pi.id]
  }

  egress {
    description = "HTTPS para servicos externos"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}



# acesso publico da aplicaçãp
resource "aws_security_group" "app_access" {
  name        = "nginx-access"
  description = "Permite acesso publico ao Nginx"
  vpc_id      = aws_vpc.vpc_miguel_aluguel.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description     = "Acesso ao frontend"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.front-pi.id]
  }

  egress {
    description     = "Acesso ao backend"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.back-pi.id]
  }
}

# --- BANCO DE DADOS RDS 
resource "aws_security_group" "rds-pi" {
  name        = "database"
  description = "Libera PostgreSQL apenas para o ECS Backend"
  vpc_id      = aws_vpc.vpc_miguel_aluguel.id

  ingress {
    description     = "PostgreSQL do Backend"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.back-pi.id]
  }
}
