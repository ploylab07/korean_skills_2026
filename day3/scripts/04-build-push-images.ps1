# Build/push user, product, stress images via CodeBuild (no Docker Desktop).
# Encoding: UTF-8 with BOM
param(
    [string]$AppDir = (Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..")).Path "apps"),
    [string]$ImageTag = $env:IMAGE_TAG
)
. (Join-Path $PSScriptRoot "lib.ps1")
foreach ($cmd in @("aws")) { Require-Command $cmd }
Ensure-CoreState

$AppDir = (Resolve-Path $AppDir).Path
if (-not $ImageTag) { $ImageTag = [DateTime]::UtcNow.ToString('yyyyMMddHHmmss') }
$region = Get-AwsRegion
$accountId = ((& aws sts get-caller-identity --query Account --output text) | Out-String).Trim()
Assert-NativeSuccess "aws sts get-caller-identity"
$project = Get-ProjectName
$repos = (Get-TfOutputJson "ecr_repository_urls") | ConvertFrom-Json
$s3Bucket = Get-TfOutputRaw "image_bucket_name"

foreach ($app in @("user", "product", "stress")) {
    $binary = Join-Path $AppDir $app
    if (-not (Test-Path $binary -PathType Leaf)) { Fail "Required Linux binary not found: $binary" }
}

function Ensure-CodeBuildRole {
    param([string]$RoleName)
    $roleArn = ((& aws iam get-role --role-name $RoleName --query 'Role.Arn' --output text 2>$null) | Out-String).Trim()
    if ($LASTEXITCODE -eq 0 -and $roleArn -and $roleArn -ne 'None') { return $roleArn }

    $trust = @'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "codebuild.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
}
'@
    $trustFile = Join-Path ([IO.Path]::GetTempPath()) ("cb-trust-{0}.json" -f [guid]::NewGuid())
    $policyFile = Join-Path ([IO.Path]::GetTempPath()) ("cb-policy-{0}.json" -f [guid]::NewGuid())
    try {
        [IO.File]::WriteAllText($trustFile, $trust, [Text.UTF8Encoding]::new($false))
        & aws iam create-role --role-name $RoleName --assume-role-policy-document ("file://{0}" -f ($trustFile -replace '\\','/')) | Out-Null
        Assert-NativeSuccess "aws iam create-role"

        $policy = @"
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["logs:CreateLogGroup","logs:CreateLogStream","logs:PutLogEvents"],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject","s3:GetObjectVersion","s3:PutObject","s3:ListBucket"],
      "Resource": ["arn:aws:s3:::$s3Bucket","arn:aws:s3:::$s3Bucket/*"]
    },
    {
      "Effect": "Allow",
      "Action": ["ecr:GetAuthorizationToken"],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ecr:BatchCheckLayerAvailability","ecr:GetDownloadUrlForLayer","ecr:BatchGetImage",
        "ecr:PutImage","ecr:InitiateLayerUpload","ecr:UploadLayerPart","ecr:CompleteLayerUpload",
        "ecr:DescribeRepositories"
      ],
      "Resource": "arn:aws:ecr:${region}:${accountId}:repository/*"
    }
  ]
}
"@
        [IO.File]::WriteAllText($policyFile, $policy, [Text.UTF8Encoding]::new($false))
        & aws iam put-role-policy --role-name $RoleName --policy-name "${RoleName}-policy" --policy-document ("file://{0}" -f ($policyFile -replace '\\','/')) | Out-Null
        Assert-NativeSuccess "aws iam put-role-policy"
        Start-Sleep -Seconds 8
        $roleArn = ((& aws iam get-role --role-name $RoleName --query 'Role.Arn' --output text) | Out-String).Trim()
        Assert-NativeSuccess "aws iam get-role"
        return $roleArn
    }
    finally {
        Remove-Item $trustFile, $policyFile -Force -ErrorAction SilentlyContinue
    }
}

function Wait-CodeBuild {
    param([string]$BuildId)
    for ($i = 1; $i -le 90; $i++) {
        $status = ((& aws codebuild batch-get-builds --region $region --ids $BuildId --query 'builds[0].buildStatus' --output text) | Out-String).Trim()
        $phase = ((& aws codebuild batch-get-builds --region $region --ids $BuildId --query 'builds[0].currentPhase' --output text) | Out-String).Trim()
        Write-Host "[$i] $BuildId status=$status phase=$phase"
        if ($status -eq 'SUCCEEDED') { return }
        if ($status -in @('FAILED', 'FAULT', 'STOPPED', 'TIMED_OUT')) {
            & aws codebuild batch-get-builds --region $region --ids $BuildId --query 'builds[0].phases' --output json | Out-Host
            Fail "CodeBuild failed: $status"
        }
        Start-Sleep -Seconds 10
    }
    Fail "Timed out waiting for CodeBuild $BuildId"
}

$roleName = "$project-day3-codebuild"
$roleArn = Ensure-CodeBuildRole -RoleName $roleName

foreach ($app in @("user", "product", "stress")) {
    $repo = $repos.$app
    $repoName = ($repo -split '/')[-1]
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("apdev-$app-{0}" -f [guid]::NewGuid())
    $zipPath = Join-Path ([IO.Path]::GetTempPath()) ("apdev-$app-{0}.zip" -f [guid]::NewGuid())
    New-Item -ItemType Directory -Path $tmp | Out-Null
    try {
        Copy-Item (Join-Path $AppDir $app) (Join-Path $tmp $app)
        $dockerfile = @"
FROM public.ecr.aws/amazonlinux/amazonlinux:2023-minimal
ENV TZ=Asia/Seoul
WORKDIR /app
COPY $app /app/$app
RUN chmod 0755 /app/$app
EXPOSE 8080
ENTRYPOINT ["/app/$app"]
"@
        [IO.File]::WriteAllText((Join-Path $tmp 'Dockerfile'), $dockerfile, [Text.UTF8Encoding]::new($false))

        if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [IO.Compression.ZipFile]::CreateFromDirectory($tmp, $zipPath)

        $s3Key = "_codebuild/$app/source.zip"
        Write-Step "Upload $app build context to s3://$s3Bucket/$s3Key"
        Invoke-Aws s3 cp $zipPath "s3://$s3Bucket/$s3Key" --region $region --only-show-errors

        $cbName = ("{0}-{1}-img" -f $project, $app)
        if ($cbName.Length -gt 255) { $cbName = $cbName.Substring(0, 255) }

        $buildspec = @"
version: 0.2
phases:
  pre_build:
    commands:
      - aws ecr get-login-password --region `$AWS_DEFAULT_REGION | docker login --username AWS --password-stdin `$AWS_ACCOUNT_ID.dkr.ecr.`$AWS_DEFAULT_REGION.amazonaws.com
  build:
    commands:
      - docker build -t `$REPO_URI:build .
      - docker tag `$REPO_URI:build `$REPO_URI:`$IMAGE_TAG
      - docker tag `$REPO_URI:build `$REPO_URI:latest
  post_build:
    commands:
      - docker push `$REPO_URI:`$IMAGE_TAG
      - docker push `$REPO_URI:latest
"@

        $projFile = Join-Path ([IO.Path]::GetTempPath()) ("cb-proj-{0}.json" -f [guid]::NewGuid())
        $exists = (& aws codebuild batch-get-projects --region $region --names $cbName --query 'projects[0].name' --output text 2>$null | Out-String).Trim()
        $escSpec = $buildspec.Replace('\', '\\').Replace('"', '\"').Replace("`r", '').Replace("`n", '\n')
        $json = @"
{
  "name": "$cbName",
  "description": "day3 $app image (Windows contest, no local Docker)",
  "source": {
    "type": "S3",
    "location": "$s3Bucket/$s3Key",
    "buildspec": "$escSpec"
  },
  "artifacts": { "type": "NO_ARTIFACTS" },
  "environment": {
    "type": "LINUX_CONTAINER",
    "image": "aws/codebuild/amazonlinux2-x86_64-standard:5.0",
    "computeType": "BUILD_GENERAL1_SMALL",
    "privilegedMode": true,
    "imagePullCredentialsType": "CODEBUILD",
    "environmentVariables": [
      { "name": "AWS_DEFAULT_REGION", "value": "$region", "type": "PLAINTEXT" },
      { "name": "AWS_ACCOUNT_ID", "value": "$accountId", "type": "PLAINTEXT" },
      { "name": "REPO_URI", "value": "$repo", "type": "PLAINTEXT" },
      { "name": "IMAGE_TAG", "value": "$ImageTag", "type": "PLAINTEXT" }
    ]
  },
  "serviceRole": "$roleArn",
  "timeoutInMinutes": 30,
  "logsConfig": {
    "cloudWatchLogs": { "status": "ENABLED", "groupName": "/codebuild/$cbName" }
  }
}
"@
        try {
            [IO.File]::WriteAllText($projFile, $json, [Text.UTF8Encoding]::new($false))
            $fileUri = 'file://' + ($projFile -replace '\\', '/')
            if ($exists -and $exists -ne 'None' -and $exists -ne '') {
                Write-Step "Update CodeBuild project $cbName"
                # update-project uses same shape minus name nesting quirks — recreate via delete+create if update fails
                & aws codebuild update-project --region $region --cli-input-json $fileUri | Out-Null
                if ($LASTEXITCODE -ne 0) {
                    & aws codebuild delete-project --region $region --name $cbName | Out-Null
                    Start-Sleep -Seconds 3
                    & aws codebuild create-project --region $region --cli-input-json $fileUri | Out-Null
                    Assert-NativeSuccess "aws codebuild create-project"
                }
            }
            else {
                Write-Step "Create CodeBuild project $cbName"
                & aws codebuild create-project --region $region --cli-input-json $fileUri | Out-Null
                Assert-NativeSuccess "aws codebuild create-project"
            }
        }
        finally {
            Remove-Item $projFile -Force -ErrorAction SilentlyContinue
        }

        Write-Step "Start CodeBuild for $app`:$ImageTag"
        $buildId = ((& aws codebuild start-build --region $region --project-name $cbName --query 'build.id' --output text) | Out-String).Trim()
        Assert-NativeSuccess "aws codebuild start-build"
        Wait-CodeBuild -BuildId $buildId
    }
    finally {
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
    }
}

[IO.File]::WriteAllText((Join-Path $Script:Root '.image-tag'), $ImageTag, [Text.UTF8Encoding]::new($false))
Write-Host "Image tag: $ImageTag"
