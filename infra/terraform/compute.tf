# EC2 NGINX (PROXY REVERSO)

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

# Instância pública para o Nginx
resource "aws_instance" "ec2-nginx-pi" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.subnet-pub-1.id

  associate_public_ip_address = true

  vpc_security_group_ids = [
    aws_security_group.ssh.id,
    aws_security_group.app_access.id
  ]
  user_data_replace_on_change = true
  user_data                   = <<-EOF
    #!/bin/bash
    set -euxo pipefail

    # Atualiza os pacotes
    apt-get update -y

    # Instala Nginx e ferramentas de diagnóstico
    DEBIAN_FRONTEND=noninteractive apt-get install -y nginx dnsutils curl

    # Configuração do Nginx
    cat > /etc/nginx/sites-available/default <<'NGINX'

    server {
        listen 80 default_server;
        listen [::]:80 default_server;

        server_name _;

        # DNS privado da VPC AWS
        resolver 10.20.0.2 valid=10s ipv6=off;
        resolver_timeout 5s;

        # -----------------------------
        # BACKEND
        # -----------------------------
        location /api/ {
            set $backend backend.miguel-aluguel.internal:8080;

            proxy_pass http://$backend;

            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        # -----------------------------
        # FRONTEND
        # -----------------------------
        location / {
            set $frontend frontend.miguel-aluguel.internal:80;

            proxy_pass http://$frontend;

            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }

    NGINX

    # Valida a configuração
    nginx -t

    # Habilita e inicia o serviço
    systemctl enable nginx
    systemctl restart nginx

EOF

  tags = {
    Name = "ec2-nginx-pi"
  }

}



# CLUSTER ECS + FARGATE
resource "aws_ecs_cluster" "pi_cluster" {
  name = "miguel-aluguel-cluster"
}

data "aws_iam_policy_document" "ecs_task_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "miguel-ecs-task-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy" {
  role = aws_iam_role.ecs_task_execution_role.name

  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}


# CloudWatch Log Groups

resource "aws_cloudwatch_log_group" "backend_logs" {
  name              = "/ecs/miguel-aluguel-backend"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "frontend_logs" {
  name              = "/ecs/miguel-aluguel-frontend"
  retention_in_days = 14
}



# --- TASK DEFINITION: BACKEND ---
resource "aws_ecs_task_definition" "backend_task" {
  family                   = "miguel-aluguel-backend"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]

  cpu    = "256"
  memory = "512"

  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
  depends_on = [
    aws_iam_role_policy_attachment.ecs_task_execution_policy
  ]
  container_definitions = jsonencode([
    {
      name      = "miguel_aluguel_backend_official"
      image     = var.ecr_backend
      essential = true

      portMappings = [
        {
          containerPort = 8080
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"

        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.backend_logs.name
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "ecs"
        }
      }

      environment = [
        {
          name  = "DB_URL"
          value = "jdbc:postgresql://${aws_db_instance.postgres_rds.endpoint}/${var.DB_NAME}"
        },
        {
          name  = "DB_USERNAME"
          value = var.DB_USERNAME
        },
        {
          name  = "DB_PASSWORD"
          value = var.DB_PASSWORD
        },
        {
          name  = "HASH_TOKEN"
          value = var.HASH_TOKEN
        },
        {
          name  = "FRONT_URL"
          value = "http://${aws_instance.ec2-nginx-pi.public_ip}/"
        }
      ]


    }
  ])
}

# ECS Service (Mantém o container rodando na EC2)
resource "aws_ecs_service" "backend_service" {
  name            = "backend-service"
  cluster         = aws_ecs_cluster.pi_cluster.id
  task_definition = aws_ecs_task_definition.backend_task.arn

  desired_count = 2
  launch_type   = "FARGATE"

  network_configuration {
    subnets = toset([
      aws_subnet.subnet-priv-1.id,
      aws_subnet.subnet-priv-2.id
    ])
    security_groups = [aws_security_group.back-pi.id]
  }

  service_registries {
    registry_arn = aws_service_discovery_service.backend.arn
  }


}

# --- TASK DEFINITION: FRONTEND ---
resource "aws_ecs_task_definition" "frontend_task" {
  family                   = "miguel-aluguel-frontend"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]

  cpu    = "256"
  memory = "512"

  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn

  depends_on = [
    aws_iam_role_policy_attachment.ecs_task_execution_policy
  ]

  container_definitions = jsonencode([
    {
      name      = "miguel_aluguel_frontend"
      image     = var.ecr_frontend
      essential = true
      portMappings = [
        {
          containerPort = 80
          protocol      = "tcp"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"

        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.frontend_logs.name
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "ecs"
        }
      }

      environment = [
        { name = "VITE_API_URL", value = "http://${aws_instance.ec2-nginx-pi.public_ip}/api" }
      ]
    }
  ])
}

resource "aws_ecs_service" "frontend_service" {
  name            = "frontend-service"
  cluster         = aws_ecs_cluster.pi_cluster.id
  task_definition = aws_ecs_task_definition.frontend_task.arn

  desired_count = 2
  launch_type   = "FARGATE"

  network_configuration {
    subnets = toset([
      aws_subnet.subnet-priv-1.id,
      aws_subnet.subnet-priv-2.id
    ])
    security_groups = [aws_security_group.front-pi.id]
  }

  service_registries {
    registry_arn = aws_service_discovery_service.frontend.arn
  }
}
