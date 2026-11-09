#declaração de variavel existente no codigo
#pode se definir um valor default para a variavel,
#caso não seja definido um valor no arquivo terraform.tfvars
variable "aws_region" {
  description = "Região da AWS onde os recursos serão criados"
  type        = string
  default     = "us-east-1"
}