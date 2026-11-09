#tags que vao ser usadas para filtrar os recursos criados, e tambem para identificar o projeto em si
locals {
  project_name = "terraform-lab"

  common_tags = {
    Project     = local.project_name
    Environment = "lab"
    ManagedBy   = "Terraform"
  }
}