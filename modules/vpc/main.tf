# WHY this module exists at all: everything else (EKS nodes, the ALB,
# your Route 53 private zone) needs a VPC to live inside. This builds
# that VPC from nothing — 2 public subnets, 2 private subnets, across
# 2 Availability Zones for basic high availability.

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.name}-vpc" }
}

# WHY an Internet Gateway: this is what lets anything in a *public*
# subnet reach the internet directly. Private subnets never talk to
# this directly — they go through the NAT instance instead (below).
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.name}-igw" }
}

# --- Public subnets (one per AZ) ---
resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = { Name = "${var.name}-public-${count.index}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.name}-public-rt" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id              = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# --- Private subnets (one per AZ) ---
resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = { Name = "${var.name}-private-${count.index}" }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.name}-private-rt" }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# --- NAT instance (not NAT Gateway — cost minimization, matches your
#     existing pattern elsewhere). This is a plain EC2 instance that
#     forwards traffic from private subnets out to the internet, so
#     your EKS nodes can pull container images etc. without having a
#     public IP themselves. ---

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_security_group" "nat" {
  name_prefix = "${var.name}-nat-"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "All traffic from inside the VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-nat-sg" }
}

resource "aws_instance" "nat" {
  ami                    = data.aws_ami.al2023.id
  instance_type           = var.nat_instance_type
  subnet_id                = aws_subnet.public[0].id
  vpc_security_group_ids   = [aws_security_group.nat.id]

  # WHY this matters: AWS blocks traffic that isn't addressed to/from
  # the instance itself by default. A NAT instance's whole job is
  # forwarding OTHER machines' traffic, so this check has to be off —
  # this is the "commonly missed step" that causes silent NAT failures.
  source_dest_check = false

  user_data = <<-EOF
    #!/bin/bash
    sysctl -w net.ipv4.ip_forward=1
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
  EOF

  tags = { Name = "${var.name}-nat-instance" }
}

resource "aws_eip" "nat" {
  instance = aws_instance.nat.id
  domain   = "vpc"
  tags     = { Name = "${var.name}-nat-eip" }
}

resource "aws_route" "private_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.nat.primary_network_interface_id
}
