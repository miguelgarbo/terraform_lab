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
