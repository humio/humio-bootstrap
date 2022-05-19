resource "aws_s3_bucket" "this" {
  bucket = "${var.bucket_prefix}-${random_string.random_suffix.result}"

  tags = local.tags
}

resource "aws_s3_bucket_object" "object" {
  bucket = aws_s3_bucket.this.id
  key    = "ansible.tar.gz"
  acl    = "private"
  source = "ansible.tar.gz"
  etag   = filemd5("${path.module}/ansible.tar.gz")
}

resource "aws_s3_bucket_acl" "this" {
  bucket = aws_s3_bucket.this.id
  acl    = "private"
}

resource "random_string" "random_suffix" {
  length  = 18
  special = false
  upper   = false
}

#resource "null_resource" "ansible" {
#  provisioner "local-exec" {
#    working_dir = path.module
#    command     = "tar -C ../ansible -czf ansible.tar.gz ."
#    interpreter = ["/bin/bash", "-c"]
#  }
#}
