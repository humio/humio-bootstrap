locals {
  vpc_name                  = var.vpc_name
  sg_name_external          = var.sg_name_external
  sg_name_internal          = var.sg_name_internal
  vpc_external_access_cidr  = var.vpc_external_access_cidr
  iam_name                  = var.iam_name
  humio_instance_name       = var.humio_instance_name
  region                    = var.region
  humio_instance_type       = var.humio_instance_type
  kafka_instance_type       = var.kafka_instance_type
  humio_instance_count      = var.humio_instance_count
  kafka_instance_count      = var.kafka_instance_count
  kafka_disk_size           = var.kafka_disk_size
  tags = {
    "Purpose" = "HumioBootstrap"
  }
}
