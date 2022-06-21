data "aws_iam_policy_document" "this" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_instance_profile" "this" {
  name = "${local.iam_name}-${random_string.random_suffix.result}"
  role = aws_iam_role.this.name
}

resource "aws_iam_role" "this" {
  name = "${local.iam_name}-${random_string.random_suffix.result}"
  path = "/"

  assume_role_policy = data.aws_iam_policy_document.this.json
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "s3" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

resource "aws_iam_role_policy_attachment" "ec2" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess"
}

data "aws_iam_policy_document" "bucket_policy" {
  statement {
    effect = "Allow"

    actions = [
      "s3:ListBucket"
    ]

    resources = [
      "arn:aws:s3:::humio-${random_string.random_suffix.result}-bucket-storage",
      "arn:aws:s3:::${var.bucket_prefix}-${random_string.random_suffix.result}"
    ]
  }
  statement {
    effect = "Allow"

    actions = [
      "s3:GetObject",
    ]

    resources = [
      "arn:aws:s3:::${var.bucket_prefix}-${random_string.random_suffix.result}/*"
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject"
    ]

    resources = [
      "arn:aws:s3:::humio-${random_string.random_suffix.result}-bucket-storage/*",
    ]
  }
}

resource "aws_iam_policy" "bucket_storage_policy" {
  name        = "${local.iam_name}-${random_string.random_suffix.result}-bucket-storage"
  description = "Policy for S3 access for humio-bootstrap"
  policy      = data.aws_iam_policy_document.bucket_policy.json
}

resource "aws_iam_role_policy_attachment" "bucket_storage_attach" {
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.bucket_storage_policy.arn
}
