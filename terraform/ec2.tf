data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-ebs"]
  }
}

module "ec2_humio" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "4.0.0"

  name                        = "humio-instance"
  count                       = 3
  user_data_replace_on_change = true
  user_data                   = templatefile("${path.module}/user-data.sh", { bucket_name = aws_s3_bucket.this.id })
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = local.humio_instance_type
  availability_zone           = module.vpc.azs[count.index]
  subnet_id                   = module.vpc.private_subnets[count.index]
  vpc_security_group_ids      = [module.security_group.security_group_id]
  iam_instance_profile        = aws_iam_instance_profile.this.name

  tags = merge(local.tags, { "humio-bootstrap-humio" = "true" })
}

module "ec2_kafka" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "4.0.0"

  name                        = "kafka-instance"
  count                       = 3
  user_data_replace_on_change = true
  user_data                   = templatefile("${path.module}/user-data.sh", { bucket_name = aws_s3_bucket.this.id })
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = local.kafka_instance_type
  availability_zone           = module.vpc.azs[count.index]
  subnet_id                   = module.vpc.private_subnets[count.index]
  vpc_security_group_ids      = [module.security_group.security_group_id]
  iam_instance_profile        = aws_iam_instance_profile.this.name

  tags = merge(local.tags, { "humio-bootstrap-kafka" = "true", "humio-bootstrap-zookeeper" = "true" })
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
