data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-ebs"]
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server*"]
  }
}


module "ec2_humio" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "4.0.0"

  name                        = "humio-${random_string.random_suffix.result}-humio-${count.index}"
  count                       = 3
  user_data_replace_on_change = true
  user_data                   = file("${path.module}/user-data.sh")
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = local.humio_instance_type
  availability_zone           = module.vpc.azs[count.index]
  subnet_id                   = module.vpc.private_subnets[count.index]
  vpc_security_group_ids      = [module.security_group.security_group_id, aws_security_group.vpc_internal_http.id]
  iam_instance_profile        = aws_iam_instance_profile.this.name

  tags = merge(local.tags, { 
                            "humio-bootstrap-config" = "${aws_s3_bucket.bootstrap.id}",  
                            "humio-bootstrap-humio" = "true",  
                            "humio-cluster-id" = "humio-${random_string.random_suffix.result}",
                            "humio-cluster-index" = "${count.index}"
                           })

  depends_on =  [ module.vpc, module.ec2_kafka ]
}

module "ec2_kafka" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "4.0.0"

  name                        = "humio-${random_string.random_suffix.result}-kafka-${count.index}"
  count                       = 3
  user_data_replace_on_change = true
  user_data                   = file("${path.module}/user-data.sh")
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = local.kafka_instance_type
  availability_zone           = module.vpc.azs[count.index]
  subnet_id                   = module.vpc.private_subnets[count.index]
  vpc_security_group_ids      = [module.security_group.security_group_id]
  iam_instance_profile        = aws_iam_instance_profile.this.name

  tags = merge(local.tags, { 
                             "humio-bootstrap-config" = "${aws_s3_bucket.bootstrap.id}",  
                             "humio-bootstrap-kafka" = "true", 
                             "humio-bootstrap-zookeeper" = "true",  
                             "humio-cluster-id" = "humio-${random_string.random_suffix.result}",
                             "humio-cluster-index" = "${count.index}"
                           })
  depends_on =  [ module.vpc ]
}

resource "aws_volume_attachment" "kafka" {
  count       = 3
  device_name = "/dev/sdk"
  volume_id   = element(aws_ebs_volume.kafka.*.id, count.index)
  instance_id = element(module.ec2_kafka.*.id, count.index)
}

resource "aws_volume_attachment" "zookeeper" {
  count       = 3
  device_name = "/dev/sdz"
  volume_id   = element(aws_ebs_volume.zookeeper.*.id, count.index)
  instance_id = element(module.ec2_kafka.*.id, count.index)
}


####################################################
# Target Group Creation
####################################################

resource "aws_lb_target_group" "tg" {
  name        = "humio-tg-${random_string.random_suffix.result}"
  port        = 8080
  target_type = "instance"
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  health_check {
    port = 8080
  }
}

####################################################
# Target Group Attachment with Instance
####################################################

resource "aws_alb_target_group_attachment" "tgattachment" {
  count            = length(module.ec2_humio)
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = module.ec2_humio[count.index].id
}

####################################################
# Application Load balancer
####################################################

resource "aws_lb" "lb" {
  name               = "humio-alb-${random_string.random_suffix.result}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id, aws_security_group.vpc_internal_http.id]
  subnets            = module.vpc.public_subnets
}

####################################################
# Listner
####################################################

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.lb.arn
  port              = "8080"
  protocol          = "HTTP"

  default_action {
    type = "forward"

    # redirect {
    #   port        = "443"
    #   protocol    = "HTTPS"
    #   status_code = "HTTP_301"
    # }
    target_group_arn = aws_lb_target_group.tg.arn
  }
}


####################################################
# Listener Rule
####################################################

resource "aws_lb_listener_rule" "static" {
  listener_arn = aws_lb_listener.front_end.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn

  }

  condition {
    path_pattern {
      values = ["/"]
    }
  }
}