# Terraform Lab

Plataforma para construir, modificar e versionar infras criadas para atuar (principalmente) nas clouds

fácil manutenção par amigrar a outra plataforma cloud

## comandos principais

inicia um diretorio de trabalho de um projeto com terraform
```bash
terraform init
```

Valida se o script tem algum problema de sintaxe
```bash
terraform validate
```

Vai la na subscrição e fala oque vai ser criado ou alterado ou destruido dos recursos
da uma preview basicamente
```bash
terraform plan
```

Roda realmente o script
```bash
terraform apply 
```

Destroi os recursos de todo seu script terraform
```bash
terraform destroy 
```
