# CodeCommit / CodeBuild / CodePipeline 素振り

CodeBuild のログが CloudWatch Logs に記録されているけど、勝手にロググループ・ストリームが作られており、
いまのところ Terraform で管理できない。

## CodeBuild の type=CODEPIPELINE

CodeBuild が CodePipeline から実行されるなら source や artifacts には `CODEPIPELINE` を指定する。

```
  source {
    type = "CODEPIPELINE"
  }

  artifacts {
    type = "CODEPIPELINE"
  }
```
