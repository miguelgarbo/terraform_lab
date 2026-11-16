# Infraestrutura AWS com Terraform — Projeto Aluguel

Este repositório contém o código Terraform que provisiona, de ponta a ponta, a infraestrutura na AWS definida no diagrama de arquitetura do projeto (`infra/diagrama/diagrama_infraestrutura.pdf`). Cada componente do diagrama possui um recurso correspondente no Terraform, de modo que `terraform apply` entrega o ambiente exatamente como foi desenhado.

---

## Sumário

1. [Visão geral](#visão-geral)
2. [Diagrama da arquitetura](#diagrama-da-arquitetura)
3. [Mapeamento diagrama → Terraform](#mapeamento-diagrama--terraform)
4. [Rede](#rede)
5. [Segurança (Security Groups)](#segurança-security-groups)
6. [Computação](#computação)
7. [Banco de dados](#banco-de-dados)
8. [Service Discovery (Cloud Map)](#service-discovery-cloud-map)
9. [Registro de imagens (ECR)](#registro-de-imagens-ecr)
10. [Acesso administrativo (SSM)](#acesso-administrativo-ssm)
11. [Fluxos de tráfego](#fluxos-de-tráfego)
12. [Pré-requisitos](#pré-requisitos)
13. [Como usar](#como-usar)
14. [Variáveis e outputs](#variáveis-e-outputs)
15. [Validação pós-deploy](#validação-pós-deploy)
16. [Estrutura do projeto](#estrutura-do-projeto)
17. [Decisões de projeto](#decisões-de-projeto)

---

## Visão geral

| Item | Valor |
|---|---|
| Provedor | AWS |
| Região | `us-east-1` (N. Virginia) |
| VPC | `vpc_miguel_aluguel` — `10.20.0.0/20` |
| Zonas de disponibilidade | `us-east-1a` e `us-east-1b` |
| Ponto de entrada | EC2 `t3.micro` com **Nginx** (reverse proxy) |
| Aplicação | Frontend e Backend em **ECS Fargate** (2 réplicas de cada, uma por AZ) |
| Banco de dados | **Amazon RDS** com **Multi-AZ** (primário + standby) |
| Descoberta de serviços | **AWS Cloud Map** (DNS privado) |
| Imagens de contêiner | **Amazon ECR** (frontend e backend) |
| Acesso administrativo | **AWS Systems Manager** (sem SSH e sem chave `.pem`) |

A arquitetura segue o princípio de **menor exposição**: somente o Nginx fica em subnet pública. Frontend, backend e banco ficam em subnets privadas, e cada camada só aceita tráfego da camada imediatamente anterior, controlado por Security Groups encadeados.


## Mapeamento diagrama → Terraform

| Componente no diagrama | Recurso Terraform |
|---|---|
| VPC `vpc_miguel_aluguel` | `aws_vpc.vpc_miguel_aluguel` |
| Subnet pública `10.20.0.0/24` (1a) | `aws_subnet` |
| Subnets privadas `10.20.1.0/24` (1a) e `10.20.2.0/24` (1b) | `aws_subnet` |
| Internet Gateway | `aws_internet_gateway` |
| NAT Gateway | `aws_nat_gateway` + `aws_eip` |
| Tabelas de rotas (pública e privadas) | `aws_route_table` + `aws_route_table_association` |
| EC2 `t3.micro` com Nginx | `aws_instance` |
| `sg-app-access` | `aws_security_group.app_access` (`nginx-access`) |
| `sg-frontend` | `aws_security_group.front-pi` |
| `sg-backend` | `aws_security_group.back-pi` |
| `sg-database` | `aws_security_group.rds-pi` (`database`) |
| Regras dos Security Groups | `aws_vpc_security_group_ingress_rule` / `aws_vpc_security_group_egress_rule` |
| ECS Fargate (Frontend #1 e #2, Backend #1 e #2) | `aws_ecs_cluster`, `aws_ecs_task_definition`, `aws_ecs_service` |
| RDS primário + standby (Multi-AZ) | `aws_db_subnet_group` + `aws_db_instance` (`multi_az = true`) |
| Cloud Map | `aws_service_discovery_private_dns_namespace` + `aws_service_discovery_service` |
| ECR (frontend e backend) | `aws_ecr_repository` (x2) |
| AWS Systems Manager | `aws_iam_role` + `aws_iam_instance_profile` (política `AmazonSSMManagedInstanceCore`) |

---

## Rede

**VPC:** `vpc_miguel_aluguel`, CIDR `10.20.0.0/20` (4.096 endereços).

| Subnet | CIDR | AZ | Tipo | Conteúdo |
|---|---|---|---|---|
| Pública | `10.20.0.0/24` | `us-east-1a` | Pública | EC2 Nginx, NAT Gateway |
| Privada 1 | `10.20.1.0/24` | `us-east-1a` | Privada | Frontend #1, Backend #1, RDS primário |
| Privada 2 | `10.20.2.0/24` | `us-east-1b` | Privada | Frontend #2, Backend #2, RDS standby |

**Roteamento:**

- **Subnet pública** → rota `0.0.0.0/0` para o **Internet Gateway**.
- **Subnets privadas** → rota `0.0.0.0/0` para o **NAT Gateway**, permitindo que as tarefas Fargate baixem imagens do ECR e acessem serviços externos sem ter IP público.

---

## Segurança (Security Groups)

Os Security Groups são **encadeados por referência** (um SG autoriza outro SG, e não faixas de IP), de modo que só o componente certo consegue falar com o próximo.

> **Observação técnica:** como `nginx-access` ↔ `front-pi` e `nginx-access` ↔ `back-pi` se referenciam mutuamente (ingress de um é egress do outro), os SGs são criados **sem regras inline** e as regras são declaradas em recursos separados (`aws_vpc_security_group_*_rule`). Isso evita o erro de *Cycle* no Terraform.

### `nginx-access` (diagrama: `sg-app-access`)

| Direção | Porta | Origem / Destino |
|---|---|---|
| Entrada | 80/tcp | `0.0.0.0/0` |
| Entrada | 443/tcp | `0.0.0.0/0` |
| Saída | 80/tcp | SG `front-pi` |
| Saída | 8080/tcp | SG `back-pi` |
| Saída | 443/tcp | `0.0.0.0/0` (agente SSM e atualizações) |
| Saída | 80/tcp | `0.0.0.0/0` (repositórios `apt` do Ubuntu) |

### `front-pi` (diagrama: `sg-frontend`)

| Direção | Porta | Origem / Destino |
|---|---|---|
| Entrada | 80/tcp | SG `nginx-access` |
| Saída | 443/tcp | `0.0.0.0/0` (via NAT: ECR e serviços externos) |

### `back-pi` (diagrama: `sg-backend`)

| Direção | Porta | Origem / Destino |
|---|---|---|
| Entrada | 8080/tcp | SG `nginx-access` |
| Saída | 443/tcp | `0.0.0.0/0` (via NAT: ECR e serviços externos) |
| Saída | 5432/tcp | SG `database` |

### `database` (diagrama: `sg-database`)

| Direção | Porta | Origem / Destino |
|---|---|---|
| Entrada | 5432/tcp | SG `back-pi` |

> Somente o backend alcança o banco. Frontend e Nginx não têm caminho de rede até o RDS.

---

## Computação

### Nginx (reverse proxy) — EC2

- Instância **`t3.micro`** na subnet pública, `us-east-1a`.
- Associada ao SG `nginx-access`.
- É o **único ponto de entrada público** da aplicação (portas 80/443).
- Encaminha as requisições para o frontend (porta `80`) e para o backend (porta `8080`) usando os nomes DNS do Cloud Map.
- AMI: **Ubuntu 24.04 LTS (Noble)**, oficial da Canonical.
- Toda a configuração é feita via `user_data` no primeiro boot: instala `nginx`, `dnsutils` e `curl`, grava o `server` em `/etc/nginx/sites-available/default`, valida com `nginx -t` e inicia o serviço.

| Rota | Destino |
|---|---|
| `/` | `frontend.miguel-aluguel.internal:80` |
| `/api/` | `backend.miguel-aluguel.internal:8080` |

**Detalhes importantes da configuração do Nginx:**

- O `proxy_pass` usa **variável** (`set $backend ...`) junto com `resolver 10.20.0.2`. Assim o Nginx consulta o DNS do Cloud Map a cada 10 s (`valid=10s`) e acompanha a troca de IPs das tasks Fargate. Sem a variável, ele resolveria o nome uma única vez na inicialização.
- O resolver `10.20.0.2` é o DNS da VPC (endereço base da rede + 2).
- O `server` é `default_server` com `server_name _`, então responde também quando o acesso é feito direto pelo IP.
- O `aws_instance` usa `user_data_replace_on_change = true`: o `user_data` só executa no primeiro boot, e com essa opção qualquer alteração no script recria a instância.

### Frontend e Backend — ECS Fargate

| Serviço | Réplicas | Subnets | Porta | Security Group |
|---|---|---|---|---|
| Frontend | 2 (#1 em 1a, #2 em 1b) | Privadas | 80 | `front-pi` |
| Backend | 2 (#1 em 1a, #2 em 1b) | Privadas | 8080 | `back-pi` |

- Execução em **Fargate** (sem gerenciar servidores).
- Uma réplica de cada serviço por AZ, garantindo **alta disponibilidade**: se uma AZ falhar, a outra continua atendendo.
- Imagens puxadas do ECR através do NAT Gateway.
- Registradas automaticamente no Cloud Map.

---

## Banco de dados

- **Amazon RDS (PostgreSQL)** com **Multi-AZ** habilitado.
- **Primário** em `us-east-1a` (subnet `10.20.1.0/24`) e **standby** em `us-east-1b` (subnet `10.20.2.0/24`).
- **Replicação síncrona** entre as instâncias: em caso de falha do primário, o RDS promove o standby automaticamente.
- Criado em um **DB Subnet Group** contendo as duas subnets privadas.
- Sem acesso público; aceita conexões apenas do SG `back-pi` na porta `5432`.

---

## Service Discovery (Cloud Map)

Namespace DNS privado **`miguel-aluguel.internal`**, vinculado à VPC:

| Serviço | Endereço interno |
|---|---|
| Backend | `backend.miguel-aluguel.internal:8080` |
| Frontend | `frontend.miguel-aluguel.internal:80` |

O Nginx usa esses nomes para localizar as tarefas Fargate, sem depender de IPs fixos (que mudam a cada nova tarefa).

---

## Registro de imagens (ECR)

Dois repositórios:

- `frontend` — imagem do frontend
- `backend` — imagem do backend

As tarefas Fargate puxam as imagens a partir das subnets privadas, saindo pelo **NAT Gateway**.

---

## Acesso administrativo (SSM)

O administrador acessa a EC2 pelo **AWS Systems Manager (Session Manager)**. Não há chave `.pem` e **nenhuma porta 22 está aberta**: o agente SSM, que já vem na AMI do Ubuntu 24.04, abre uma conexão de saída (443) até o serviço, e é por ela que a sessão trafega.

Recursos criados no Terraform (`iam.tf`):

| Recurso | Função |
|---|---|
| `aws_iam_role.ssm_nginx` | Role que a EC2 assume (`role-ssm-nginx-pi`) |
| `aws_iam_role_policy_attachment.ssm_core` | Anexa a política `AmazonSSMManagedInstanceCore` |
| `aws_iam_instance_profile.ssm_nginx` | Liga a role à instância (`iam_instance_profile` no `aws_instance`) |

**Pré-requisitos na máquina do administrador:**

- AWS CLI configurado
- [Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html) instalado
- Permissões IAM `ssm:StartSession` e `ssm:TerminateSession`

**Conectar:** o Terraform já devolve o comando pronto, com o id atual da instância (o id muda sempre que a instância é recriada):

```bash
cd infra/terraform
$(terraform output -raw ssm_command)
```

Ou, se preferir, copie o valor de `ssm_command` mostrado ao final do `terraform apply`. O output é definido em `outputs.tf`:

```hcl
output "ssm_command" {
  value = "aws ssm start-session --region us-east-1 --target ${aws_instance.ec2-nginx-pi.id}"
}
```

Caso não tenha o state do Terraform à mão, dá para buscar a instância pela tag `Name`:

```bash
aws ssm start-session --region us-east-1 --target $(aws ec2 describe-instances --region us-east-1 \
  --filters "Name=tag:Name,Values=ec2-nginx-pi" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text)
```

Dentro da sessão: `sudo -i` para virar root e `exit` para sair.

**Verificar se a instância está registrada no SSM:**

```bash
aws ssm describe-instance-information --region us-east-1
```

---

## Fluxos de tráfego

**1. Requisição do usuário**

```
Usuário ──HTTPS:443──▶ Internet Gateway ──▶ Nginx (EC2, subnet pública)
                                              ├──:80───▶ Frontend (Fargate)
                                              └──:8080─▶ Backend  (Fargate) ──:5432──▶ RDS
```

**2. Saída das aplicações (ex.: pull de imagens)**

```
Frontend / Backend (subnet privada) ──443──▶ NAT Gateway ──▶ Internet / ECR
```

**3. Alta disponibilidade do banco**

```
RDS primário (1a) ══ replicação síncrona ══▶ RDS standby (1b)
```

**4. Administração**

```
Admin ──▶ AWS Systems Manager ──▶ EC2 / recursos da VPC
```

---

## Pré-requisitos

- [Terraform](https://developer.hashicorp.com/terraform/install) `>= 1.5`
- Provider `hashicorp/aws` `>= 5.x` (necessário para `aws_vpc_security_group_*_rule`)
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) configurado (`aws configure`)
- Permissões IAM para criar VPC, EC2, ECS, ECR, RDS, Cloud Map, IAM e SSM

---

## Como usar

```bash
# 1. Entrar no diretório do Terraform
cd infra/terraform

# 2. Criar o arquivo de variáveis a partir do template e preencher os valores
cp terraform.tfvars.ex terraform.tfvars

# 3. Inicializar providers e backend
terraform init

# 4. Validar a sintaxe
terraform validate

# 5. Visualizar o que será criado
terraform plan

# 6. Provisionar a infraestrutura
terraform apply

# 7. Destruir o ambiente quando não for mais necessário
terraform destroy
```

Para forçar a recriação apenas da instância do Nginx (por exemplo, depois de ajustar o `user_data`):

```bash
terraform apply -replace=aws_instance.ec2-nginx-pi
```

---

## Variáveis e outputs

**Variáveis:** declaradas em `variables.tf`. Os valores reais ficam em `terraform.tfvars`, criado a partir do template `terraform.tfvars.ex`.

> `terraform.tfvars` pode conter dados sensíveis (como senha do banco) e **não deve ser versionado**. O mesmo vale para `terraform.tfstate` e `terraform.tfstate.backup`.

**Outputs** (`outputs.tf`), exibidos ao final do `terraform apply`:

| Output | Descrição |
|---|---|
| `public_ip_access` | IP público da EC2 do Nginx (ponto de entrada da aplicação) |
| `private_ip_nginx` | IP privado da EC2 do Nginx na subnet pública |
| `public_ip_nat` | IP público de saída do NAT Gateway |
| `url_app` | URL de acesso à aplicação (`http://<ip>/welcome`) |
| `instance_id_nginx` | ID da instância EC2 do Nginx (muda quando a instância é recriada) |
| `ssm_command` | Comando pronto para abrir uma sessão SSM na EC2 do Nginx |

---

## Validação pós-deploy

Roteiro usado para validar que o ambiente provisionado corresponde ao diagrama. Rode na EC2 do Nginx.

**1. Cloud Map: as duas réplicas de cada serviço devem aparecer (uma por AZ):**

```bash
getent hosts frontend.miguel-aluguel.internal   # esperado: um IP 10.20.1.x e um 10.20.2.x
getent hosts backend.miguel-aluguel.internal    # esperado: um IP 10.20.1.x e um 10.20.2.x
```

**2. Conectividade Nginx → serviços (valida os Security Groups):**

```bash
curl -i http://frontend.miguel-aluguel.internal:80     # 200 OK com o HTML do frontend
curl -i http://backend.miguel-aluguel.internal:8080/   # 403 (Spring Security): backend no ar
```

**3. Fluxo completo pelo Nginx:**

```bash
curl -i localhost            # frontend
curl -i localhost/api/       # 403 do Spring: o proxy alcançou o backend
```

**4. Logs, em caso de falha:**

```bash
sudo nginx -t
sudo systemctl status nginx --no-pager
sudo tail -n 20 /var/log/nginx/error.log
cat /var/log/cloud-init-output.log
```

---

## Estrutura do projeto

```
terraform_lab/
└── infra/
    └── terraform/
        ├── provider.tf           # provider AWS
        ├── variables.tf          # variáveis da infraestrutura e da aplicação Miguel Aluguel
        ├── terraform.tfvars.ex   # template para criar o terraform.tfvars
        ├── terraform.tfvars      # valores das variáveis (não versionar)
        ├── network.tf            # VPC, subnets, IGW, NAT Gateway e rotas
        ├── security.tf           # Security Groups e suas regras
        ├── compute.tf            # EC2 Nginx, cluster ECS, task definitions e services
        ├── database.tf           # DB subnet group e RDS Multi-AZ
        ├── cloudmap.tf           # namespace e serviços de DNS interno (resolução para o Nginx)
        ├── iam.tf                # role, política e instance profile do SSM
        ├── outputs.tf            # outputs com os IPs gerados
        ├── terraform.tfstate     # estado do Terraform (gerado, não versionar)
```

---

## Decisões de projeto

- **Subnets privadas para a aplicação e o banco:** nenhum componente além do Nginx é alcançável diretamente pela internet.
- **Security Groups por referência:** em vez de liberar faixas de IP, cada camada confia apenas no SG da camada anterior.
- **Regras de SG em recursos separados:** evita dependências circulares entre `nginx-access`, `front-pi` e `back-pi`.
- **Egress restrito:** frontend e backend só saem pela porta 443 (e o backend também para o RDS na 5432), reduzindo a superfície em caso de comprometimento.
- **Duas réplicas em AZs distintas:** tolerância a falha de uma zona inteira.
- **RDS Multi-AZ:** failover automático do banco, com replicação síncrona.
- **Cloud Map:** comunicação por nome DNS, sem IPs fixos.
- **SSM no lugar de SSH:** acesso administrativo auditável, sem chave `.pem` e sem a porta 22 aberta. O antigo Security Group `libera-ssh` foi removido.
- **Saída do Nginx limitada a 80 e 443:** além do tráfego para frontend e backend, a EC2 só sai para o agente SSM (443) e para os repositórios `apt` (80).
