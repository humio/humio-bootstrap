resource "aws_ebs_volume" "zookeeper" {
  count               = 3
  availability_zone   = element(module.vpc.azs, count.index)
  size                = 8
  type                = "gp3"

  tags = merge(local.tags, { "humio-bootstrap-zookeeper" = "true", "humio-mount-point" = "/var/lib/zookeeper" })
}

resource "aws_ebs_volume" "kafka" {
  count             = local.kafka_instance_count
  availability_zone   = element(module.vpc.azs, count.index)
  size              = local.kafka_disk_size
  type                = "gp2"

  tags = merge(local.tags, { "humio-bootstrap-kafka" = "true", "humio-mount-point" = "/var/lib/kafka" })
}
