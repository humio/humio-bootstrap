resource "aws_ebs_volume" "zookeeper" {
  count             = 3
  availability_zone = module.vpc.azs[count.index]
  size              = 8

  tags = merge(local.tags, { "humio-bootstrap-zookeeper" = "true", "mount_point" = "/var/zookeeper" })
}

resource "aws_ebs_volume" "kafka" {
  count             = 3
  availability_zone = module.vpc.azs[count.index]
  size              = 250

  tags = merge(local.tags, { "humio-bootstrap-kafka" = "true", "mount_point" = "/var/kafka" })
}
