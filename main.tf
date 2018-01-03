provider "aws" {
  region = "${var.aws_region}"
}

resource "aws_iam_role_policy" "etc_jobs_summiter_policy" {
  name = "etc_jobs_summiter_policy"
  role = "${aws_iam_role.lambda_s3_execution_role.id}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "elastictranscoder:Read*",
        "elastictranscoder:List*",
        "elastictranscoder:*Job",
        "elastictranscoder:*Preset",
        "s3:List*",
        "iam:List*",
        "sns:List*"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "lambda_execute_policy" {
  name = "lambda_execute_policy"
  role = "${aws_iam_role.lambda_s3_execution_role.id}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:*"
      ],
      "Resource": "arn:aws:logs:*:*:*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject"
      ],
      "Resource": "arn:aws:s3:::*"
    }
  ]
}
EOF
}

resource "aws_iam_role" "lambda_s3_execution_role" {
  name = "lambda_s3_execution_role"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "ets_console_generated_policy" {
  name = "ets_console_generated_policy"
  role = "${aws_iam_role.ets_console_role.id}"

  policy = <<EOF
{
  "Version": "2008-10-17",
  "Statement": [
    {
      "Sid": "1",
      "Effect": "Allow",
      "Action": [
        "s3:Put*",
        "s3:ListBucket",
        "s3:*MultipartUpload*",
        "s3:Get*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "2",
      "Effect": "Allow",
      "Action": "sns:Publish",
      "Resource": "*"
    },
    {
      "Sid": "3",
      "Effect": "Deny",
      "Action": [
        "s3:*Delete*",
        "s3:*Policy*",
        "sns:*Remove*",
        "sns:*Delete*",
        "sns:*Permission*"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

# terraform import aws_iam_role.developer developer_name
resource "aws_iam_role" "ets_console_role" {
  name = "ets_console_role"
  assume_role_policy = <<EOF
{
  "Version": "2008-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "elastictranscoder.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": "1"
    }
  ]
}
EOF
}

resource "aws_s3_bucket" "video_upload_bucket" {
  bucket = "${var.video_upload_bucket_name}"
  region = "${var.aws_region}"
  acl    = "private"
}

resource "aws_s3_bucket" "video_transcoded_bucket" {
  bucket = "${var.video_transcoded_bucket_name}"
  region = "${var.aws_region}"
  acl    = "private"
}

resource "aws_elastictranscoder_pipeline" "video_transcode_pipeline" {
  input_bucket = "${aws_s3_bucket.video_upload_bucket.bucket}"
  name         = "${var.video_transcode_pipeline_name}"
  role         = "${aws_iam_role.ets_console_role.arn}"

  content_config = {
    bucket        = "${aws_s3_bucket.video_transcoded_bucket.bucket}"
    storage_class = "Standard"
  }

  thumbnail_config = {
    bucket        = "${aws_s3_bucket.video_transcoded_bucket.bucket}"
    storage_class = "Standard"
  }
}

resource "aws_lambda_function" "transcode_video_lambda" {
  function_name = "transcode_video_lambda"
  handler = "index.handler"
  runtime = "nodejs6.10"
  filename = "./transcode-video-lambda/transcode-video-lambda.zip"
  source_code_hash = "${base64sha256(file("./transcode-video-lambda/transcode-video-lambda.zip"))}"
  role = "${aws_iam_role.lambda_s3_execution_role.arn}"

  environment {
    variables = {
      ETC_PIPELINE_REGION = "${var.aws_region}"
      ETC_PIPELINE_ID     = "${aws_elastictranscoder_pipeline.video_transcode_pipeline.id}"
    }
  }
}

resource "aws_lambda_permission" "allow_bucket" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.transcode_video_lambda.arn}"
  principal     = "s3.amazonaws.com"
  source_arn    = "${aws_s3_bucket.video_upload_bucket.arn}"
}

resource "aws_s3_bucket_notification" "video_upload" {
  bucket = "${aws_s3_bucket.video_upload_bucket.id}"

  lambda_function {
    lambda_function_arn = "${aws_lambda_function.transcode_video_lambda.arn}"
    events              = ["s3:ObjectCreated:*"]
  }
}

# terraform console
output "pipeline_arn" {
  value = "${aws_elastictranscoder_pipeline.video_transcode_pipeline.arn}"
}