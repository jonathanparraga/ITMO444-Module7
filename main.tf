# Terraform for Module 07
##############################################################################
# You will need to fill in the blank values using the values in terraform.tfvars
# or using the links to the documentation. You can also make use of the auto-complete
# in VSCode
# Reference your code in Module 04 to fill out the values
# This is the same exercise but converting from Bash to HCL
##############################################################################
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/vpc
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/vpcs
##############################################################################
data "aws_vpc" "main" {
  default = true
}

output "vpcs" {
  value = data.aws_vpc.main.id
}
##############################################################################
# https://developer.hashicorp.com/terraform/tutorials/configuration-language/data-source
##############################################################################
data "aws_availability_zones" "available" {
  state = "available"
  /*
  filter {
    name   = "zone-type"
    values = ["availability-zone"]
  }
*/
}

##############################################################################
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones
##############################################################################
data "aws_availability_zones" "primary" {
  filter {
    name   = "zone-name"
    values = ["us-east-2a"]
  }
}

data "aws_availability_zones" "secondary" {
  filter {
    name   = "zone-name"
    values = ["us-east-2b"]
  }
}

##############################################################################
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/subnets
##############################################################################
# The data value is essentially a query and or a filter to retrieve values
data "aws_subnets" "subneta" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }

  filter {
    name   = "availability-zone"
    values = ["us-east-2a"]
  }
}

data "aws_subnets" "subnetb" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }

  filter {
    name   = "availability-zone"
    values = ["us-east-2b"]
  }
}

data "aws_subnets" "subnetc" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }

  filter {
    name   = "availability-zone"
    values = ["us-east-2c"]
  }
}

output "subnetid-2a" {
  value = data.aws_subnets.subneta.ids
}

##############################################################################
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb
##############################################################################
resource "aws_lb" "lb" {
  name               = var.elb-name
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.vpc_security_group_ids]

  subnets = [
    data.aws_subnets.subneta.ids[0],
    data.aws_subnets.subnetb.ids[0]
  ]

  enable_deletion_protection = false

  tags = {
    assessment = var.module-tag
    Name       = var.elb-name
  }
}

# output will print a value out to the screen
output "url" {
  value = aws_lb.lb.dns_name
}

##############################################################################
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group
##############################################################################

resource "aws_lb_target_group" "alb_lb_tg" {
  # depends_on is effectively a waiter -- it forces this resource to wait until the listed
  # resource is ready
  depends_on  = [aws_lb.lb]
  name        = var.tg-name
  target_type = "instance"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.main.id

  health_check {
    enabled             = true
    protocol            = "HTTP"
    path                = "/"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  tags = {
    assessment = var.module-tag
    Name       = var.tg-name
  }
}

##############################################################################
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener
##############################################################################

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb_lb_tg.arn
  }
}

##############################################################################
# Create launch template
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/launch_template
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/launch_template
##############################################################################
resource "aws_launch_template" "mp1_lt" {
  name                                 = var.lt-name
  image_id                             = var.imageid
  instance_initiated_shutdown_behavior = "terminate"
  instance_type                        = var.instance-type
  key_name                             = var.key-name

  vpc_security_group_ids = [var.vpc_security_group_ids]

  monitoring {
    enabled = false
  }

  # Extra EBS volume 1
  block_device_mappings {
    device_name = "/dev/sdf"

    ebs {
      volume_size           = 8
      volume_type           = "gp3"
      delete_on_termination = true
    }
  }

  # Extra EBS volume 2
  block_device_mappings {
    device_name = "/dev/sdg"

    ebs {
      volume_size           = 8
      volume_type           = "gp3"
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name       = var.lt-name
      assessment = var.module-tag
    }
  }

  tag_specifications {
    resource_type = "volume"

    tags = {
      Name       = var.lt-name
      assessment = var.module-tag
    }
  }

  user_data = filebase64(var.install-env-file)

  tags = {
    assessment = var.module-tag
    Name       = var.lt-name
  }
}

##############################################################################
# Create autoscaling group
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_group
##############################################################################

resource "aws_autoscaling_group" "asg" {
  name                      = var.asg-name
  depends_on                = [aws_launch_template.mp1_lt, aws_lb_target_group.alb_lb_tg]
  desired_capacity          = var.desired
  max_size                  = var.max
  min_size                  = var.min
  health_check_grace_period = 300
  health_check_type         = "ELB"

  vpc_zone_identifier = [
    data.aws_subnets.subneta.ids[0],
    data.aws_subnets.subnetb.ids[0]
  ]

  launch_template {
    id      = aws_launch_template.mp1_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "assessment"
    value               = var.module-tag
    propagate_at_launch = true
  }

  tag {
    key                 = "Name"
    value               = var.asg-name
    propagate_at_launch = true
  }
}


##############################################################################
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_attachment
##############################################################################
# Create a new ALB Target Group attachment

resource "aws_autoscaling_attachment" "asg_attachment" {
  depends_on = [
    aws_autoscaling_group.asg,
    aws_lb_target_group.alb_lb_tg,
    aws_lb_listener.front_end
  ]

  autoscaling_group_name = aws_autoscaling_group.asg.name
  lb_target_group_arn    = aws_lb_target_group.alb_lb_tg.arn
}

output "alb_lb_tg-arn" {
  value = aws_lb_target_group.alb_lb_tg.arn
}

output "alb_lb_tg-id" {
  value = aws_lb_target_group.alb_lb_tg.id
}

##############################################################################
# S3 Buckets
##############################################################################
resource "aws_s3_bucket" "raw_bucket" {
  bucket = var.raw-s3-bucket

  tags = {
    assessment = var.module-tag
    Name       = var.raw-s3-bucket
  }
}

resource "aws_s3_bucket" "finished_bucket" {
  bucket = var.finished-s3-bucket

  tags = {
    assessment = var.module-tag
    Name       = var.finished-s3-bucket
  }
}

output "raw-s3-bucket" {
  value = aws_s3_bucket.raw_bucket.bucket
}

output "finished-s3-bucket" {
  value = aws_s3_bucket.finished_bucket.bucket
}