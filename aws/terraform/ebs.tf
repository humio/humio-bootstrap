resource "aws_ebs_volume" "zookeeper" {
  count             = 3
  availability_zone = module.vpc.azs[count.index]
  size              = 8

  tags = merge(local.tags, { "humio-bootstrap-zookeeper" = "true", "humio-mount-point" = "/var/lib/zookeeper" })
}

resource "aws_ebs_volume" "kafka" {
  count             = 3
  availability_zone = module.vpc.azs[count.index]
  size              = 250

  tags = merge(local.tags, { "humio-bootstrap-kafka" = "true", "humio-mount-point" = "/var/lib/kafka" })
}
