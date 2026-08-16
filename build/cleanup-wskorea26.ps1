# Wipe day1/002 known AWS leftovers by name (state may be incomplete).
# Requires aws CLI on PATH and credentials from .env.
# Encoding: UTF-8 with BOM

function Invoke-AwsQuiet {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$AwsArgs)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $null = & aws @AwsArgs 2>$null
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    return $code
}

function Clear-Wskorea26Leftovers {
    param([string]$Region = "ap-northeast-2")

    if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
        Write-Host "[!] aws CLI not found - skip leftover wipe" -ForegroundColor Yellow
        return
    }

    Write-Host ""
    Write-Host ">>> Wiping AWS leftovers named wskorea26-* (may take several minutes)" -ForegroundColor Cyan
    $env:AWS_DEFAULT_REGION = $Region

    # ALB / TG
    $lbs = & aws elbv2 describe-load-balancers --query "LoadBalancers[?contains(LoadBalancerName, 'wskorea26')].LoadBalancerArn" --output text 2>$null
    foreach ($arn in @($lbs -split '\s+' | Where-Object { $_ })) {
        Write-Host "  delete ALB $arn"
        Invoke-AwsQuiet elbv2 delete-load-balancer --load-balancer-arn $arn | Out-Null
    }
    Start-Sleep -Seconds 15
    $tgs = & aws elbv2 describe-target-groups --query "TargetGroups[?contains(TargetGroupName, 'wskorea26')].TargetGroupArn" --output text 2>$null
    foreach ($arn in @($tgs -split '\s+' | Where-Object { $_ })) {
        Invoke-AwsQuiet elbv2 delete-target-group --target-group-arn $arn | Out-Null
    }

    # EKS
    $cluster = "wskorea26-cluster"
    $ngs = & aws eks list-nodegroups --cluster-name $cluster --query "nodegroups" --output text 2>$null
    foreach ($ng in @($ngs -split '\s+' | Where-Object { $_ })) {
        Write-Host "  delete nodegroup $ng"
        Invoke-AwsQuiet eks delete-nodegroup --cluster-name $cluster --nodegroup-name $ng | Out-Null
        Invoke-AwsQuiet eks wait nodegroup-deleted --cluster-name $cluster --nodegroup-name $ng | Out-Null
    }
    if ((& aws eks describe-cluster --name $cluster --query "cluster.name" --output text 2>$null)) {
        Write-Host "  delete EKS $cluster"
        Invoke-AwsQuiet eks delete-cluster --name $cluster | Out-Null
        Invoke-AwsQuiet eks wait cluster-deleted --name $cluster | Out-Null
    }

    # VPC by tag
    $vpc = & aws ec2 describe-vpcs --filters "Name=tag:Name,Values=wskorea26-vpc" --query "Vpcs[0].VpcId" --output text 2>$null
    if ($vpc -and $vpc -ne "None" -and $vpc -ne "null") {
        Write-Host "  cleanup VPC $vpc"
        $ids = & aws ec2 describe-instances --filters "Name=vpc-id,Values=$vpc" "Name=instance-state-name,Values=pending,running,stopping,stopped" --query "Reservations[].Instances[].InstanceId" --output text 2>$null
        if ($ids) {
            Invoke-AwsQuiet ec2 terminate-instances --instance-ids ($ids -split '\s+') | Out-Null
            Invoke-AwsQuiet ec2 wait instance-terminated --instance-ids ($ids -split '\s+') | Out-Null
        }
        $nats = & aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$vpc" "Name=state,Values=available,pending" --query "NatGateways[].NatGatewayId" --output text 2>$null
        foreach ($nat in @($nats -split '\s+' | Where-Object { $_ })) {
            Invoke-AwsQuiet ec2 delete-nat-gateway --nat-gateway-id $nat | Out-Null
        }
        for ($i = 0; $i -lt 40; $i++) {
            $left = & aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$vpc" "Name=state,Values=available,pending,deleting" --query "NatGateways[].NatGatewayId" --output text 2>$null
            if (-not $left) { break }
            Start-Sleep -Seconds 10
        }
        $eips = & aws ec2 describe-addresses --query "Addresses[?!AssociationId].AllocationId" --output text 2>$null
        foreach ($a in @($eips -split '\s+' | Where-Object { $_ })) {
            Invoke-AwsQuiet ec2 release-address --allocation-id $a | Out-Null
        }
        $eps = & aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$vpc" --query "VpcEndpoints[].VpcEndpointId" --output text 2>$null
        if ($eps) { Invoke-AwsQuiet ec2 delete-vpc-endpoints --vpc-endpoint-ids ($eps -split '\s+') | Out-Null }
        Start-Sleep -Seconds 5
        $enis = & aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$vpc" --query "NetworkInterfaces[].NetworkInterfaceId" --output text 2>$null
        foreach ($eni in @($enis -split '\s+' | Where-Object { $_ })) {
            Invoke-AwsQuiet ec2 delete-network-interface --network-interface-id $eni | Out-Null
        }
        $igws = & aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$vpc" --query "InternetGateways[].InternetGatewayId" --output text 2>$null
        foreach ($igw in @($igws -split '\s+' | Where-Object { $_ })) {
            Invoke-AwsQuiet ec2 detach-internet-gateway --internet-gateway-id $igw --vpc-id $vpc | Out-Null
            Invoke-AwsQuiet ec2 delete-internet-gateway --internet-gateway-id $igw | Out-Null
        }
        $sns = & aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc" --query "Subnets[].SubnetId" --output text 2>$null
        foreach ($sn in @($sns -split '\s+' | Where-Object { $_ })) {
            Invoke-AwsQuiet ec2 delete-subnet --subnet-id $sn | Out-Null
        }
        $rtbs = & aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$vpc" --query "RouteTables[?Associations[0].Main!=``true``].RouteTableId" --output text 2>$null
        foreach ($rtb in @($rtbs -split '\s+' | Where-Object { $_ })) {
            $assocs = & aws ec2 describe-route-tables --route-table-ids $rtb --query "RouteTables[0].Associations[?!Main].RouteTableAssociationId" --output text 2>$null
            foreach ($assoc in @($assocs -split '\s+' | Where-Object { $_ })) {
                Invoke-AwsQuiet ec2 disassociate-route-table --association-id $assoc | Out-Null
            }
            Invoke-AwsQuiet ec2 delete-route-table --route-table-id $rtb | Out-Null
        }
        $sgs = & aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpc" --query "SecurityGroups[?GroupName!=``default``].GroupId" --output text 2>$null
        foreach ($sg in @($sgs -split '\s+' | Where-Object { $_ })) {
            Invoke-AwsQuiet ec2 delete-security-group --group-id $sg | Out-Null
        }
        Invoke-AwsQuiet ec2 delete-vpc --vpc-id $vpc | Out-Null
    }

    Invoke-AwsQuiet lambda delete-function --function-name wskorea26-book-lambda | Out-Null
    Invoke-AwsQuiet dynamodb update-table --table-name wskorea26-data-table --no-deletion-protection-enabled | Out-Null
    Start-Sleep -Seconds 3
    Invoke-AwsQuiet dynamodb delete-table --table-name wskorea26-data-table | Out-Null
    Invoke-AwsQuiet ecr delete-repository --repository-name wskorea26-book-repo --force | Out-Null
    Invoke-AwsQuiet codebuild delete-project --name wskorea26-book | Out-Null

    $buckets = & aws s3api list-buckets --query "Buckets[?contains(Name, 'wskorea26')].Name" --output text 2>$null
    foreach ($b in @($buckets -split '\s+' | Where-Object { $_ })) {
        Write-Host "  delete bucket $b"
        Invoke-AwsQuiet s3 rm "s3://$b" --recursive | Out-Null
        Invoke-AwsQuiet s3api delete-bucket --bucket $b | Out-Null
    }

    $oac = & aws cloudfront list-origin-access-controls --query "OriginAccessControlList.Items[?Name=='wskorea26-s3-oac'].Id" --output text 2>$null
    if ($oac -and $oac -ne "None") {
        $etag = & aws cloudfront get-origin-access-control --id $oac --query ETag --output text 2>$null
        Invoke-AwsQuiet cloudfront delete-origin-access-control --id $oac --if-match $etag | Out-Null
    }
    $fn = & aws cloudfront list-functions --query "FunctionList.Items[?Name=='wskorea26-book-rewrite'].Name" --output text 2>$null
    if ($fn -and $fn -ne "None") {
        $etag = & aws cloudfront describe-function --name $fn --query ETag --output text 2>$null
        Invoke-AwsQuiet cloudfront delete-function --name $fn --if-match $etag | Out-Null
    }

    foreach ($role in @(
            "wskorea26-book-codebuild",
            "wskorea26-book-lambda-role",
            "wskorea26-eks-cluster-role",
            "wskorea26-eks-node-role"
        )) {
        $attached = & aws iam list-attached-role-policies --role-name $role --query "AttachedPolicies[].PolicyArn" --output text 2>$null
        foreach ($p in @($attached -split '\s+' | Where-Object { $_ })) {
            Invoke-AwsQuiet iam detach-role-policy --role-name $role --policy-arn $p | Out-Null
        }
        $inline = & aws iam list-role-policies --role-name $role --query "PolicyNames" --output text 2>$null
        foreach ($p in @($inline -split '\s+' | Where-Object { $_ })) {
            Invoke-AwsQuiet iam delete-role-policy --role-name $role --policy-name $p | Out-Null
        }
        $ips = & aws iam list-instance-profiles-for-role --role-name $role --query "InstanceProfiles[].InstanceProfileName" --output text 2>$null
        foreach ($ip in @($ips -split '\s+' | Where-Object { $_ })) {
            Invoke-AwsQuiet iam remove-role-from-instance-profile --instance-profile-name $ip --role-name $role | Out-Null
            Invoke-AwsQuiet iam delete-instance-profile --instance-profile-name $ip | Out-Null
        }
        Invoke-AwsQuiet iam delete-role --role-name $role | Out-Null
    }

    foreach ($alias in @(
            "alias/wskorea26-dynamodb-key",
            "alias/wskorea26-ecr-key",
            "alias/wskorea26-eks-key",
            "alias/wskorea26-s3-key"
        )) {
        $kid = & aws kms list-aliases --query "Aliases[?AliasName=='$alias'].TargetKeyId" --output text 2>$null
        if ($kid -and $kid -ne "None") {
            Invoke-AwsQuiet kms delete-alias --alias-name $alias | Out-Null
            Invoke-AwsQuiet kms schedule-key-deletion --key-id $kid --pending-window-in-days 7 | Out-Null
        }
    }

    Write-Host "[OK] wskorea26 leftover wipe finished" -ForegroundColor Green
}
