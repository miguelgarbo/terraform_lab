
resource "aws_db_instance" "postgres_rds" {
  identifier             = "miguel-aluguel-db"
  engine                 = "postgres"
  engine_version         = "17"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  db_name                = var.DB_NAME
  username               = var.DB_USERNAME
  password               = var.DB_PASSWORD
  db_subnet_group_name   = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds-pi.id]
  skip_final_snapshot    = true
  publicly_accessible    = false

  multi_az = true
}

# Subnet Group do RDS
# aqui informa as subnets/zonas que o rds pode usar 
resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "db-subnet-group"
  subnet_ids = [aws_subnet.subnet-priv-1.id, aws_subnet.subnet-priv-2.id]

  tags = {
    Name = "DB Subnet Group"
  }
}
