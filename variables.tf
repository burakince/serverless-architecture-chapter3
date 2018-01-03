variable "aws_region" {
  default = "us-west-1"
}

variable "video_upload_bucket_name" {
  default = "serverless-video-upload"
}
variable "video_transcoded_bucket_name" {
  default = "serverless-video-transcoded"
}

variable "video_transcode_pipeline_name" {
  default = "serverless-video-transcode-pipeline"
}
