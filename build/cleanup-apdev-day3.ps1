# Wipe day3 (apdev-dev-*) AWS leftovers not reliably tracked in terraform state.
# Requires aws CLI + credentials from .env. Encoding: UTF-8 with BOM.
# Note: under $ErrorActionPreference=Stop, aws stderr becomes NativeCommandError —
# always run aws with Continue + redirect.

function Invoke-AwsQuiet {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$AwsArgs)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    & aws @AwsArgs 1>$null 2>$null | Out-Null
    $code = $LASTEXITCODE
    if ($null -eq $code) { $code = 0 }
    $ErrorActionPreference = $prev
    return [int]$code
}

function Get-AwsText {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$AwsArgs)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $out = & aws @AwsArgs 2>$null
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    if ($null -eq $code) { $code = 1 }
    if ([int]$code -ne 0) { return "" }
    if ($null -eq $out) { return "" }
    $text = ($out | ForEach-Object { "$_" }) -join "`n"
    $text = $text.Trim()
    if ($text -eq "None" -or $text -eq "null") { return "" }
    return $text
}

function Get-AwsTokens {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$AwsArgs)
    $text = Get-AwsText @AwsArgs
    if (-not $text) { return @() }
    return @($text -split '\s+' | Where-Object { $_ -and $_.Trim() -ne '' })
}

function Clear-ApdevDay3Leftovers {
    param(
        [string]$Region = "ap-northeast-2",
        [string]$Prefix = "",
        [string]$DbIdentifier = ""
    )

    if (-not $Prefix) {
        if ($env:APDEV_PREFIX) {
            $Prefix = $env:APDEV_PREFIX
        }
        else {
            $proj = if ($env:TF_VAR_project) { $env:TF_VAR_project } elseif ($env:DAY3_PROJECT) { $env:DAY3_PROJECT } else { "apdev" }
            $envName = if ($env:TF_VAR_environment) { $env:TF_VAR_environment } elseif ($env:DAY3_ENVIRONMENT) { $env:DAY3_ENVIRONMENT } else { "dev" }
            $Prefix = "{0}-{1}" -f $proj, $envName
        }
    }
    if (-not $DbIdentifier) {
        $DbIdentifier = if ($env:TF_VAR_db_identifier) { $env:TF_VAR_db_identifier } elseif ($env:DB_IDENTIFIER) { $env:DB_IDENTIFIER } else { "apdev-rds-instance" }
    }

    if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
        Write-Host "[!] aws CLI not found - skip day3 leftover wipe" -ForegroundColor Yellow
        return
    }

    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    try {
        Write-Host ""
        Write-Host (">>> Wiping day3 leftovers named {0}-* (may take several minutes)" -f $Prefix) -ForegroundColor Cyan
        $env:AWS_DEFAULT_REGION = $Region
        $account = Get-AwsText sts get-caller-identity --query Account --output text
        if (-not $account) {
            Write-Host "[!] AWS credentials invalid - skip wipe" -ForegroundColor Yellow
            return
        }

        # CloudFront distributions tagged/commented for this project (edge stack)
        $distIds = Get-AwsTokens cloudfront list-distributions --query "DistributionList.Items[?contains(Comment, '$Prefix') || contains(Origins.Items[0].Id, '$Prefix')].Id" --output text
        foreach ($id in $distIds) {
            Write-Host "  disable/delete CloudFront $id"
            $cfg = Get-AwsText cloudfront get-distribution-config --id $id --output json
            if ($cfg) {
                $tmp = Join-Path $env:TEMP ("cf-$id.json")
                try {
                    $obj = $cfg | ConvertFrom-Json
                    $etag = $obj.ETag
                    $obj.DistributionConfig.Enabled = $false
                    ($obj.DistributionConfig | ConvertTo-Json -Depth 40) | Set-Content -LiteralPath $tmp -Encoding UTF8
                    $null = Invoke-AwsQuiet cloudfront update-distribution --id $id --if-match $etag --distribution-config ("file://{0}" -f ($tmp -replace '\\', '/'))
                    Start-Sleep -Seconds 5
                    $etag2 = Get-AwsText cloudfront get-distribution-config --id $id --query ETag --output text
                    $null = Invoke-AwsQuiet cloudfront delete-distribution --id $id --if-match $etag2
                }
                catch {
                    Write-Host ("  cloudfront wipe skip {0}: {1}" -f $id, $_) -ForegroundColor DarkYellow
                }
                finally {
                    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
                }
            }
        }

        # ALBs / target groups created by AWS LB Controller often named after project
        foreach ($arn in (Get-AwsTokens elbv2 describe-load-balancers --query "LoadBalancers[?contains(LoadBalancerName, '$Prefix')].LoadBalancerArn" --output text)) {
            Write-Host "  delete ALB $arn"
            $null = Invoke-AwsQuiet elbv2 delete-load-balancer --load-balancer-arn $arn
        }
        Start-Sleep -Seconds 10
        foreach ($arn in (Get-AwsTokens elbv2 describe-target-groups --query "TargetGroups[?contains(TargetGroupName, '$Prefix')].TargetGroupArn" --output text)) {
            $null = Invoke-AwsQuiet elbv2 delete-target-group --target-group-arn $arn
        }

        # EKS cluster
        $cluster = "$Prefix-cluster"
        $exists = Get-AwsText eks describe-cluster --name $cluster --query "cluster.name" --output text
        if ($exists) {
            foreach ($ng in (Get-AwsTokens eks list-nodegroups --cluster-name $cluster --query "nodegroups" --output text)) {
                Write-Host "  delete nodegroup $ng"
                $null = Invoke-AwsQuiet eks delete-nodegroup --cluster-name $cluster --nodegroup-name $ng
                $null = Invoke-AwsQuiet eks wait nodegroup-deleted --cluster-name $cluster --nodegroup-name $ng
            }
            # Access entries (ignore failures)
            foreach ($p in (Get-AwsTokens eks list-access-entries --cluster-name $cluster --query "accessEntries" --output text)) {
                $null = Invoke-AwsQuiet eks delete-access-entry --cluster-name $cluster --principal-arn $p
            }
            Write-Host "  delete EKS $cluster"
            $null = Invoke-AwsQuiet eks delete-cluster --name $cluster
            $null = Invoke-AwsQuiet eks wait cluster-deleted --name $cluster
        }
        else {
            Write-Host "  EKS $cluster not found - skip"
        }

        # RDS instance
        $dbId = $DbIdentifier
        $db = Get-AwsText rds describe-db-instances --db-instance-identifier $dbId --query "DBInstances[0].DBInstanceIdentifier" --output text
        if ($db) {
            Write-Host "  delete RDS $dbId"
            $null = Invoke-AwsQuiet rds delete-db-instance --db-instance-identifier $dbId --skip-final-snapshot --delete-automated-backups
            $null = Invoke-AwsQuiet rds wait db-instance-deleted --db-instance-identifier $dbId
        }

        $null = Invoke-AwsQuiet rds delete-db-subnet-group --db-subnet-group-name "$Prefix-db-subnet"
        $null = Invoke-AwsQuiet rds delete-db-parameter-group --db-parameter-group-name "$Prefix-mysql8"

        # ECR repos
        foreach ($repo in @("$Prefix-user", "$Prefix-product", "$Prefix-stress")) {
            Write-Host "  delete ECR $repo"
            $null = Invoke-AwsQuiet ecr delete-repository --repository-name $repo --force
        }

        # S3 buckets
        foreach ($bucket in @("$Prefix-images-$account", "$Prefix-alb-logs-$account")) {
            $owned = Get-AwsText s3api head-bucket --bucket $bucket --query "BucketRegion" --output text
            # head-bucket returns empty on success with some CLIs; also try list
            $listed = Get-AwsText s3api list-buckets --query "Buckets[?Name=='$bucket'].Name | [0]" --output text
            if ($listed -or $owned) {
                Write-Host "  empty/delete S3 $bucket"
                $null = Invoke-AwsQuiet s3 rm "s3://$bucket" --recursive
                # versioned objects
                $versions = Get-AwsText s3api list-object-versions --bucket $bucket --output json
                $null = Invoke-AwsQuiet s3api delete-bucket --bucket $bucket
            }
        }

        # IAM roles: exact names + module-generated prefixes (…-aws-lbc-<hash>, cluster/node roles)
        $roleNames = New-Object System.Collections.Generic.HashSet[string]
        foreach ($role in @("$Prefix-rds-monitoring", "$Prefix-product-pod", "$Prefix-db-init-pod", "$Prefix-aws-lbc", "$Prefix-cluster-autoscaler", "$Prefix-cluster", "$Prefix-main-eks-node-group")) {
            [void]$roleNames.Add($role)
        }
        foreach ($role in (Get-AwsTokens iam list-roles --query "Roles[?starts_with(RoleName, '$Prefix')].RoleName" --output text)) {
            [void]$roleNames.Add($role)
        }
        foreach ($role in $roleNames) {
            Write-Host "  delete IAM role $role"
            foreach ($ip in (Get-AwsTokens iam list-instance-profiles-for-role --role-name $role --query "InstanceProfiles[].InstanceProfileName" --output text)) {
                $null = Invoke-AwsQuiet iam remove-role-from-instance-profile --instance-profile-name $ip --role-name $role
                $null = Invoke-AwsQuiet iam delete-instance-profile --instance-profile-name $ip
            }
            foreach ($pol in (Get-AwsTokens iam list-attached-role-policies --role-name $role --query "AttachedPolicies[].PolicyArn" --output text)) {
                $null = Invoke-AwsQuiet iam detach-role-policy --role-name $role --policy-arn $pol
            }
            foreach ($pol in (Get-AwsTokens iam list-role-policies --role-name $role --query "PolicyNames" --output text)) {
                $null = Invoke-AwsQuiet iam delete-role-policy --role-name $role --policy-name $pol
            }
            $null = Invoke-AwsQuiet iam delete-role --role-name $role
        }

        # Customer-managed policies left by EKS encryption policy (name prefixes)
        foreach ($parn in (Get-AwsTokens iam list-policies --scope Local --query "Policies[?starts_with(PolicyName, '$Prefix')].Arn" --output text)) {
            Write-Host "  delete IAM policy $parn"
            foreach ($ver in (Get-AwsTokens iam list-policy-versions --policy-arn $parn --query "Versions[?IsDefaultVersion==``false``].VersionId" --output text)) {
                $null = Invoke-AwsQuiet iam delete-policy-version --policy-arn $parn --version-id $ver
            }
            $null = Invoke-AwsQuiet iam delete-policy --policy-arn $parn
        }

        # WAF WebACL (REGIONAL)
        $wafIds = Get-AwsTokens wafv2 list-web-acls --scope REGIONAL --query "WebACLs[?Name=='$Prefix-waf'].Id" --output text
        foreach ($wid in $wafIds) {
            $lock = Get-AwsText wafv2 get-web-acl --scope REGIONAL --id $wid --name "$Prefix-waf" --query LockToken --output text
            Write-Host "  delete WAF $Prefix-waf"
            $null = Invoke-AwsQuiet wafv2 delete-web-acl --scope REGIONAL --id $wid --name "$Prefix-waf" --lock-token $lock
        }

        # CloudWatch log groups
        foreach ($lg in @("aws-waf-logs-$Prefix", "/aws/eks/$Prefix-cluster/cluster")) {
            Write-Host "  delete log group $lg"
            $null = Invoke-AwsQuiet logs delete-log-group --log-group-name $lg
        }

        # CodeBuild projects created by image push scripts
        foreach ($p in (Get-AwsTokens codebuild list-projects --output text)) {
            if ($p -like "$Prefix-*-img" -or $p -like "$Prefix-day3*") {
                Write-Host "  delete CodeBuild $p"
                $null = Invoke-AwsQuiet codebuild delete-project --name $p
            }
        }

        # KMS alias left by EKS module (do not delete CMK blindly; only alias)
        $alias = "alias/eks/$Prefix-cluster"
        $null = Invoke-AwsQuiet kms delete-alias --alias-name $alias

        # SNS topic
        $topic = Get-AwsText sns list-topics --query "Topics[?contains(TopicArn, '$Prefix-alerts')].TopicArn | [0]" --output text
        if ($topic) {
            Write-Host "  delete SNS $topic"
            $null = Invoke-AwsQuiet sns delete-topic --topic-arn $topic
        }

        # CloudWatch alarms
        foreach ($a in (Get-AwsTokens cloudwatch describe-alarms --alarm-name-prefix $Prefix --query "MetricAlarms[].AlarmName" --output text)) {
            Write-Host "  delete alarm $a"
            $null = Invoke-AwsQuiet cloudwatch delete-alarms --alarm-names $a
        }

        # Security groups + VPC tagged Project=apdev
        $vpc = Get-AwsText ec2 describe-vpcs --filters "Name=tag:Name,Values=$Prefix" --query "Vpcs[0].VpcId" --output text
        if (-not $vpc) {
            $vpc = Get-AwsText ec2 describe-vpcs --filters "Name=tag:Project,Values=apdev" "Name=tag:Environment,Values=dev" --query "Vpcs[0].VpcId" --output text
        }
        if ($vpc) {
            Write-Host "  cleanup VPC $vpc"
            foreach ($nat in (Get-AwsTokens ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$vpc" "Name=state,Values=available,pending" --query "NatGateways[].NatGatewayId" --output text)) {
                $null = Invoke-AwsQuiet ec2 delete-nat-gateway --nat-gateway-id $nat
            }
            for ($i = 0; $i -lt 40; $i++) {
                $left = Get-AwsTokens ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$vpc" "Name=state,Values=available,pending,deleting" --query "NatGateways[].NatGatewayId" --output text
                if ($left.Count -eq 0) { break }
                Start-Sleep -Seconds 10
            }
            foreach ($a in (Get-AwsTokens ec2 describe-addresses --filters "Name=domain,Values=vpc" --query "Addresses[?AssociationId==null].AllocationId" --output text)) {
                $null = Invoke-AwsQuiet ec2 release-address --allocation-id $a
            }
            foreach ($ep in (Get-AwsTokens ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$vpc" --query "VpcEndpoints[].VpcEndpointId" --output text)) {
                $null = Invoke-AwsQuiet ec2 delete-vpc-endpoints --vpc-endpoint-ids $ep
            }
            foreach ($igw in (Get-AwsTokens ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$vpc" --query "InternetGateways[].InternetGatewayId" --output text)) {
                $null = Invoke-AwsQuiet ec2 detach-internet-gateway --internet-gateway-id $igw --vpc-id $vpc
                $null = Invoke-AwsQuiet ec2 delete-internet-gateway --internet-gateway-id $igw
            }
            foreach ($rt in (Get-AwsTokens ec2 describe-route-tables --filters "Name=vpc-id,Values=$vpc" --query "RouteTables[?Associations[0].Main!=``true``].RouteTableId" --output text)) {
                $null = Invoke-AwsQuiet ec2 delete-route-table --route-table-id $rt
            }
            foreach ($sn in (Get-AwsTokens ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc" --query "Subnets[].SubnetId" --output text)) {
                $null = Invoke-AwsQuiet ec2 delete-subnet --subnet-id $sn
            }
            # Delete non-default SGs (retry — dependency order)
            for ($i = 0; $i -lt 8; $i++) {
                $sgs = Get-AwsTokens ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpc" --query "SecurityGroups[?GroupName!='default'].GroupId" --output text
                if ($sgs.Count -eq 0) { break }
                foreach ($sg in $sgs) {
                    $null = Invoke-AwsQuiet ec2 delete-security-group --group-id $sg
                }
                Start-Sleep -Seconds 5
            }
            $null = Invoke-AwsQuiet ec2 delete-vpc --vpc-id $vpc
        }

        Write-Host "[OK] day3 leftover wipe finished" -ForegroundColor Green
    }
    finally {
        $ErrorActionPreference = $prevEap
    }
}
