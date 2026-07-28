# WHY this exists: your EKS nodes and the NAT instance aren't meant to
# be logged into directly for general use. This is a small, separate
# EC2 instance whose only job is being something you can SSH into — to
# host misc tools, poke around the VPC's private side, or just have a
# stable jump point. Its security group is the whole point: port 22 is
# open to exactly one IP, never 0.0.0.0/0.

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_key_pair" "bastion" {
  key_name   = "${var.name}-bastion-key"
  public_key = file(var.ssh_public_key_path)
}

resource "aws_security_group" "bastion" {
  name_prefix = "${var.name}-bastion-"
  vpc_id      = var.vpc_id

  # WHY /32: a CIDR ending in /32 means "exactly this one address," not
  # a range. That's the difference between "open to me" and "open to
  # everyone" — 0.0.0.0/0 would mean literally any IP on the internet.
  ingress {
    description = "SSH from your IP only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-bastion-sg" }
}

# WHY an IAM role at all, on a box you SSH into: this gives you SSM
# Session Manager as a second way in, with no security group changes
# and no key file needed. Useful if you're ever on a different network
# and your IP no longer matches allowed_ssh_cidr — SSM doesn't care
# what IP you're coming from.
resource "aws_iam_role" "bastion" {
  name = "${var.name}-bastion-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "bastion_ssm" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "bastion" {
  name = "${var.name}-bastion-profile"
  role = aws_iam_role.bastion.name
}

resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.al2023.id
  instance_type           = var.instance_type
  subnet_id                = var.public_subnet_id
  vpc_security_group_ids   = [aws_security_group.bastion.id]
  key_name                 = aws_key_pair.bastion.key_name
  iam_instance_profile     = aws_iam_instance_profile.bastion.name
  associate_public_ip_address = true

  tags = { Name = "${var.name}-bastion" }
}

# WHY an Elastic IP: without one, the public IP changes if the instance
# ever stops/starts. This keeps the address stable so your
# allowed_ssh_cidr rule and PuTTY saved session don't need updating.
resource "aws_eip" "bastion" {
  instance = aws_instance.bastion.id
  domain   = "vpc"
  tags     = { Name = "${var.name}-bastion-eip" }
}
