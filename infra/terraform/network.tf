
# VPC Principal (10.20.0.0/20) - Espaço total: 10.20.0.0 a 10.20.15.255
resource "aws_vpc" "vpc_miguel_aluguel" {
  cidr_block = "10.20.0.0/20"

  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
      Name = "vpc_miguel_aluguel"
    }
  
}

# Subnet pública para o Nginx / ALB
# Faixa: 10.20.0.0/24 (IPs de 10.20.0.0 a 10.20.0.255)
resource "aws_subnet" "subnet-pub-1" {
  vpc_id                  = aws_vpc.vpc_miguel_aluguel.id
  cidr_block              = "10.20.0.0/24"
  map_public_ip_on_launch = true

  tags = {
      Name = "subnet-pub-1"
    }
  
}

resource "aws_subnet" "subnet-priv-1" {
  vpc_id            = aws_vpc.vpc_miguel_aluguel.id
  cidr_block        = "10.20.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "subnet-priv-1"
  }
}

resource "aws_subnet" "subnet-priv-2" {
  vpc_id            = aws_vpc.vpc_miguel_aluguel.id
  cidr_block        = "10.20.2.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "subnet-priv-2"
  }
}

# Subnet Group do RDS
resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "db-subnet-group"
  subnet_ids = [aws_subnet.subnet-priv-1.id, aws_subnet.subnet-priv-2.id]

  tags = {
    Name = "DB Subnet Group"
  }
}

# Internet Gateway
# criar o igw para liberar acesso a internet para a subnet pública 
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc_miguel_aluguel.id

  tags = {
    Name = "igw-miguel-aluguel"
  }
}

resource "aws_eip" "nat_eip" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.igw]

  tags = {
    Name = "eip-nat-miguel-aluguel"
  }
}

# NAT Gateway
# criar o NAT para liberar acesso a internet para a subnet privada 
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.subnet-pub-1.id 

  tags = {
    Name = "natzao-miguel-aluguel"
  }
}

## Tabela de rotas
# criação da tabela de rota, para referenciar o igw
#entao o fluxo fica quando a máquina tentar um ip que nao seja no range da vpc
#ele vai referenciar o igw para ter o acesso a internet
resource "aws_route_table" "rt_public" {
  vpc_id = aws_vpc.vpc_miguel_aluguel.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

## Tabela de rotas
# criação da tabela de rota, para referenciar o nat gateway
resource "aws_route_table" "rt_private" {
  vpc_id = aws_vpc.vpc_miguel_aluguel.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.nat.id
  }
}

# Associar as tabelas de rotas às subnets respectivas
resource "aws_route_table_association" "assoc-pb" {
  subnet_id      = aws_subnet.subnet-pub-1.id
  route_table_id = aws_route_table.rt_public.id
}

resource "aws_route_table_association" "assoc-priv" {
  subnet_id      = aws_subnet.subnet-priv-1.id
  route_table_id = aws_route_table.rt_private.id
}

resource "aws_route_table_association" "assoc-priv-2" {
  subnet_id      = aws_subnet.subnet-priv-2.id
  route_table_id = aws_route_table.rt_private.id
}

# Security Group
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

resource "aws_security_group" "app_access" {
  name        = "nginx-access"
  description = "Permite acesso a aplicacao"
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
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }


}


resource "aws_security_group" "front-pi" {
  name        = "front-pi"
  description = "Permite acesso ao frontend apenas para o nginx"
  vpc_id      = aws_vpc.vpc_miguel_aluguel.id

  ingress {
    description     = "HTTP"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.app_access.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_security_group" "back-pi" {
  name        = "back-pi"
  description = "Permite acesso ao backend apenas para o nginx"
  vpc_id      = aws_vpc.vpc_miguel_aluguel.id

  ingress {
    description     = "HTTP"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.app_access.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

}

# --- BANCO DE DADOS RDS 
resource "aws_security_group" "rds-pi" {
  name        = "database"
  description = "Libera PostgreSQL apenas para o ECS Backend"
  vpc_id      = aws_vpc.vpc_miguel_aluguel.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.back-pi.id]
  }
}

