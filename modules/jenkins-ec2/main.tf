# WHY Jenkins gets its own module separate from the bastion:
# The bastion is a jump host — it's tiny, stateless, and exists purely
# for SSH access. Jenkins is a stateful service that runs builds, stores
# artifacts, and needs specific software installed. Mixing them would
# make both harder to manage.
#
# Jenkins lives in a PRIVATE subnet. It has no public IP. Access is
# through the internal ALB (for the UI) or through the bastion (for
# admin SSH). This is the correct production posture — CI/CD pipelines
# don't need to be reachable from the internet.

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

# Jenkins only needs to be reachable from:
# - The internal ALB (port 8080)
# - The bastion (port 22, for admin access)
# - Itself (agents communicating back on port 50000)
resource "aws_security_group" "jenkins" {
  name_prefix = "${var.name}-jenkins-"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Jenkins UI from internal ALB only"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [var.alb_security_group_id]
  }

  ingress {
    description     = "SSH from bastion only — not from 0.0.0.0/0"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [var.bastion_security_group_id]
  }

  ingress {
    description = "Jenkins agent inbound (JNLP)"
    from_port   = 50000
    to_port     = 50000
    protocol    = "tcp"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-jenkins-sg" }
}

resource "aws_instance" "jenkins" {
  ami                    = data.aws_ami.al2023.id
  instance_type           = var.instance_type
  subnet_id                = var.private_subnet_id
  vpc_security_group_ids   = [aws_security_group.jenkins.id]
  key_name                 = var.key_name
  iam_instance_profile     = var.iam_instance_profile_name

  # WHY 30GB: Jenkins stores build artifacts, workspace clones, and
  # Docker image layers locally. 8GB (the AMI default) fills up within
  # a few dozen builds.
  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }

  # WHY user_data installs everything at launch:
  # This makes the instance reproducible. If you terminate it and launch
  # a new one (from Terraform), it comes back with the exact same
  # software stack. Nothing is installed manually and then forgotten.
  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -e

    echo "=== Installing Java (Jenkins requires Java 17+) ==="
    dnf install -y java-17-amazon-corretto

    echo "=== Installing Jenkins ==="
    wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
    rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
    dnf install -y jenkins
    systemctl enable jenkins
    systemctl start jenkins

    echo "=== Installing Git ==="
    dnf install -y git

    echo "=== Installing Terraform ${var.terraform_version} ==="
    yum install -y yum-utils
    yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
    dnf install -y terraform-${var.terraform_version}

    echo "=== Installing kubectl ==="
    curl -LO "https://dl.k8s.io/release/v${var.kubectl_version}/bin/linux/amd64/kubectl"
    chmod +x kubectl
    mv kubectl /usr/local/bin/kubectl

    echo "=== Installing AWS CLI v2 ==="
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    ./aws/install

    echo "=== All tools installed. Jenkins initial admin password: ==="
    # The password appears in /var/lib/jenkins/secrets/initialAdminPassword
    # after Jenkins fully starts (~60 seconds after this script finishes)
    cat /var/lib/jenkins/secrets/initialAdminPassword || echo "(not ready yet — Jenkins still starting)"
  EOF
  )

  tags = { Name = "${var.name}-jenkins" }
}
