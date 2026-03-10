data "aws_ami" "app_ami" {
  most_recent = true

  filter {
    name   = "name"
    values = [var.ami_filter.name]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = [var.ami_filter.owner]
}

module "blog_vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "${var.environment.name}-vpc"
  cidr = "${var.environment.network_prefix}.0.0/16"

  azs             = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
  private_subnets = ["${var.environment.network_prefix}.1.0/24", "${var.environment.network_prefix}.2.0/24", "${var.environment.network_prefix}.3.0/24"]
  public_subnets  = ["${var.environment.network_prefix}.101.0/24", "${var.environment.network_prefix}.102.0/24", "${var.environment.network_prefix}.103.0/24"]

  enable_nat_gateway = true
  enable_vpn_gateway = true

  tags = {
    Terraform = "true"
    Environment = var.environment.name
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
      Environment = var.environment.name
  }
}

resource "aws_lb_target_group" "blog" {
  name     = "blog-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.blog_vpc.vpc_id
}

module "blog_asg" {
  source = "terraform-aws-modules/autoscaling/aws"
  version = "~> 9.0.2"

  name                 = "blog-asg"
  min_size             = var.asg_settings.min_size
  max_size             = var.asg_settings.max_size
  desired_capacity     = var.asg_settings.desired_capacity

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
      value               = var.environment.name
      propagate_at_launch = true
    }
  ]
}
