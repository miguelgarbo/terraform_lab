terraform {

  # aqui é aonde definimos o provider para ser instalado ao rodar terraform init,
  # essa infra é baseada na AWS, então vamos usar o provider da AWS
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
# definicao qual regiao da AWS sera utilizada para criar os recursos
# aqui é inicializado a variavel que foi criada no arquivo variables.tf
provider "aws" {
  region = var.aws_region
}

#aqui nada é criado e sim consultado para pegar o ID da AMI mais recente do Ubuntu Server
data "aws_ami" "ubuntu" {
  most_recent = true
  
  #busca a ami do ubuntu da empresa canonical
  owners = ["099720109477"] # canonical empresa responsável pelo Ubuntu

  # filtrando  a busca com a versão 24.04 
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

# VPC
#criação da rede isolada para nossa infra, ele deve ser o primeiro recurso na infra
#pois todos os recursos ficarão atrelados a ele
resource "aws_vpc" "vpc_lab" {
  cidr_block = "10.0.0.0/16"

# utilizando tags para identificar o recurso, e também para poder filtrar recursos com tags
#o uso do merge foi para manter um padrão criado no arquivo locals.tf,
# onde criamos um bloco de tags comuns para todos os recursos
  tags = merge(  
    local.common_tags,
    {
    Name = "vpc_lab"
  }
  )
}

# Subnet pública
resource "aws_subnet" "subnet_pub_lab" {
  #aqui referenciamos o resource criado a cima, perceba a hierarquia na sintaxe,
  # o nome do recurso e dps o nome que atribuimos a ele com a chave referenciada
  # que aqui no caso é o ID
  vpc_id                  = aws_vpc.vpc_lab.id
  cidr_block              = "10.0.1.0/24"
  # É isso que torna a subnet pública, junto com o fato de você atribuir IP público às instâncias
  map_public_ip_on_launch = true

  tags = {
    Name = "subnet_pub_lab"
  }
}

# Subnet privada para backend e banco
resource "aws_subnet" "subnet_priv_lab" {
  vpc_id     = aws_vpc.vpc_lab.id
  cidr_block = "10.0.2.0/24"

  # Instâncias desta subnet não recebem IP público
  map_public_ip_on_launch = false

  tags = merge(
    local.common_tags,
    {
      Name = "subnet_priv_lab"
    }
  )
}

# Internet Gateway
# criar o igw para liberar acesso a internet para a subnet pública 
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc_lab.id

  tags = {
    Name = "meu-igw"
  }
}

## Tabela de rotas
# criação da tabela de rota, para referenciar o igw
#entao o fluxo fica quando a máquina tentar um ip que nao seja no range da vpc
#ele vai referenciar o igw para ter o acesso a internet
resource "aws_route_table" "rt_public" {
  vpc_id = aws_vpc.vpc_lab.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

# Associar a tabela de rotas à subnet
# de novo associando o recurso com o nome que demos
resource "aws_route_table_association" "associacao" {
  subnet_id      = aws_subnet.subnet_pub_lab.id
  route_table_id = aws_route_table.rt_public.id
}

# Security Group
#criação do security group para liberar o acesso a porta 22 apenas para meu IP
resource "aws_security_group" "ssh" {
  name        = "libera-ssh"
  description = "Libera SSH apenas para meu IP"
  vpc_id      = aws_vpc.vpc_lab.id
 # liberando acesso apenas do meu ip
  ingress {
    description = "SSH do meu IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["177.73.97.182/32"]
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

resource "aws_security_group" "frontend_sg" {
  name        = "frontend-sg"
  description = "Permite acesso ao frontend"
  vpc_id      = aws_vpc.vpc_lab.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH do meu IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["201.89.76.26/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "frontend-sg"
  }
}

resource "aws_key_pair" "lab" {
  key_name = "terraform-lab"

  public_key = file(
    pathexpand("~/.ssh/terraform-lab.pub")
  )
}

resource "aws_instance" "ec2_frontend" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.subnet_pub_lab.id

  # Associa nosso Key Pair à EC2
  key_name = aws_key_pair.lab.key_name

  vpc_security_group_ids = [
    aws_security_group.ssh.id
  ]

  user_data = <<-EOF
              #!/bin/bash

              apt-get update -y
              apt-get install -y docker.io

              systemctl enable docker
              systemctl start docker

              usermod -aG docker ubuntu
              EOF

  tags = {
    Name = "ec2-lab"
  }
}