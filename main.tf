data "aws_ami" "app_ami" {
  most_recent = true

  filter {
    name   = "name"
    values = ["bitnami-tomcat-*-x86_64-hvm-ebs-nami"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["979382823631"] # Bitnami
}

module "blog_vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "dev-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway = true
  enable_vpn_gateway = true

  tags = {
    Terraform = "true"
    Environment = "dev"
  }
}

module "blog_sg" {
  source = "terraform-aws-modules/security-group/aws"
  version = "~> 4.13.0"

  vpc_id      = module.blog_vpc.vpc_id
  name        = "blog-sg"
  
  ingress_rules       = ["https-442-tcp","http-80-tcp"]
  ingress_cidr_blocks = ["0.0.0.0/0"]

  egress_rules       = ["all-all"]
  egress_cidr_blocks = ["0.0.0.0/0"]
}

module "blog_alb" {
  source = "terraform-aws-modules/alb/aws"
  version = "~> 6.0.0"

  name               = "blog-alb"
  load_balancer_type = "application"
  vpc_id             = module.blog_vpc.vpc_id
  subnets            = module.blog_vpc.public_subnets

  security_groups    = [module.blog_sg.security_group_id]

  listeners = {
    blog-http = {
      port     = 80
      protocol = "HTTP"
      forward = {
        target_group_arn = aws_lb_target_group.blog.arn
      }
    }
  }

  tags = {
      Environment = "dev"
  }
}

resource "aws_lb_target_group" "blog" {
  name     = "blog-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.blog_vpc.vpc_id
}

module "asg" {
  source = "terraform-aws-modules/autoscaling/aws"
  version = "~> 9.0.2"

  name                 = "blog-asg"
  min_size             = 1
  max_size             = 2
  desired_capacity     = 1

  vpc_zone_identifier  = module.blog_vpc.public_subnets
  
  launch_template_name  = "blog"
  security_groups       = [module.blog_sg.security_group_id]
  instance_type         = var.instance_type
  image_id              = data.aws_ami.app_ami.id

  traffic_source_attachments = {
    alb = {
      target_group_arn = aws_lb_target_group.blog.arn
    }
  }

  tags = [
    {
      key                 = "Environment"
      value               = "dev"
      propagate_at_launch = true
    }
  ]
}
