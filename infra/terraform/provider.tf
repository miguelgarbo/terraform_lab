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

  default_tags {
    tags = {
      project = "miguel-aluguel"
      group   = "pi-02-2026"
      managed = "terraform"
    }
  }
}