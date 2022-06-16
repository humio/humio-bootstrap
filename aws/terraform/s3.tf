resource "aws_s3_bucket" "bootstrap" {
  bucket = "${var.bucket_prefix}-${random_string.random_suffix.result}"

  tags = local.tags
}

resource "aws_s3_object" "object" {
  bucket = aws_s3_bucket.bootstrap.id
  key    = "ansible.tar.gz"
  acl    = "private"
  source = "ansible.tar.gz"
  etag   = filemd5("${path.module}/ansible.tar.gz")
  # depends_on = [
  #   null_resource.ansible
  # ]
}

resource "aws_s3_bucket_acl" "bootstrap" {
  bucket = aws_s3_bucket.bootstrap.id
  acl    = "private"
}

resource "random_string" "random_suffix" {
  length  = 9
  special = false
  upper   = false
}

resource "aws_s3_bucket" "bucket_storage" {
  bucket = "humio-${random_string.random_suffix.result}-bucket-storage"
  tags = local.tags
}

resource "aws_s3_bucket_acl" "bucket_storage" {
  bucket = aws_s3_bucket.bucket_storage.id
  acl    = "private"
}



# resource "null_resource" "ansible" {
#  provisioner "local-exec" {
#    working_dir = path.module
#    command     = "tar -C ../ansible -czf ansible.tar.gz ."
#    interpreter = ["/bin/bash", "-c"]
#  }
# }
