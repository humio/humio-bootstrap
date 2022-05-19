locals {
  vpc_name            = var.vpc_name
  sg_name             = var.sg_name
  iam_name            = var.iam_name
  humio_instance_name = var.humio_instance_name
  region              = var.region
  humio_instance_type = var.humio_instance_type
  kafka_instance_type = var.kafka_instance_type
  tags = {
    "Purpose" = "HumioBootstrap"
  }
}
