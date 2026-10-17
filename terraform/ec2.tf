# Latest RHEL 9 image from Red Hat (owner 309956199498) unless ami_id is set.
data "aws_ami" "rhel9" {
  most_recent = true
  owners      = ["309956199498"]

  filter {
    name   = "name"
    values = ["RHEL-9.*_HVM-*-x86_64-*"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

locals {
  ami_id = var.ami_id != "" ? var.ami_id : data.aws_ami.rhel9.id
}

# Generated credentials. They reach the instances through user_data, which anyone with
# ec2:DescribeInstanceAttribute can read; production setups should fetch them from
# AWS Secrets Manager or SSM Parameter Store at boot instead.
resource "random_password" "mysql_root" {
  length           = 20
  special          = true
  override_special = "@#%"
}

resource "random_password" "db_app" {
  length           = 20
  special          = true
  override_special = "@#%"
}

resource "aws_instance" "bastion" {
  ami                    = local.ami_id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.bastion.id]
  key_name               = var.key_name
  tags                   = { Name = "${local.name}-bastion", Tier = "bastion" }
}

resource "aws_instance" "mysql" {
  ami                    = local.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.database[0].id
  vpc_security_group_ids = [aws_security_group.mysql.id]
  key_name               = var.key_name

  user_data = templatefile("${path.module}/userdata.sh.tftpl", {
    repo_url = var.repo_url
    script   = "01-mysql.sh"
    env = {
      MYSQL_ROOT_PASSWORD = random_password.mysql_root.result
      DB_PASSWORD         = random_password.db_app.result
    }
  })
  user_data_replace_on_change = true

  root_block_device {
    volume_size = 20
    encrypted   = true
  }

  tags = { Name = "${local.name}-mysql", Tier = "db" }
}

resource "aws_instance" "backend" {
  ami                    = local.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private[0].id
  vpc_security_group_ids = [aws_security_group.backend.id]
  key_name               = var.key_name

  user_data = templatefile("${path.module}/userdata.sh.tftpl", {
    repo_url = var.repo_url
    script   = "02-backend.sh"
    env = {
      DB_HOST     = aws_instance.mysql.private_ip
      DB_PASSWORD = random_password.db_app.result
    }
  })
  user_data_replace_on_change = true

  root_block_device {
    encrypted = true
  }

  tags = { Name = "${local.name}-backend", Tier = "app" }
}

resource "aws_instance" "frontend" {
  ami                    = local.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private[1].id
  vpc_security_group_ids = [aws_security_group.frontend.id]
  key_name               = var.key_name

  user_data = templatefile("${path.module}/userdata.sh.tftpl", {
    repo_url = var.repo_url
    script   = "03-frontend.sh"
    env = {
      BACKEND_HOST = aws_instance.backend.private_ip
    }
  })
  user_data_replace_on_change = true

  root_block_device {
    encrypted = true
  }

  tags = { Name = "${local.name}-frontend", Tier = "web" }
}
