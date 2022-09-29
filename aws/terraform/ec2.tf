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
  count                       = local.humio_instance_count
  user_data_replace_on_change = true
  user_data                   = file("${path.module}/user-data.sh")
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = local.humio_instance_type
  availability_zone           = element(module.vpc.azs, count.index)
  subnet_id                   = element(module.vpc.private_subnets, count.index)
  vpc_security_group_ids      = [module.security_group.security_group_id, aws_security_group.vpc_internal_http.id]
  iam_instance_profile        = aws_iam_instance_profile.this.name

  root_block_device = [{
    volume_type = "gp2"
    volume_size = 128
  }]

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
  count                       = local.kafka_instance_count
  user_data_replace_on_change = true
  user_data                   = file("${path.module}/user-data.sh")
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = local.kafka_instance_type
  availability_zone           = element(module.vpc.azs, count.index)
  subnet_id                   = element(module.vpc.private_subnets, count.index)
  vpc_security_group_ids      = [module.security_group.security_group_id]
  iam_instance_profile        = aws_iam_instance_profile.this.name

  tags = merge(local.tags, { 
                             "humio-bootstrap-config" = "${aws_s3_bucket.bootstrap.id}",  
                             "humio-bootstrap-kafka" = "true", 
                             "humio-cluster-id" = "humio-${random_string.random_suffix.result}",
                             "humio-cluster-index" = "${count.index}"
                             // remove these befor push!
                             "cstag-department" = "Humio Infra Eng - 118000"
                             "cstag-accounting" = "dev"
                           })
  root_block_device = [{
    volume_type = "gp2"
    volume_size = 128
  }]

  depends_on =  [ module.vpc , module.ec2_zookeeper ]
}

module "ec2_zookeeper" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "4.0.0"

  name                        = "humio-${random_string.random_suffix.result}-zookeeper-${count.index}"
  count                       = 3
  user_data_replace_on_change = true
  user_data                   = file("${path.module}/user-data.sh")
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "c5.large"
  availability_zone           = element(module.vpc.azs, count.index)
  subnet_id                   = element(module.vpc.private_subnets, count.index)
  vpc_security_group_ids      = [module.security_group.security_group_id]
  iam_instance_profile        = aws_iam_instance_profile.this.name

  root_block_device = [{
    volume_type = "gp2"
    volume_size = 32
  }]

  tags = merge(local.tags, { 
                             "humio-bootstrap-config" = "${aws_s3_bucket.bootstrap.id}",  
                             "humio-bootstrap-zookeeper" = "true",  
                             "humio-cluster-id" = "humio-${random_string.random_suffix.result}",
                             "humio-cluster-index" = "${count.index}"
                           })
  depends_on =  [ module.vpc ]
}

resource "aws_volume_attachment" "kafka" {
  count       = local.kafka_instance_count
  device_name = "/dev/sdk"
  volume_id   = element(aws_ebs_volume.kafka.*.id, count.index)
  instance_id = element(module.ec2_kafka.*.id, count.index)
}

resource "aws_volume_attachment" "zookeeper" {
  count       = 3
  device_name = "/dev/sdz"
  volume_id   = element(aws_ebs_volume.zookeeper.*.id, count.index)
  instance_id = element(module.ec2_zookeeper.*.id, count.index)
}
