
# CLUSTER
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

#criação de dns privado para suporte de troca de ips dos ecs

resource "aws_service_discovery_private_dns_namespace" "internal" {
  name        = "miguel-aluguel.internal"
  description = "DNS interno dos serviços ECS"
  vpc         = aws_vpc.vpc_miguel_aluguel.id
}

#registros dos "target groups", ta fazendo o mesmo papel 

resource "aws_service_discovery_service" "backend" {
  name = "backend"

  dns_config {
    namespace_id   = aws_service_discovery_private_dns_namespace.internal.id
    routing_policy = "MULTIVALUE"

    dns_records {
      ttl  = 10
      type = "A"
    }
  }
}

resource "aws_service_discovery_service" "frontend" {
  name = "frontend"

  dns_config {
    namespace_id   = aws_service_discovery_private_dns_namespace.internal.id
    routing_policy = "MULTIVALUE"

    dns_records {
      ttl  = 10
      type = "A"
    }
  }
}
# caso de uso
#backend.miguel-aluguel.internal
#frontend.miguel-aluguel.internal


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
          value =  "jdbc:postgresql://${aws_db_instance.postgres_rds.endpoint}/${var.DB_NAME}"
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
    security_groups  = [aws_security_group.back-pi.id]
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
    security_groups  = [aws_security_group.front-pi.id]
  }

  service_registries {
    registry_arn = aws_service_discovery_service.frontend.arn
  }
}
