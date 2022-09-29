
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

output "Loadbalancer-address" {
  description = "DNS address of the loadbalancer"
  value = aws_lb.lb.dns_name
}
