# Wipe day1/002 known AWS leftovers by name (state may be incomplete).
# Requires aws CLI on PATH and credentials from .env.
# Encoding: UTF-8 with BOM (Windows PowerShell 5.x)
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

function Clear-Wskorea26Leftovers {
    param([string]$Region = "ap-northeast-2")

    if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
        Write-Host "[!] aws CLI not found - skip leftover wipe" -ForegroundColor Yellow
        return
    }

    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    try {
        Write-Host ""
        Write-Host ">>> Wiping AWS leftovers named wskorea26-* (may take several minutes)" -ForegroundColor Cyan
        $env:AWS_DEFAULT_REGION = $Region

        foreach ($arn in (Get-AwsTokens elbv2 describe-load-balancers --query "LoadBalancers[?contains(LoadBalancerName, 'wskorea26')].LoadBalancerArn" --output text)) {
            Write-Host "  delete ALB $arn"
            $null = Invoke-AwsQuiet elbv2 delete-load-balancer --load-balancer-arn $arn
        }
        Start-Sleep -Seconds 15
        foreach ($arn in (Get-AwsTokens elbv2 describe-target-groups --query "TargetGroups[?contains(TargetGroupName, 'wskorea26')].TargetGroupArn" --output text)) {
            $null = Invoke-AwsQuiet elbv2 delete-target-group --target-group-arn $arn
        }

        $cluster = "wskorea26-cluster"
        $exists = Get-AwsText eks describe-cluster --name $cluster --query "cluster.name" --output text
        if ($exists) {
            foreach ($ng in (Get-AwsTokens eks list-nodegroups --cluster-name $cluster --query "nodegroups" --output text)) {
                Write-Host "  delete nodegroup $ng"
                $null = Invoke-AwsQuiet eks delete-nodegroup --cluster-name $cluster --nodegroup-name $ng
                $null = Invoke-AwsQuiet eks wait nodegroup-deleted --cluster-name $cluster --nodegroup-name $ng
            }
            Write-Host "  delete EKS $cluster"
            $null = Invoke-AwsQuiet eks delete-cluster --name $cluster
            $null = Invoke-AwsQuiet eks wait cluster-deleted --name $cluster
        }
        else {
            Write-Host "  EKS $cluster not found - skip"
        }

        $vpc = Get-AwsText ec2 describe-vpcs --filters "Name=tag:Name,Values=wskorea26-vpc" --query "Vpcs[0].VpcId" --output text
        if ($vpc) {
            Write-Host "  cleanup VPC $vpc"
            $ids = Get-AwsTokens ec2 describe-instances --filters "Name=vpc-id,Values=$vpc" "Name=instance-state-name,Values=pending,running,stopping,stopped" --query "Reservations[].Instances[].InstanceId" --output text
            if ($ids.Count -gt 0) {
                $null = Invoke-AwsQuiet ec2 terminate-instances --instance-ids $ids
                $null = Invoke-AwsQuiet ec2 wait instance-terminated --instance-ids $ids
            }
            foreach ($nat in (Get-AwsTokens ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$vpc" "Name=state,Values=available,pending" --query "NatGateways[].NatGatewayId" --output text)) {
                $null = Invoke-AwsQuiet ec2 delete-nat-gateway --nat-gateway-id $nat
            }
            for ($i = 0; $i -lt 40; $i++) {
                $left = Get-AwsTokens ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$vpc" "Name=state,Values=available,pending,deleting" --query "NatGateways[].NatGatewayId" --output text
                if ($left.Count -eq 0) { break }
                Start-Sleep -Seconds 10
            }
            foreach ($a in (Get-AwsTokens ec2 describe-addresses --query "Addresses[?!AssociationId].AllocationId" --output text)) {
                $null = Invoke-AwsQuiet ec2 release-address --allocation-id $a
            }
            $eps = Get-AwsTokens ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$vpc" --query "VpcEndpoints[].VpcEndpointId" --output text
            if ($eps.Count -gt 0) {
                $null = Invoke-AwsQuiet ec2 delete-vpc-endpoints --vpc-endpoint-ids $eps
            }
            Start-Sleep -Seconds 5
            foreach ($eni in (Get-AwsTokens ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$vpc" --query "NetworkInterfaces[].NetworkInterfaceId" --output text)) {
                $null = Invoke-AwsQuiet ec2 delete-network-interface --network-interface-id $eni
            }
            foreach ($igw in (Get-AwsTokens ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$vpc" --query "InternetGateways[].InternetGatewayId" --output text)) {
                $null = Invoke-AwsQuiet ec2 detach-internet-gateway --internet-gateway-id $igw --vpc-id $vpc
                $null = Invoke-AwsQuiet ec2 delete-internet-gateway --internet-gateway-id $igw
            }
            foreach ($sn in (Get-AwsTokens ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc" --query "Subnets[].SubnetId" --output text)) {
                $null = Invoke-AwsQuiet ec2 delete-subnet --subnet-id $sn
            }
            foreach ($rtb in (Get-AwsTokens ec2 describe-route-tables --filters "Name=vpc-id,Values=$vpc" --query "RouteTables[?Associations[0].Main!=``true``].RouteTableId" --output text)) {
                foreach ($assoc in (Get-AwsTokens ec2 describe-route-tables --route-table-ids $rtb --query "RouteTables[0].Associations[?!Main].RouteTableAssociationId" --output text)) {
                    $null = Invoke-AwsQuiet ec2 disassociate-route-table --association-id $assoc
                }
                $null = Invoke-AwsQuiet ec2 delete-route-table --route-table-id $rtb
            }
            foreach ($sg in (Get-AwsTokens ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpc" --query "SecurityGroups[?GroupName!=``default``].GroupId" --output text)) {
                $null = Invoke-AwsQuiet ec2 delete-security-group --group-id $sg
            }
            $null = Invoke-AwsQuiet ec2 delete-vpc --vpc-id $vpc
        }
        else {
            Write-Host "  VPC wskorea26-vpc not found - skip"
        }

        $null = Invoke-AwsQuiet lambda delete-function --function-name wskorea26-book-lambda
        $null = Invoke-AwsQuiet dynamodb update-table --table-name wskorea26-data-table --no-deletion-protection-enabled
        Start-Sleep -Seconds 3
        $null = Invoke-AwsQuiet dynamodb delete-table --table-name wskorea26-data-table
        $null = Invoke-AwsQuiet ecr delete-repository --repository-name wskorea26-book-repo --force
        $null = Invoke-AwsQuiet codebuild delete-project --name wskorea26-book

        foreach ($b in (Get-AwsTokens s3api list-buckets --query "Buckets[?contains(Name, 'wskorea26')].Name" --output text)) {
            Write-Host "  delete bucket $b"
            $null = Invoke-AwsQuiet s3 rm "s3://$b" --recursive
            $null = Invoke-AwsQuiet s3api delete-bucket --bucket $b
        }

        $oac = Get-AwsText cloudfront list-origin-access-controls --query "OriginAccessControlList.Items[?Name=='wskorea26-s3-oac'].Id" --output text
        if ($oac) {
            $etag = Get-AwsText cloudfront get-origin-access-control --id $oac --query ETag --output text
            $null = Invoke-AwsQuiet cloudfront delete-origin-access-control --id $oac --if-match $etag
        }
        $fn = Get-AwsText cloudfront list-functions --query "FunctionList.Items[?Name=='wskorea26-book-rewrite'].Name" --output text
        if ($fn) {
            $etag = Get-AwsText cloudfront describe-function --name $fn --query ETag --output text
            $null = Invoke-AwsQuiet cloudfront delete-function --name $fn --if-match $etag
        }

        foreach ($role in @(
                "wskorea26-book-codebuild",
                "wskorea26-book-lambda-role",
                "wskorea26-eks-cluster-role",
                "wskorea26-eks-node-role"
            )) {
            foreach ($p in (Get-AwsTokens iam list-attached-role-policies --role-name $role --query "AttachedPolicies[].PolicyArn" --output text)) {
                $null = Invoke-AwsQuiet iam detach-role-policy --role-name $role --policy-arn $p
            }
            foreach ($p in (Get-AwsTokens iam list-role-policies --role-name $role --query "PolicyNames" --output text)) {
                $null = Invoke-AwsQuiet iam delete-role-policy --role-name $role --policy-name $p
            }
            foreach ($ip in (Get-AwsTokens iam list-instance-profiles-for-role --role-name $role --query "InstanceProfiles[].InstanceProfileName" --output text)) {
                $null = Invoke-AwsQuiet iam remove-role-from-instance-profile --instance-profile-name $ip --role-name $role
                $null = Invoke-AwsQuiet iam delete-instance-profile --instance-profile-name $ip
            }
            $null = Invoke-AwsQuiet iam delete-role --role-name $role
        }

        foreach ($alias in @(
                "alias/wskorea26-dynamodb-key",
                "alias/wskorea26-ecr-key",
                "alias/wskorea26-eks-key",
                "alias/wskorea26-s3-key"
            )) {
            $kid = Get-AwsText kms list-aliases --query "Aliases[?AliasName=='$alias'].TargetKeyId" --output text
            if ($kid) {
                $null = Invoke-AwsQuiet kms delete-alias --alias-name $alias
                $null = Invoke-AwsQuiet kms schedule-key-deletion --key-id $kid --pending-window-in-days 7
            }
        }

        Write-Host "[OK] wskorea26 leftover wipe finished" -ForegroundColor Green
    }
    catch {
        Write-Host ("[!] leftover wipe hit an error but will continue: {0}" -f $_) -ForegroundColor Yellow
    }
    finally {
        $ErrorActionPreference = $prevEap
    }
}
