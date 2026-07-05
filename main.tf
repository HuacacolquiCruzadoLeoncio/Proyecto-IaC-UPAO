# 1. Le decimos a Terraform que trabaje con AWS en la zona gratuita
provider "aws" {
  region = "us-east-1"
}

# 2. Creamos un Muro de Seguridad (Security Group)
resource "aws_security_group" "muro_seguridad" {
  name        = "app-tareas-sg"
  description = "Permitir entrar a la web y a configurar"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 3. FABRICAMOS LA LLAVE SECRETA (NUEVO)
resource "tls_private_key" "llave_ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "llave_aws" {
  key_name   = "llave-app-tareas"
  public_key = tls_private_key.llave_ssh.public_key_openssh
}

resource "local_file" "guardar_llave" {
  content  = tls_private_key.llave_ssh.private_key_pem
  filename = "llave-app-tareas.pem"
}

# 4. Creamos 2 Servidores (Instancias EC2) actualizados con la llave
resource "aws_instance" "mis_servidores" {
  count         = 2 
  ami           = "ami-0c7217cdde317cfec" 
  instance_type = "t3.micro" 
  
  vpc_security_group_ids = [aws_security_group.muro_seguridad.id]
  key_name               = aws_key_pair.llave_aws.key_name # (NUEVO) Le ponemos la llave a la chapa

  tags = {
    Name = "Servidor-App-Tareas-${count.index + 1}"
  }
}

# 5. LE PEDIMOS A TERRAFORM QUE NOS DE LAS DIRECCIONES IP (NUEVO)
output "ips_publicas" {
  value       = aws_instance.mis_servidores[*].public_ip
  description = "Las direcciones IP de nuestros servidores"
}

# ==========================================
# RETO SEMANA 4: EL BALANCEADOR DE CARGA
# ==========================================

# 1. Le pedimos a AWS que nos preste su Red por defecto (VPC) para no tener que crearla
data "aws_vpc" "red_por_defecto" {
  default = true
}

data "aws_subnets" "subredes_por_defecto" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.red_por_defecto.id]
  }
}

# 2. Creamos el "Grupo de Destino" (La lista de servidores donde el balanceador mandará gente)
resource "aws_lb_target_group" "grupo_servidores" {
  name     = "app-tareas-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.red_por_defecto.id
}

# 3. Enganchamos nuestros 2 servidores creados arriba a este Grupo de Destino
resource "aws_lb_target_group_attachment" "enganchar_servidores" {
  count            = 2
  target_group_arn = aws_lb_target_group.grupo_servidores.arn
  target_id        = aws_instance.mis_servidores[count.index].id
  port             = 80
}

# 4. Creamos el Balanceador de Carga en sí (El Recepcionista)
resource "aws_lb" "recepcionista" {
  name               = "app-tareas-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.muro_seguridad.id]
  # Usamos 2 zonas diferentes para cumplir el atributo de disponibilidad
  subnets            = [data.aws_subnets.subredes_por_defecto.ids[0], data.aws_subnets.subredes_por_defecto.ids[1]] 
}

# 5. Creamos el "Oyente" (El que está parado en la puerta 80 esperando a los usuarios)
resource "aws_lb_listener" "oyente_puerta" {
  load_balancer_arn = aws_lb.recepcionista.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.grupo_servidores.arn
  }
}

# 6. ¡NUEVO OUTPUT! Le pedimos a Terraform que nos dé el Link Final
output "url_balanceador" {
  value       = aws_lb.recepcionista.dns_name
  description = "¡Pega este link en tu navegador para ver tu app balanceada!"
}