////////////////////////////////////////////////////////////////////////////////
// AWS

provider "aws" {
  region = "ap-northeast-1"
}

////////////////////////////////////////////////////////////////////////////////
/// CodeCommit

resource "aws_codecommit_repository" "repo" {
  repository_name = "test"
}

output "git_url_http" {
  value = "${aws_codecommit_repository.repo.clone_url_http}"
}

output "git_url_ssh" {
  value = "${aws_codecommit_repository.repo.clone_url_ssh}"
}

////////////////////////////////////////////////////////////////////////////////
/// IAM User for CodeCommit

resource "aws_iam_user" "user" {
  name = "test-commit-user"
}

resource "aws_iam_user_ssh_key" "user" {
  username   = "${aws_iam_user.user.name}"
  encoding   = "SSH"
  public_key = "${file("ssh.pub")}"
}

resource "aws_iam_user_policy" "user_policy" {
  name   = "test-commit-policy"
  user   = "${aws_iam_user.user.name}"
  policy = "${data.aws_iam_policy_document.user_policy.json}"
}

data "aws_iam_policy_document" "user_policy" {
  statement {
    actions = [
      "codecommit:GitPull",
      "codecommit:GitPush",
    ]

    resources = [
      "${aws_codecommit_repository.repo.arn}",
    ]
  }
}

output "ssh_user" {
  value = "${aws_iam_user_ssh_key.user.ssh_public_key_id}"
}

////////////////////////////////////////////////////////////////////////////////
/// CodeCommit Trigger

data "aws_sns_topic" "mail" {
  name = "mail"
}

resource "aws_codecommit_trigger" "trigger" {
  repository_name = "${aws_codecommit_repository.repo.repository_name}"

  trigger {
    name            = "test-trigger"
    events          = ["all"]
    branches        = ["master"]
    destination_arn = "${data.aws_sns_topic.mail.arn}"
  }
}

////////////////////////////////////////////////////////////////////////////////
/// Cloudwatch Event (CodeCommit Pull Request or Comment -> SNS)

resource "aws_cloudwatch_event_rule" "codecommit_comment_event_rule" {
  name = "test-codecommit-comment-event"

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
  rule       = "${aws_cloudwatch_event_rule.codecommit_comment_event_rule.name}"
  arn        = "${data.aws_sns_topic.mail.arn}"
  input_path = "$$.detail.notificationBody"
}

////////////////////////////////////////////////////////////////////////////////
/// S3

resource "aws_s3_bucket" "code" {
  bucket_prefix = "test-code-"
  acl           = "private"
  force_destroy = true
}

////////////////////////////////////////////////////////////////////////////////
/// CodeBuild

resource "aws_iam_role" "build_role" {
  name               = "test-build-role"
  assume_role_policy = "${data.aws_iam_policy_document.build_role.json}"
}

data "aws_iam_policy_document" "build_role" {
  statement {
    actions = [
      "sts:AssumeRole",
    ]

    principals = {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "build_policy" {
  name   = "test-build-policy"
  role   = "${aws_iam_role.build_role.id}"
  policy = "${data.aws_iam_policy_document.build_policy.json}"
}

data "aws_iam_policy_document" "build_policy" {
  statement {
    actions = [
      "codecommit:GitPull",
    ]

    resources = [
      "${aws_codecommit_repository.repo.arn}",
    ]
  }

  statement {
    actions = [
      "s3:GetObject",
      "s3:PutObject",
    ]

    resources = [
      "${aws_s3_bucket.code.arn}/*",
    ]
  }

  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = [
      "*",
    ]
  }
}

resource "aws_codebuild_project" "build" {
  name         = "test"
  service_role = "${aws_iam_role.build_role.arn}"

  source {
    type            = "CODECOMMIT"
    location        = "${aws_codecommit_repository.repo.clone_url_http}"
    git_clone_depth = 1

    // type = "CODEPIPELINE"
  }

  artifacts {
    type           = "S3"
    location       = "${aws_s3_bucket.code.bucket}"
    path           = "builds"
    namespace_type = "BUILD_ID"
    name           = "build.zip"
    packaging      = "ZIP"

    // type = "CODEPIPELINE"
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

resource "aws_iam_role" "pipeline_role" {
  name               = "test-pipeline-role"
  assume_role_policy = "${data.aws_iam_policy_document.pipeline_role.json}"
}

data "aws_iam_policy_document" "pipeline_role" {
  statement {
    actions = [
      "sts:AssumeRole",
    ]

    principals = {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "pipeline_policy" {
  name = "test-pipeline-policy"
  role = "${aws_iam_role.pipeline_role.id}"

  policy = "${data.aws_iam_policy_document.pipeline_policy.json}"
}

data "aws_iam_policy_document" "pipeline_policy" {
  statement {
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:UploadPart",
    ]

    resources = [
      "${aws_s3_bucket.code.arn}/*",
    ]
  }

  statement {
    actions = [
      "codebuild:BatchGetBuilds",
      "codebuild:StartBuild",
    ]

    resources = [
      "${aws_codebuild_project.build.arn}",
    ]
  }

  statement {
    actions = [
      "codecommit:GetBranch",
      "codecommit:GetCommit",
      "codecommit:GetUploadArchiveStatus",
      "codecommit:UploadArchive",
    ]

    resources = [
      "${aws_codecommit_repository.repo.arn}",
    ]
  }
}

resource "aws_codepipeline" "pipeline" {
  name     = "test"
  role_arn = "${aws_iam_role.pipeline_role.arn}"

  artifact_store {
    location = "${aws_s3_bucket.code.bucket}"
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
        RepositoryName       = "${aws_codecommit_repository.repo.repository_name}"
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
        ProjectName = "${aws_codebuild_project.build.name}"
      }

      input_artifacts  = ["source"]
      output_artifacts = ["build"]
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
        BucketName = "${aws_s3_bucket.code.bucket}"
        ObjectKey  = "public"
        Extract    = "true"
      }

      input_artifacts = ["build"]
    }
  }
}

////////////////////////////////////////////////////////////////////////////////
/// CloudWatch Event (CodeCommit -> CodePipeline)

resource "aws_iam_role" "start_pipeline_role" {
  name               = "test-start-pipeline-role"
  assume_role_policy = "${data.aws_iam_policy_document.start_pipeline_role.json}"
}

data "aws_iam_policy_document" "start_pipeline_role" {
  statement {
    actions = [
      "sts:AssumeRole",
    ]

    principals = {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "start_pipeline_policy" {
  name = "test-start-pipeline"
  role = "${aws_iam_role.start_pipeline_role.id}"

  policy = "${data.aws_iam_policy_document.start_pipeline_policy.json}"
}

data "aws_iam_policy_document" "start_pipeline_policy" {
  statement {
    actions = [
      "codepipeline:StartPipelineExecution",
    ]

    resources = [
      "${aws_codepipeline.pipeline.arn}",
    ]
  }
}

resource "aws_cloudwatch_event_rule" "codecommit_change_event_rule" {
  name = "test-codecommit-change-event"

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
  rule     = "${aws_cloudwatch_event_rule.codecommit_change_event_rule.name}"
  arn      = "${aws_codepipeline.pipeline.arn}"
  role_arn = "${aws_iam_role.start_pipeline_role.arn}"
}
