# One security group per tier. Each tier only accepts traffic from the tier in front of it:
#   internet -> ALB:80 -> frontend:80 -> backend:8080 -> mysql:3306
# SSH is allowed only from the bastion, and the bastion only from admin_cidr.

resource "aws_security_group" "alb" {
  name        = "${local.name}-alb"
  description = "Public load balancer"
  vpc_id      = aws_vpc.main.id
}

resource "aws_security_group" "bastion" {
  name        = "${local.name}-bastion"
  description = "SSH jump host"
  vpc_id      = aws_vpc.main.id
}

resource "aws_security_group" "frontend" {
  name        = "${local.name}-frontend"
  description = "Web tier (Nginx)"
  vpc_id      = aws_vpc.main.id
}

resource "aws_security_group" "backend" {
  name        = "${local.name}-backend"
  description = "App tier (Python API)"
  vpc_id      = aws_vpc.main.id
}

resource "aws_security_group" "mysql" {
  name        = "${local.name}-mysql"
  description = "DB tier (MySQL)"
  vpc_id      = aws_vpc.main.id
}

# ---------- ingress ----------
resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  description       = "HTTP from the internet"
}

resource "aws_vpc_security_group_ingress_rule" "bastion_ssh" {
  security_group_id = aws_security_group.bastion.id
  cidr_ipv4         = var.admin_cidr
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  description       = "SSH from the admin IP only"
}

resource "aws_vpc_security_group_ingress_rule" "frontend_from_alb" {
  security_group_id            = aws_security_group.frontend.id
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
  description                  = "HTTP from the ALB"
}

resource "aws_vpc_security_group_ingress_rule" "backend_from_frontend" {
  security_group_id            = aws_security_group.backend.id
  referenced_security_group_id = aws_security_group.frontend.id
  from_port                    = 8080
  to_port                      = 8080
  ip_protocol                  = "tcp"
  description                  = "API from the web tier"
}

resource "aws_vpc_security_group_ingress_rule" "mysql_from_backend" {
  security_group_id            = aws_security_group.mysql.id
  referenced_security_group_id = aws_security_group.backend.id
  from_port                    = 3306
  to_port                      = 3306
  ip_protocol                  = "tcp"
  description                  = "MySQL from the app tier"
}

resource "aws_vpc_security_group_ingress_rule" "ssh_from_bastion" {
  for_each = {
    frontend = aws_security_group.frontend.id
    backend  = aws_security_group.backend.id
    mysql    = aws_security_group.mysql.id
  }
  security_group_id            = each.value
  referenced_security_group_id = aws_security_group.bastion.id
  from_port                    = 22
  to_port                      = 22
  ip_protocol                  = "tcp"
  description                  = "SSH from the bastion"
}

# ---------- egress (all outbound; private tiers still exit only via NAT) ----------
resource "aws_vpc_security_group_egress_rule" "all" {
  for_each = {
    alb      = aws_security_group.alb.id
    bastion  = aws_security_group.bastion.id
    frontend = aws_security_group.frontend.id
    backend  = aws_security_group.backend.id
    mysql    = aws_security_group.mysql.id
  }
  security_group_id = each.value
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "All outbound"
}
