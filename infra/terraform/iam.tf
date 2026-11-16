# SSM CONFIGURAÇÃO (ACESSO SSH AS MAQUINAS)

# Quem pode assumir a role: o serviço EC2
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ssm_nginx" {
  name               = "role-ssm-nginx-pi"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = {
    Name = "role-ssm-nginx-pi"
  }
}

# Política gerenciada pela AWS com o mínimo que o SSM precisa
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ssm_nginx.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# O instance profile é o que "pendura" a role na EC2
resource "aws_iam_instance_profile" "ssm_nginx" {
  name = "profile-ssm-nginx-pi"
  role = aws_iam_role.ssm_nginx.name
}


# Role de execução das tasks ECS (usada pelo agente do Fargate, não pela aplicação):
# permite puxar as imagens do ECR e enviar os logs para o CloudWatch.

# Trust policy: somente o serviço ecs-tasks pode assumir a role

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
