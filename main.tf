////////////////////////////////////////////////////////////////////////////////
// Variables

variable "prefix" {
  default = "oreore-code"
}

////////////////////////////////////////////////////////////////////////////////
// AWS

provider "aws" {
  region = "ap-northeast-1"
}

////////////////////////////////////////////////////////////////////////////////
/// CodeCommit

resource "aws_codecommit_repository" "repo" {
  repository_name = "${var.prefix}-repo"
}

output "git_url_http" {
  value = aws_codecommit_repository.repo.clone_url_http
}

output "git_url_ssh" {
  value = aws_codecommit_repository.repo.clone_url_ssh
}

////////////////////////////////////////////////////////////////////////////////
/// CodeCommit Trigger

resource "aws_sns_topic" "mail" {
  name = "${var.prefix}-mail"
}

resource "aws_codecommit_trigger" "trigger" {
  repository_name = aws_codecommit_repository.repo.repository_name

  trigger {
    name            = "${var.prefix}-trigger"
    events          = ["all"]
    branches        = ["master"]
    destination_arn = aws_sns_topic.mail.arn
  }
}

////////////////////////////////////////////////////////////////////////////////
/// Cloudwatch Event (CodeCommit Pull Request or Comment -> SNS)

resource "aws_cloudwatch_event_rule" "codecommit_comment_event_rule" {
  name = "${var.prefix}-codecommit-comment-event"

  event_pattern = <<EOS
  {
    "source": [
      "aws.codecommit"
    ],
    "resources": [
      "${aws_codecommit_repository.repo.arn}"
    ],
    "detail-type": [
      "CodeCommit Pull Request State Change",
      "CodeCommit Comment on Pull Request",
      "CodeCommit Comment on Commit"
    ]
  }
EOS
}

resource "aws_cloudwatch_event_target" "codecommit_comment_event_target" {
  rule       = aws_cloudwatch_event_rule.codecommit_comment_event_rule.name
  arn        = aws_sns_topic.mail.arn
  input_path = "$.detail.notificationBody"
}

////////////////////////////////////////////////////////////////////////////////
/// S3

resource "aws_s3_bucket" "code" {
  bucket_prefix = "${var.prefix}-code-"
  acl           = "private"
  force_destroy = true
}

////////////////////////////////////////////////////////////////////////////////
/// Logs

resource "aws_cloudwatch_log_group" "build_log" {
  name_prefix       = "${var.prefix}-build-log-"
  retention_in_days = 1
}

resource "aws_cloudwatch_log_group" "build_log_2nd" {
  name              = "/aws/codebuild/${aws_codebuild_project.build_2nd.name}"
  retention_in_days = 1
}

////////////////////////////////////////////////////////////////////////////////
/// CodeBuild

resource "aws_codebuild_project" "build" {
  name         = "${var.prefix}-build"
  service_role = aws_iam_role.build_role.arn

  source {
    type = "CODEPIPELINE"
  }

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    type            = "LINUX_CONTAINER"
    image           = "aws/codebuild/docker:18.09.0-1.7.0"
    compute_type    = "BUILD_GENERAL1_SMALL"
    privileged_mode = true
  }

  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.build_log.name
    }
  }
}

////////////////////////////////////////////////////////////////////////////////
/// CodeBuild 2nd

resource "aws_codebuild_project" "build_2nd" {
  name         = "${var.prefix}-build-2nd"
  service_role = aws_iam_role.build_role.arn

  source {
    type = "CODEPIPELINE"
    buildspec           = "buildspec-2nd.yml"
  }

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    type            = "LINUX_CONTAINER"
    image           = "aws/codebuild/docker:18.09.0-1.7.0"
    compute_type    = "BUILD_GENERAL1_SMALL"
    privileged_mode = true
  }
}

////////////////////////////////////////////////////////////////////////////////
/// CodePipeline

resource "aws_codepipeline" "pipeline" {
  name     = "${var.prefix}-pipeline"
  role_arn = aws_iam_role.pipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.code.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeCommit"
      version          = "1"
      output_artifacts = ["source"]

      configuration = {
        RepositoryName       = aws_codecommit_repository.repo.repository_name
        BranchName           = "master"
        PollForSourceChanges = "false"
      }
    }
  }

  stage {
    name = "Build"

    action {
      name     = "Build"
      category = "Build"
      owner    = "AWS"
      provider = "CodeBuild"
      version  = "1"

      configuration = {
        ProjectName = aws_codebuild_project.build.name
      }

      input_artifacts  = ["source"]
      output_artifacts = ["build"]
    }
  }

  stage {
    name = "Build-2nd"

    action {
      name     = "Build"
      category = "Build"
      owner    = "AWS"
      provider = "CodeBuild"
      version  = "1"

      configuration = {
        ProjectName = aws_codebuild_project.build_2nd.name
        PrimarySource = "source"
      }

      input_artifacts  = ["source", "build"]
      output_artifacts = ["build-2nd"]
    }
  }

  stage {
    name = "Deploy"

    action {
      name     = "Deploy"
      category = "Deploy"
      owner    = "AWS"
      provider = "S3"
      version  = "1"

      configuration = {
        BucketName = aws_s3_bucket.code.bucket
        ObjectKey  = "public"
        Extract    = "true"
      }

      input_artifacts = ["build-2nd"]
    }
  }
}

////////////////////////////////////////////////////////////////////////////////
/// CloudWatch Event (CodeCommit -> CodePipeline)

resource "aws_cloudwatch_event_rule" "codecommit_change_event_rule" {
  name = "${var.prefix}-codecommit-change-event"

  event_pattern = <<EOS
  {
    "source": [
      "aws.codecommit"
    ],
    "detail-type": [
      "CodeCommit Repository State Change"
    ],
    "resources": [
      "${aws_codecommit_repository.repo.arn}"
    ],
    "detail": {
      "event": [
        "referenceCreated",
        "referenceUpdated"
      ],
      "referenceType": [
        "branch"
      ],
      "referenceName": [
        "master"
      ]
    }
  }
EOS
}

resource "aws_cloudwatch_event_target" "codecommit_change_event_target" {
  rule     = aws_cloudwatch_event_rule.codecommit_change_event_rule.name
  arn      = aws_codepipeline.pipeline.arn
  role_arn = aws_iam_role.start_pipeline_role.arn
}
