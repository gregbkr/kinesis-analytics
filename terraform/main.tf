provider "aws" {
  version = "~> 2.62"
  region = "eu-west-1"
  profile = "finstack"
}

terraform {
  required_version = "~> 0.12.0"
  backend "remote" {  
    hostname = "app.terraform.io"
    organization = "gregbkr"
    workspaces {
      name = "kinesis-analysis-dev"
    }
  }
}

variable "tag" {
  default = "kinesis-analysis-terra"
}
variable "cognito_pool" {
  default = "kinesis_analysis_terra"
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}


# S3 (data storage) 
resource "aws_s3_bucket" "b" {
  bucket = var.tag
  acl    = "private"
}

# COGNITO (user identity)
resource "aws_iam_role" "auth" {
  name = "${var.tag}-auth-role"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Principal": {
        "Federated": "cognito-identity.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "auth" {
  name = "${var.tag}-auth-policy"
  role = aws_iam_role.auth.id
  policy = <<-EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "mobileanalytics:PutEvents",
        "cognito-sync:*",
        "cognito-identity:*"
      ],
      "Resource": [
        "*"
      ]
    }
  ]
}
EOF
}

resource "aws_iam_role" "unauth" {
  name = "${var.tag}-unauth-role"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Principal": {
        "Federated": "cognito-identity.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "unauth" {
  name = "${var.tag}-unauth-policy"
  role = aws_iam_role.unauth.id
  policy = <<-EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "VisualEditor0",
      "Effect": "Allow",
      "Action": [
        "firehose:PutRecord",
        "firehose:PutRecordBatch"
      ],
      "Resource": "arn:aws:firehose:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:deliverystream/${var.tag}"
    },
    {
      "Sid": "VisualEditor1",
      "Effect": "Allow",
      "Action": [
        "mobileanalytics:PutEvents",
        "firehose:ListDeliveryStreams",
        "cognito-sync:*"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_cognito_identity_pool" "main" {
  identity_pool_name               = var.cognito_pool
  allow_unauthenticated_identities = true
}

resource "aws_cognito_identity_pool_roles_attachment" "main" {
  identity_pool_id = "${aws_cognito_identity_pool.main.id}"
  roles = {
    "authenticated" = "${aws_iam_role.auth.arn}"
    "unauthenticated" = "${aws_iam_role.unauth.arn}"
  }
}

# FIREHOSE (data extract & transform)
resource "aws_iam_role" "firehose" {
  name = "${var.tag}-firehose"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "firehose.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "firehose" {
  name = "${var.tag}-firehose-policy"
  role = aws_iam_role.firehose.id
  policy = <<-EOF
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Sid": "",
        "Effect": "Allow",
        "Action": [
          "glue:GetTable",
          "glue:GetTableVersion",
          "glue:GetTableVersions"
        ],
        "Resource": "*"
      },
      {
        "Sid": "",
        "Effect": "Allow",
        "Action": [
          "s3:AbortMultipartUpload",
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:PutObject"
        ],
        "Resource": [
          "arn:aws:s3:::${var.tag}",
          "arn:aws:s3:::${var.tag}/*",
          "arn:aws:s3:::%FIREHOSE_BUCKET_NAME%",
          "arn:aws:s3:::%FIREHOSE_BUCKET_NAME%/*"
        ]
      },
      {
        "Sid": "",
        "Effect": "Allow",
        "Action": [
          "lambda:InvokeFunction",
          "lambda:GetFunctionConfiguration"
        ],
        "Resource": "arn:aws:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:function:%FIREHOSE_DEFAULT_FUNCTION%:%FIREHOSE_DEFAULT_VERSION%"
      },
      {
        "Sid": "",
        "Effect": "Allow",
        "Action": [
            "logs:PutLogEvents"
        ],
        "Resource": [
          "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/kinesisfirehose/${var.tag}:log-stream:*"
        ]
      },
      {
        "Sid": "",
        "Effect": "Allow",
        "Action": [
          "kinesis:DescribeStream",
          "kinesis:GetShardIterator",
          "kinesis:GetRecords",
          "kinesis:ListShards"
        ],
        "Resource": "arn:aws:kinesis:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:stream/%FIREHOSE_STREAM_NAME%"
      },
      {
        "Effect": "Allow",
        "Action": [
          "kms:Decrypt"
        ],
        "Resource": [
          "arn:aws:kms:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:key/%SSE_KEY_ID%"
        ],
        "Condition": {
          "StringEquals": {
              "kms:ViaService": "kinesis.%REGION_NAME%.amazonaws.com"
          },
          "StringLike": {
              "kms:EncryptionContext:aws:kinesis:arn": "arn:aws:kinesis:%REGION_NAME%:${data.aws_caller_identity.current.account_id}:stream/%FIREHOSE_STREAM_NAME%"
          }
        }
      }
    ]
  }
  EOF
}

resource "aws_kinesis_firehose_delivery_stream" "stream" {
  name        = var.tag
  destination = "extended_s3"  

  extended_s3_configuration {

    role_arn            = aws_iam_role.firehose.arn
    bucket_arn          = aws_s3_bucket.b.arn
    prefix              = "destination/"
    error_output_prefix = "error/"
    buffer_size         = 64
    s3_backup_mode     = "Enabled"

    data_format_conversion_configuration {
      input_format_configuration {
        deserializer {
          open_x_json_ser_de {}
        }
      }
      output_format_configuration {
        serializer {
          parquet_ser_de {}
        }
      }
      schema_configuration {
        database_name = "kinesis-analytics-demo"
        role_arn      = "${aws_iam_role.firehose.arn}"
        table_name    = "destination"
        region        = "${data.aws_region.current.name}"
      }
    }
  
    s3_backup_configuration {
      role_arn           = "${aws_iam_role.firehose.arn}"
      bucket_arn         = "${aws_s3_bucket.b.arn}"
      prefix              = "source/"
    }
  }
}

# GLUE (data format)
resource "aws_glue_catalog_database" "glue" {
  name = var.tag
}

resource "aws_iam_role" "glue" {
  name = "${var.tag}-glue"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "glue.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "glue" {
  name = "${var.tag}-glue-policy"
  role = aws_iam_role.glue.id
  policy = <<-EOF
  {
    "Version": "2012-10-17",
    "Statement": [
        {
          "Effect": "Allow",
          "Action": [
            "s3:GetObject",
            "s3:PutObject"
          ],
          "Resource": [
            "arn:aws:s3:::${var.tag}*"
          ]
        }
    ]
  }
  EOF
}

resource "aws_iam_role_policy_attachment" "attach" {
  role       = aws_iam_role.glue.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_glue_crawler" "crawler" {
  database_name = "${aws_glue_catalog_database.glue.name}"
  name          = var.tag
  role          = "${aws_iam_role.glue.arn}"
  schedule      = "cron(0/5 * * * ? *)"
  s3_target {
    path = "s3://${aws_s3_bucket.b.bucket}/destination"
  }
}

# ATHENA (nothing to deploy)


# QUICKSIGN (dashboard)


# OUTPUTS

output "region" {
  value = data.aws_region.current.name
}
# output "account_id" {
#   value = data.aws_caller_identity.current.account_id
# }
output "aws_cognito_identity_pool_id" {
  value = aws_cognito_identity_pool.main.id
}
output "aws_firehose_name" {
  value = aws_kinesis_firehose_delivery_stream.stream.name
}
