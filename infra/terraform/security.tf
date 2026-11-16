

# ---------- Grupos (sem regras inline) ----------
resource "aws_security_group" "app_access" {
  name        = "nginx-access"
  description = "Permite acesso publico ao Nginx"
  vpc_id      = aws_vpc.vpc_miguel_aluguel.id
  tags        = { Name = "nginx-access" }
}

resource "aws_security_group" "front-pi" {
  name        = "front-pi"
  description = "Permite acesso ao frontend apenas para o nginx"
  vpc_id      = aws_vpc.vpc_miguel_aluguel.id
  tags        = { Name = "front-pi" }
}

resource "aws_security_group" "back-pi" {
  name        = "back-pi"
  description = "Permite acesso ao backend apenas para o nginx"
  vpc_id      = aws_vpc.vpc_miguel_aluguel.id
  tags        = { Name = "back-pi" }
}

resource "aws_security_group" "rds-pi" {
  name        = "database"
  description = "Libera PostgreSQL apenas para o ECS Backend"
  vpc_id      = aws_vpc.vpc_miguel_aluguel.id
  tags        = { Name = "database" }
}

# ---------- Nginx (app_access) ----------
resource "aws_vpc_security_group_ingress_rule" "app_http" {
  security_group_id = aws_security_group.app_access.id
  description       = "HTTP"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "app_https" {
  security_group_id = aws_security_group.app_access.id
  description       = "HTTPS"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "app_to_front" {
  security_group_id            = aws_security_group.app_access.id
  description                  = "Acesso ao frontend"
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.front-pi.id
}

resource "aws_vpc_security_group_egress_rule" "app_to_back" {
  security_group_id            = aws_security_group.app_access.id
  description                  = "Acesso ao backend"
  from_port                    = 8080
  to_port                      = 8080
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.back-pi.id
}

# Saída para SSM (HTTPS) e atualizações do sistema
resource "aws_vpc_security_group_egress_rule" "app_https_out" {
  security_group_id = aws_security_group.app_access.id
  description       = "HTTPS para SSM e atualizacoes"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

# Repositórios apt do Ubuntu usam HTTP
resource "aws_vpc_security_group_egress_rule" "app_http_out" {
  security_group_id = aws_security_group.app_access.id
  description       = "HTTP para repositorios apt (Ubuntu)"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

# ---------- Frontend ----------
resource "aws_vpc_security_group_ingress_rule" "front_from_nginx" {
  security_group_id            = aws_security_group.front-pi.id
  description                  = "HTTP do nginx"
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.app_access.id
}

resource "aws_vpc_security_group_egress_rule" "front_https" {
  security_group_id = aws_security_group.front-pi.id
  description       = "HTTPS para servicos externos"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

# ---------- Backend ----------
resource "aws_vpc_security_group_ingress_rule" "back_from_nginx" {
  security_group_id            = aws_security_group.back-pi.id
  description                  = "HTTP do Nginx"
  from_port                    = 8080
  to_port                      = 8080
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.app_access.id
}

resource "aws_vpc_security_group_egress_rule" "back_https" {
  security_group_id = aws_security_group.back-pi.id
  description       = "HTTPS para servicos externos"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

# Backend -> RDS 
resource "aws_vpc_security_group_egress_rule" "back_to_rds" {
  security_group_id            = aws_security_group.back-pi.id
  description                  = "PostgreSQL para o RDS"
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.rds-pi.id
}

# ---------- RDS ----------
resource "aws_vpc_security_group_ingress_rule" "rds_from_back" {
  security_group_id            = aws_security_group.rds-pi.id
  description                  = "PostgreSQL do Backend"
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.back-pi.id
}
