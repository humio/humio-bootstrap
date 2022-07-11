variable "vpc_name" {
  default = "humio-bootstrap"
}
variable "vpc_cidr_block" {
  default = "10.0.0.0/16"
}
variable "private_subnets" {
  default = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}
variable "public_subnets" {
  default = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
}
variable "vpc_external_access_cidr" {
  default = ["165.225.243.21/32"]
}
variable "sg_name_internal" {
  default = "humio-bootstrap-internal"
}

variable "sg_name_external" {
  default = "humio-bootstrap-external"
}
variable "iam_name" {
  default = "humio-bootstrap"
}
variable "humio_instance_name" {
  default = "humio-bootstrap"
}
variable "region" {
  default = "us-east-1"
}
variable "bucket_prefix" {
  default = "humio-bootstrap"
}
variable "humio_instance_type" {
  default = "i3.8xlarge"
}
variable "kafka_instance_type" {
  default = "m5.2xlarge"
}
variable "humio_instance_count" {
  default = 6
}
variable "kafka_instance_count" {
  default = 3
}