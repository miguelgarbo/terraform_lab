#criação de dns interno para resolução de ips dos ecs, suportando as trocas ips 

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