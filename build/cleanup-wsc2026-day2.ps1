# Wipe day2/002 AWS leftovers not in terraform state (partial apply / retry).
# Encoding: UTF-8 with BOM (Windows PowerShell 5.x)
# Covers AlreadyExists / VpcLimitExceeded from interrupted apply.

. (Join-Path $PSScriptRoot "cleanup-wskorea26.ps1")

function Remove-Wsc2026IamRole([string]$RoleName) {
    if (-not (Get-AwsText iam get-role --role-name $RoleName --query "Role.RoleName" --output text)) { return }
    Write-Host "  delete IAM role $RoleName"
    foreach ($p in (Get-AwsTokens iam list-attached-role-policies --role-name $RoleName --query "AttachedPolicies[].PolicyArn" --output text)) {
        $null = Invoke-AwsQuiet iam detach-role-policy --role-name $RoleName --policy-arn $p
    }
    foreach ($p in (Get-AwsTokens iam list-role-policies --role-name $RoleName --query "PolicyNames[]" --output text)) {
        $null = Invoke-AwsQuiet iam delete-role-policy --role-name $RoleName --policy-name $p
    }
    foreach ($ip in (Get-AwsTokens iam list-instance-profiles-for-role --role-name $RoleName --query "InstanceProfiles[].InstanceProfileName" --output text)) {
        $null = Invoke-AwsQuiet iam remove-role-from-instance-profile --instance-profile-name $ip --role-name $RoleName
        $null = Invoke-AwsQuiet iam delete-instance-profile --instance-profile-name $ip
    }
    $null = Invoke-AwsQuiet iam delete-role --role-name $RoleName
}

function Remove-Wsc2026NamedVpc {
    param([string]$Region, [string]$NameTag)

    foreach ($vpc in (Get-AwsTokens ec2 describe-vpcs --region $Region --filters "Name=tag:Name,Values=$NameTag" --query "Vpcs[].VpcId" --output text)) {
        Write-Host "  delete VPC $vpc ($Region / $NameTag)"
        foreach ($nat in (Get-AwsTokens ec2 describe-nat-gateways --region $Region --filter "Name=vpc-id,Values=$vpc" "Name=state,Values=available,pending" --query "NatGateways[].NatGatewayId" --output text)) {
            $null = Invoke-AwsQuiet ec2 delete-nat-gateway --region $Region --nat-gateway-id $nat
            for ($i = 0; $i -lt 24; $i++) {
                $st = Get-AwsText ec2 describe-nat-gateways --region $Region --nat-gateway-ids $nat --query "NatGateways[0].State" --output text
                if ($st -eq "deleted" -or -not $st) { break }
                Start-Sleep -Seconds 10
            }
        }
        foreach ($id in (Get-AwsTokens ec2 describe-instances --region $Region --filters "Name=vpc-id,Values=$vpc" "Name=instance-state-name,Values=pending,running,stopping,stopped" --query "Reservations[].Instances[].InstanceId" --output text)) {
            $null = Invoke-AwsQuiet ec2 terminate-instances --region $Region --instance-ids $id
            $null = Invoke-AwsQuiet ec2 wait instance-terminated --region $Region --instance-ids $id
        }
        foreach ($alb in (Get-AwsTokens elbv2 describe-load-balancers --region $Region --query "LoadBalancers[?VpcId=='$vpc'].LoadBalancerArn" --output text)) {
            $null = Invoke-AwsQuiet elbv2 delete-load-balancer --region $Region --load-balancer-arn $alb
        }
        Start-Sleep -Seconds 10
        for ($i = 0; $i -lt 12; $i++) {
            foreach ($eni in (Get-AwsTokens ec2 describe-network-interfaces --region $Region --filters "Name=vpc-id,Values=$vpc" "Name=status,Values=available" --query "NetworkInterfaces[].NetworkInterfaceId" --output text)) {
                $null = Invoke-AwsQuiet ec2 delete-network-interface --region $Region --network-interface-id $eni
            }
            $left = Get-AwsText ec2 describe-network-interfaces --region $Region --filters "Name=vpc-id,Values=$vpc" --query "length(NetworkInterfaces)" --output text
            if (-not $left -or $left -eq "0") { break }
            Start-Sleep -Seconds 15
        }
        foreach ($sn in (Get-AwsTokens ec2 describe-subnets --region $Region --filters "Name=vpc-id,Values=$vpc" --query "Subnets[].SubnetId" --output text)) {
            $null = Invoke-AwsQuiet ec2 delete-subnet --region $Region --subnet-id $sn
        }
        foreach ($igw in (Get-AwsTokens ec2 describe-internet-gateways --region $Region --filters "Name=attachment.vpc-id,Values=$vpc" --query "InternetGateways[].InternetGatewayId" --output text)) {
            $null = Invoke-AwsQuiet ec2 detach-internet-gateway --region $Region --internet-gateway-id $igw --vpc-id $vpc
            $null = Invoke-AwsQuiet ec2 delete-internet-gateway --region $Region --internet-gateway-id $igw
        }
        foreach ($sg in (Get-AwsTokens ec2 describe-security-groups --region $Region --filters "Name=vpc-id,Values=$vpc" --query "SecurityGroups[?GroupName!='default'].GroupId" --output text)) {
            $null = Invoke-AwsQuiet ec2 delete-security-group --region $Region --group-id $sg
        }
        foreach ($rtb in (Get-AwsTokens ec2 describe-route-tables --region $Region --filters "Name=vpc-id,Values=$vpc" --query "RouteTables[?!(Associations[?Main])].RouteTableId" --output text)) {
            $null = Invoke-AwsQuiet ec2 delete-route-table --region $Region --route-table-id $rtb
        }
        $null = Invoke-AwsQuiet ec2 delete-vpc --region $Region --vpc-id $vpc
    }
}

function Remove-Wsc2026Day2OrphanAws {
    param([string]$AssignPath = "")

    if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
        Write-Host "[!] aws CLI not found - skip day2/002 orphan cleanup" -ForegroundColor Yellow
        return
    }

    $inState = {
        param($addr)
        if (-not $AssignPath) { return $false }
        $root = Split-Path -Parent $PSScriptRoot
        $tf = Join-Path $root "terraform.cmd"
        if (-not (Test-Path -LiteralPath $tf)) { return $false }
        $prev = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        $list = @(& $tf "-chdir=$AssignPath" "state" "list" 2>$null)
        $ErrorActionPreference = $prev
        return ($list | ForEach-Object { "$_".Trim() }) -contains $addr
    }

    Write-Host ">>> day2/002 orphan cleanup (state 외 동명 AWS 리소스 / VPC 한도)" -ForegroundColor Cyan

    # Participant suffix for S3 (from tfvars if present)
    $pidSuffix = ""
    if ($AssignPath) {
        $tfvars = Join-Path $AssignPath "terraform.tfvars"
        if (Test-Path -LiteralPath $tfvars) {
            $m = [regex]::Match((Get-Content -LiteralPath $tfvars -Raw), 'participant_id\s*=\s*"([^"]+)"')
            if ($m.Success) { $pidSuffix = $m.Groups[1].Value }
        }
    }
    if (-not $pidSuffix -and $env:PARTICIPANT_ID) { $pidSuffix = $env:PARTICIPANT_ID }
    if (-not $pidSuffix -and $env:TF_VAR_participant_id) { $pidSuffix = $env:TF_VAR_participant_id }

    # --- MSK ---
    if (-not (& $inState "module.msk.aws_msk_cluster.this")) {
        $clusterArn = Get-AwsText kafka list-clusters --region ap-northeast-1 `
            --cluster-name-filter wsc2026-msk-cluster `
            --query "ClusterInfoList[0].ClusterArn" --output text
        if ($clusterArn) {
            Write-Host "  delete orphan MSK cluster $clusterArn"
            $null = Invoke-AwsQuiet kafka delete-cluster --region ap-northeast-1 --cluster-arn $clusterArn
        }
    }

    # --- Lambda / Step Functions / SNS (named) ---
    foreach ($fn in @(
            "wsc2026-sensor-consumer", "wsc2026-sensor-alert-consumer",
            "wsc2026-student-score-function", "wsc2026-student-score-trigger"
        )) {
        $region = if ($fn -like "wsc2026-student*") { "ap-southeast-1" } else { "ap-northeast-1" }
        if (Get-AwsText lambda get-function --region $region --function-name $fn --query "Configuration.FunctionName" --output text) {
            Write-Host "  delete Lambda $fn"
            $null = Invoke-AwsQuiet lambda delete-function --region $region --function-name $fn
        }
    }
    $sm = Get-AwsText stepfunctions list-state-machines --region ap-southeast-1 `
        --query "stateMachines[?name=='wsc2026-student-score-workflow'].stateMachineArn | [0]" --output text
    if ($sm) {
        Write-Host "  delete Step Functions $sm"
        $null = Invoke-AwsQuiet stepfunctions delete-state-machine --region ap-southeast-1 --state-machine-arn $sm
    }
    $topic = Get-AwsText sns list-topics --region ap-northeast-1 `
        --query "Topics[?contains(TopicArn,'wsc2026-sensor-alert')].TopicArn | [0]" --output text
    if ($topic) { $null = Invoke-AwsQuiet sns delete-topic --region ap-northeast-1 --topic-arn $topic }

    # --- Analytics ALB / TG / Kinesis ---
    if (-not (& $inState "module.analytics.aws_lb.analytics")) {
        foreach ($alb in (Get-AwsTokens elbv2 describe-load-balancers --region ap-northeast-2 `
                    --query "LoadBalancers[?LoadBalancerName=='wsc2026-analytics-alb'].LoadBalancerArn" --output text)) {
            Write-Host "  delete ALB $alb"
            $null = Invoke-AwsQuiet elbv2 delete-load-balancer --region ap-northeast-2 --load-balancer-arn $alb
        }
        Start-Sleep -Seconds 15
    }
    if (-not (& $inState "module.analytics.aws_lb_target_group.analytics")) {
        foreach ($tg in (Get-AwsTokens elbv2 describe-target-groups --region ap-northeast-2 `
                    --query "TargetGroups[?TargetGroupName=='wsc2026-analytics-tg'].TargetGroupArn" --output text)) {
            Write-Host "  delete TG $tg"
            $null = Invoke-AwsQuiet elbv2 delete-target-group --region ap-northeast-2 --target-group-arn $tg
        }
    }
    if (-not (& $inState "module.analytics.aws_kinesis_stream.orders")) {
        if (Get-AwsText kinesis describe-stream-summary --region ap-northeast-2 --stream-name wsc2026-order-stream --query "StreamDescriptionSummary.StreamName" --output text) {
            Write-Host "  delete Kinesis wsc2026-order-stream"
            $null = Invoke-AwsQuiet kinesis delete-stream --region ap-northeast-2 --stream-name wsc2026-order-stream --enforce-consumer-deletion
        }
    }

    # --- DynamoDB ---
    if (-not (& $inState "module.msk.aws_dynamodb_table.sensor_data")) {
        if (Get-AwsText dynamodb describe-table --region ap-northeast-1 --table-name wsc2026-sensor-data --query "Table.TableName" --output text) {
            Write-Host "  delete DynamoDB wsc2026-sensor-data"
            $null = Invoke-AwsQuiet dynamodb delete-table --region ap-northeast-1 --table-name wsc2026-sensor-data
        }
    }
    if (-not (& $inState "module.workflow.aws_dynamodb_table.student_score")) {
        if (Get-AwsText dynamodb describe-table --region ap-southeast-1 --table-name wsc2026-student-score --query "Table.TableName" --output text) {
            Write-Host "  delete DynamoDB wsc2026-student-score"
            $null = Invoke-AwsQuiet dynamodb delete-table --region ap-southeast-1 --table-name wsc2026-student-score
        }
    }

    # --- S3 ---
    $buckets = @(
        "wsc2026-event-config-305291767588",
        "wsc2026-event-trail-305291767588"
    )
    if ($pidSuffix) {
        $buckets += "wsc2026-sensor-alert-bucket-$pidSuffix"
        $buckets += "wsc2026-student-score-bucket-$pidSuffix"
    }
    foreach ($b in $buckets) {
        $exists = Get-AwsText s3api head-bucket --bucket $b --query "BucketRegion" --output text
        # head-bucket returns empty on success with some CLI versions; also try list
        $listed = Get-AwsText s3api list-buckets --query "Buckets[?Name=='$b'].Name | [0]" --output text
        if ($listed -eq $b) {
            Write-Host "  empty+delete S3 $b"
            $null = Invoke-AwsQuiet s3 rb "s3://$b" --force
        }
    }

    # --- CloudTrail / Config (event module) ---
    if (Get-AwsText cloudtrail describe-trails --query "trailList[?Name=='wsc2026-event-trail'].Name | [0]" --output text) {
        Write-Host "  delete CloudTrail wsc2026-event-trail"
        $null = Invoke-AwsQuiet cloudtrail delete-trail --name wsc2026-event-trail --region eu-west-1
    }
    $null = Invoke-AwsQuiet configservice stop-configuration-recorder --region eu-west-1 --configuration-recorder-name wsc2026-event-recorder
    $null = Invoke-AwsQuiet configservice delete-delivery-channel --region eu-west-1 --delivery-channel-name wsc2026-event-delivery-channel
    $null = Invoke-AwsQuiet configservice delete-configuration-recorder --region eu-west-1 --configuration-recorder-name wsc2026-event-recorder

    # --- IAM roles (fixed names) ---
    foreach ($role in @(
            "wsc2026-alaytics-ec2-role", "wsc2026-analytics-flink-role",
            "wsc2026-event-ec2-role", "wsc2026-event-lambda-role", "wsc2026-event-config-role",
            "wsc2026-msk-ec2-role", "wsc2026-msk-lambda-role",
            "wsc2026-lambda-student-role", "wsc2026-stepfunction-student-role"
        )) {
        Remove-Wsc2026IamRole $role
    }

    # --- EC2 named ---
    foreach ($id in (Get-AwsTokens ec2 describe-instances --region ap-northeast-2 `
                --filters "Name=tag:Name,Values=wsc2026-analytics-ec2" "Name=instance-state-name,Values=pending,running,stopping,stopped" `
                --query "Reservations[].Instances[].InstanceId" --output text)) {
        Write-Host "  terminate $id"
        $null = Invoke-AwsQuiet ec2 terminate-instances --region ap-northeast-2 --instance-ids $id
    }

    # Wait MSK gone before config + VPC
    for ($i = 0; $i -lt 40; $i++) {
        $left = Get-AwsText kafka list-clusters --region ap-northeast-1 --cluster-name-filter wsc2026-msk-cluster --query "length(ClusterInfoList)" --output text
        if (-not $left -or $left -eq "0") { break }
        Start-Sleep -Seconds 15
    }
    if (-not (& $inState "module.msk.aws_msk_configuration.cluster")) {
        $cfgArn = Get-AwsText kafka list-configurations --region ap-northeast-1 `
            --query "Configurations[?Name=='wsc2026-msk-configuration'].Arn | [0]" --output text
        if ($cfgArn) {
            Write-Host "  delete orphan MSK configuration $cfgArn"
            $null = Invoke-AwsQuiet kafka delete-configuration --region ap-northeast-1 --arn $cfgArn
        }
    }

    # --- Orphan VPCs (VpcLimitExceeded) — only when not in state ---
    if (-not (& $inState "module.msk.aws_vpc.msk")) {
        Remove-Wsc2026NamedVpc -Region "ap-northeast-1" -NameTag "msk-vpc"
    }
    if (-not (& $inState "module.analytics.aws_vpc.analytics")) {
        Remove-Wsc2026NamedVpc -Region "ap-northeast-2" -NameTag "analytics-vpc"
    }
    if (-not (& $inState "module.event.aws_vpc.event")) {
        Remove-Wsc2026NamedVpc -Region "eu-west-1" -NameTag "event-vpc"
    }

    # Unassociated EIPs (free quota for NAT)
    foreach ($region in @("ap-northeast-1", "ap-northeast-2", "eu-west-1")) {
        foreach ($alloc in (Get-AwsTokens ec2 describe-addresses --region $region --query "Addresses[?AssociationId==null].AllocationId" --output text)) {
            Write-Host "  release free EIP $alloc ($region)"
            $null = Invoke-AwsQuiet ec2 release-address --region $region --allocation-id $alloc
        }
    }

    Write-Host "[OK] day2/002 orphan cleanup done" -ForegroundColor Green
}

function Ensure-Day2002Tfvars {
    param([string]$AssignPath)

    $tfvars = Join-Path $AssignPath "terraform.tfvars"
    $bad = $false
    if (-not (Test-Path -LiteralPath $tfvars)) {
        $bad = $true
    }
    else {
        $raw = Get-Content -LiteralPath $tfvars -Raw -ErrorAction SilentlyContinue
        if (-not $raw -or $raw -match 'participant_id\s*=\s*"001"') {
            $bad = $true
        }
    }

    if (-not $bad) { return }

    # Prefer PARTICIPANT_ID / TF_VAR_participant_id from .env (cross-machine, no prompt).
    $fromEnv = $env:PARTICIPANT_ID
    if (-not $fromEnv) { $fromEnv = $env:TF_VAR_participant_id }
    if ($fromEnv -and $fromEnv -ne "001" -and $fromEnv -match '^[0-9A-Za-z-]{1,20}$') {
        @(
            "# Auto-created from .env PARTICIPANT_ID"
            "participant_id = `"$fromEnv`""
        ) | Set-Content -LiteralPath $tfvars -Encoding UTF8
        Write-Host "[OK] Wrote $tfvars from .env PARTICIPANT_ID=$fromEnv" -ForegroundColor Green
        return
    }

    Write-Host ""
    Write-Host "day2/002 needs participant_id (S3 suffix)." -ForegroundColor Yellow
    Write-Host "Set PARTICIPANT_ID in .env, or create terraform.tfvars (see terraform.tfvars.example)." -ForegroundColor Yellow
    Write-Host "Do NOT use 001 — S3 bucket names are globally unique and 001 is taken." -ForegroundColor Yellow
    while ($true) {
        $num = Read-Host "participant_id (your contest number)"
        if ($num -eq "001") {
            Write-Host "[!] 001 causes BucketAlreadyExists — use your assigned number" -ForegroundColor Yellow
            continue
        }
        if ($num -match '^[0-9A-Za-z-]{1,20}$') {
            @(
                "# Auto-created by start.cmd — change to your contest number if wrong"
                "participant_id = `"$num`""
            ) | Set-Content -LiteralPath $tfvars -Encoding UTF8
            Write-Host "[OK] Wrote $tfvars" -ForegroundColor Green
            return
        }
        Write-Host "[!] Invalid format (1-20 chars: letters, digits, hyphen)" -ForegroundColor Yellow
    }
}
