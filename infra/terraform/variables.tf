#declaração de variavel existente no codigo
#pode se definir um valor default para a variavel,
#caso não seja definido um valor no arquivo terraform.tfvars
variable "aws_region" {
  description = "Regiao da AWS onde os recursos serao criados"
  type        = string
  default     = "us-east-1"
}

variable "ecr_frontend" {
  description = "Repositório Privado do Front do Miguel aluguel "
  type = string
}

variable "ecr_backend" {
  description = "Repositório Privado do Back do Miguel aluguel "
  type = string
}

variable "HASH_TOKEN" {
  description = "Hash para o JWT"
  type = string
}

variable "DB_USERNAME" {
  description = "Usuário do banco para a aplicação"
  type = string
}
variable "DB_NAME" {
  description = "Nome do banco para a aplicação"
  type = string
}

variable "DB_PASSWORD" {
  description = "Senha do usuário do banco para a aplicação"
  type = string
}

