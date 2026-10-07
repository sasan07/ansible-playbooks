resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags                 = { Name = "jenkins-vpc" }
}

resource "aws_subnet" "main" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  tags                    = { Name = "jenkins-subnet" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "rta" {
  subnet_id      = aws_subnet.main.id
  route_table_id = aws_route_table.rt.id
}

resource "aws_security_group" "sg" {
  name   = "jenkins-sg"
  vpc_id = aws_vpc.main.id

  dynamic "ingress" {
    for_each = [22, 80, 8080]
    content {
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

locals {
  names = ["Jenkins-Ansible-Master", "Agent-1", "Agent-2"]
}

resource "aws_instance" "server" {
  count                  = 3
  ami                    = "ami-0f8a61b66d1accaee"
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.main.id
  vpc_security_group_ids = [aws_security_group.sg.id]
  key_name               = "prtprt"
  tags                   = { Name = local.names[count.index] }
}

resource "aws_eip" "eip" {
  count      = 3
  instance   = aws_instance.server[count.index].id
  domain     = "vpc"
  depends_on = [aws_internet_gateway.igw]
}

output "elastic_ips" {
  value = { for i, e in aws_eip.eip : local.names[i] => e.public_ip }
}