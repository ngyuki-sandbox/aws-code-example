////////////////////////////////////////////////////////////////////////////////
/// CodeCommit

resource "aws_iam_user" "user" {
  name = "${var.prefix}-commit-user"
}

resource "aws_iam_user_ssh_key" "user" {
  username   = aws_iam_user.user.name
  encoding   = "SSH"
  public_key = file("ssh.pub")
}

resource "aws_iam_user_policy" "user_policy" {
  name = "${var.prefix}-commit-policy"
  user = aws_iam_user.user.name

  policy = jsonencode({
    Version : "2012-10-17",
    Statement : [{
      Action : [
        "codecommit:GitPush",
        "codecommit:GitPull",
      ],
      Effect : "Allow",
      Resource : aws_codecommit_repository.repo.arn,
    }]
  })
}

output "ssh_user" {
  value = aws_iam_user_ssh_key.user.ssh_public_key_id
}

////////////////////////////////////////////////////////////////////////////////
/// CodeBuild

resource "aws_iam_role" "build_role" {
  name = "${var.prefix}-build-role"

  assume_role_policy = jsonencode({
    Version : "2012-10-17",
    Statement : [{
      Action : "sts:AssumeRole",
      Effect : "Allow",
      Principal : {
        Service: "codebuild.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "build_policy" {
  name = "${var.prefix}-build-policy"
  role = aws_iam_role.build_role.id

  policy = jsonencode({
    Version : "2012-10-17",
    Statement : [
      {
        Action : ["codecommit:GitPull"]
        Effect : "Allow",
        Resource : aws_codecommit_repository.repo.arn,
      },
      {
        Action : [
          "s3:GetObject",
          "s3:PutObject",
        ]
        Effect : "Allow",
        Resource : "${aws_s3_bucket.code.arn}/*"
      },
      {
        Action : [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Effect : "Allow",
        Resource : "*"
      },
    ],
  })
}

////////////////////////////////////////////////////////////////////////////////
/// CodePipeline

resource "aws_iam_role" "pipeline_role" {
  name = "${var.prefix}-pipeline-role"

  assume_role_policy = jsonencode({
    Version : "2012-10-17",
    Statement : {
      Action : "sts:AssumeRole",
      Effect : "Allow",
      Principal : {
        Service: "codepipeline.amazonaws.com",
      }
    }
  })
}

resource "aws_iam_role_policy" "pipeline_policy" {
  name = "${var.prefix}-pipeline-policy"
  role = aws_iam_role.pipeline_role.id

  policy = jsonencode({
    Version : "2012-10-17",
    Statement : [
      {
        Action : [
          "codecommit:GetBranch",
          "codecommit:GetCommit",
          "codecommit:GetUploadArchiveStatus",
          "codecommit:UploadArchive",
        ]
        Effect : "Allow",
        Resource : aws_codecommit_repository.repo.arn
      },
      {
        Action : [
          "s3:GetObject",
          "s3:PutObject",
          "s3:UploadPart",
        ]
        Effect : "Allow",
        Resource : "${aws_s3_bucket.code.arn}/*"
      },
      {
        Action : [
          "codebuild:BatchGetBuilds",
          "codebuild:StartBuild",
        ]
        Effect : "Allow",
        Resource : aws_codebuild_project.build.arn
      }
    ],
  })
}

////////////////////////////////////////////////////////////////////////////////
/// CloudWatch Event (CodeCommit -> CodePipeline)

resource "aws_iam_role" "start_pipeline_role" {
  name = "${var.prefix}-start-pipeline-role"

  assume_role_policy = jsonencode({
    Version : "2012-10-17",
    Statement : [{
      Action : "sts:AssumeRole",
      Effect : "Allow",
      Principal : {
        Service: "events.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "start_pipeline_policy" {
  name = "${var.prefix}-start-pipeline"
  role = aws_iam_role.start_pipeline_role.id

  policy = jsonencode({
    Version : "2012-10-17",
    Statement : [{
      Action : [
        "codepipeline:StartPipelineExecution",
      ],
      Effect : "Allow",
      Resource : aws_codepipeline.pipeline.arn,
    }]
  })
}
