module "security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 4.0"

  name        = local.sg_name
  description = "Security group for example usage Humio bootstrap"
  vpc_id      = module.vpc.vpc_id

  ingress_cidr_blocks = [module.vpc.vpc_cidr_block]
  ingress_rules       = ["all-all"]
  egress_rules        = ["all-all"]

  tags = local.tags
}

resource "aws_security_group" "vpc_tls" {
  name_prefix = "${local.sg_name}-vpc_tls"
  description = "Allow TLS inbound traffic"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "TLS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [module.vpc.vpc_cidr_block]
  }

  tags = local.tags
}
