Pessoa 1: Infraestrutura base (Parte A)
Código: versions.tf, providers.tf, variables.tf, network.tf, security.tf, compute.tf, outputs.tf, .gitignore, .terraform.lock.hcl e terraform.tfvars.example.
Requisitos: R1 a R11 (VPC, sub-redes, IGW, NAT, rotas, SGs, chave SSH, tags, outputs) e S2 (egress restrito).
Orçamento: alerta configurado antes do primeiro apply.
Demonstrações: D1 (plan sem alterações e outputs) e D4 (NAT e isolamento).
Encerramento: tag entrega-2, git archive do zip e terraform destroy com evidência.
