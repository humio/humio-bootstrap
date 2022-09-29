module "security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 4.0"

  name        = "${local.sg_name_internal}-${random_string.random_suffix.result}"
  description = "Security group for example usage Humio bootstrap - internal network"
  vpc_id      = module.vpc.vpc_id

  ingress_cidr_blocks = [module.vpc.vpc_cidr_block]
  ingress_rules       = ["all-all"]
  egress_rules        = ["all-all"]
  

  tags = local.tags
}

# resource "aws_security_group" "vpc_tls" {
#   name_prefix = "${local.sg_name_external}-vpc_tls"
#   description = "Allow TLS inbound traffic"
#   vpc_id      = module.vpc.vpc_id

#   ingress {
#     description = "TLS from VPC"
#     from_port   = 443
#     to_port     = 443
#     protocol    = "tcp"
#     cidr_blocks = [module.vpc.vpc_cidr_block, join(",",local.vpc_external_access_cidr)]
#   }

#   tags = local.tags
# }

resource "aws_security_group" "alb_sg" {
  name_prefix = "${local.sg_name_external}-vpc-http"
  description = "Allow HTTP external traffic"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "8080 from the the external access cidr"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [join(",",local.vpc_external_access_cidr)]
  }

  tags = local.tags
}



resource "aws_security_group" "vpc_internal_http" {
  name_prefix = "${local.sg_name_internal}-vpc-http"
  description = "Allow HTTP inbound traffic from alb"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "8080 from ALBs"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  tags = local.tags
}

