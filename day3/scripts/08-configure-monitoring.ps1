param(
    [string]$Email = ""
)
. (Join-Path $PSScriptRoot "lib.ps1")
foreach ($cmd in @("aws", "kubectl")) { Require-Command $cmd }
Ensure-CoreState
Ensure-Kubeconfig

$region = Get-AwsRegion
$snsArn = Get-TfOutputRaw "sns_alert_topic_arn"
$rdsId = Get-TfOutputRaw "rds_identifier"
$project = Get-ProjectName
$albDns = ((& kubectl -n app get ingress application -o 'jsonpath={.status.loadBalancer.ingress[0].hostname}') | Out-String).Trim()
Assert-NativeSuccess "kubectl get ingress"

$lbArn = ((& aws elbv2 describe-load-balancers --region $region --query "LoadBalancers[?DNSName=='$albDns'].LoadBalancerArn | [0]" --output text) | Out-String).Trim()
Assert-NativeSuccess "aws elbv2 describe-load-balancers"
if (-not $lbArn -or $lbArn -eq 'None') { Fail "Unable to find ALB ARN for $albDns" }
$lbDim = ($lbArn -split ':loadbalancer/',2)[1]

if ($Email) {
    Write-Step "Subscribe email to SNS"
    Invoke-Aws sns subscribe --region $region --topic-arn $snsArn --protocol email --notification-endpoint $Email | Out-Null
    Write-Host "Confirm the subscription from the email message."
}

Write-Step "Create ALB-level alarms"
Invoke-Aws cloudwatch put-metric-alarm --region $region `
    --alarm-name "$project-alb-elb-5xx" --namespace AWS/ApplicationELB --metric-name HTTPCode_ELB_5XX_Count `
    --dimensions "Name=LoadBalancer,Value=$lbDim" --statistic Sum --period 60 --evaluation-periods 2 --datapoints-to-alarm 1 `
    --threshold 1 --comparison-operator GreaterThanOrEqualToThreshold --treat-missing-data notBreaching --alarm-actions $snsArn

Invoke-Aws cloudwatch put-metric-alarm --region $region `
    --alarm-name "$project-alb-target-5xx" --namespace AWS/ApplicationELB --metric-name HTTPCode_Target_5XX_Count `
    --dimensions "Name=LoadBalancer,Value=$lbDim" --statistic Sum --period 60 --evaluation-periods 2 --datapoints-to-alarm 1 `
    --threshold 5 --comparison-operator GreaterThanOrEqualToThreshold --treat-missing-data notBreaching --alarm-actions $snsArn

$tgText = ((& aws elbv2 describe-target-groups --region $region --load-balancer-arn $lbArn --query 'TargetGroups[].TargetGroupArn' --output text) | Out-String).Trim()
Assert-NativeSuccess "aws elbv2 describe-target-groups"
$tgArns = @($tgText -split '\s+' | Where-Object { $_ })

foreach ($tgArn in $tgArns) {
    $tgName = ((& aws elbv2 describe-target-groups --region $region --target-group-arns $tgArn --query 'TargetGroups[0].TargetGroupName' --output text) | Out-String).Trim()
    Assert-NativeSuccess "aws elbv2 describe-target-groups"
    $tgDim = ($tgArn -split ':targetgroup/',2)[1]
    $resourceTag = ((& aws elbv2 describe-tags --region $region --resource-arns $tgArn --query "TagDescriptions[0].Tags[?Key=='service.k8s.aws/resource'].Value | [0]" --output text 2>$null) | Out-String).Trim()
    $matchText = "$tgName $resourceTag"
    $threshold = '1.0'
    $service = if ($tgName.Length -gt 20) { $tgName.Substring(0,20) } else { $tgName }
    if ($matchText -match 'user') { $service='user'; $threshold='0.2' }
    elseif ($matchText -match 'product') { $service='product'; $threshold='0.2' }
    elseif ($matchText -match 'stress') { $service='stress'; $threshold='1.0' }

    Invoke-Aws cloudwatch put-metric-alarm --region $region `
        --alarm-name "$project-$service-response-time" --namespace AWS/ApplicationELB --metric-name TargetResponseTime `
        --dimensions "Name=LoadBalancer,Value=$lbDim" "Name=TargetGroup,Value=$tgDim" --statistic Average --period 60 `
        --evaluation-periods 3 --datapoints-to-alarm 2 --threshold $threshold --comparison-operator GreaterThanThreshold `
        --treat-missing-data notBreaching --alarm-actions $snsArn

    Invoke-Aws cloudwatch put-metric-alarm --region $region `
        --alarm-name "$project-$service-unhealthy-target" --namespace AWS/ApplicationELB --metric-name UnHealthyHostCount `
        --dimensions "Name=LoadBalancer,Value=$lbDim" "Name=TargetGroup,Value=$tgDim" --statistic Maximum --period 60 `
        --evaluation-periods 2 --datapoints-to-alarm 1 --threshold 1 --comparison-operator GreaterThanOrEqualToThreshold `
        --treat-missing-data notBreaching --alarm-actions $snsArn
}

Write-Step "Create CloudWatch dashboard"
$dashboard = @"
{
  "widgets": [
    {
      "type":"metric","x":0,"y":0,"width":12,"height":6,
      "properties":{"title":"ALB traffic and errors","region":"$region","view":"timeSeries","period":60,
      "metrics":[["AWS/ApplicationELB","RequestCount","LoadBalancer","$lbDim",{"stat":"Sum"}],
                 [".","HTTPCode_Target_5XX_Count",".",".",{"stat":"Sum"}],
                 [".","HTTPCode_ELB_5XX_Count",".",".",{"stat":"Sum"}]]}
    },
    {
      "type":"metric","x":12,"y":0,"width":12,"height":6,
      "properties":{"title":"ALB response time","region":"$region","view":"timeSeries","period":60,
      "metrics":[["AWS/ApplicationELB","TargetResponseTime","LoadBalancer","$lbDim",{"stat":"Average"}]]}
    },
    {
      "type":"metric","x":0,"y":6,"width":12,"height":6,
      "properties":{"title":"RDS CPU and connections","region":"$region","view":"timeSeries","period":60,
      "metrics":[["AWS/RDS","CPUUtilization","DBInstanceIdentifier","$rdsId",{"stat":"Average"}],
                 [".","DatabaseConnections",".",".",{"stat":"Average","yAxis":"right"}]]}
    }
  ]
}
"@
$tempDashboard = Join-Path ([IO.Path]::GetTempPath()) ("dashboard-{0}.json" -f [guid]::NewGuid())
try {
    [IO.File]::WriteAllText($tempDashboard, $dashboard, [Text.UTF8Encoding]::new($false))
    $fileUri = 'file://' + ($tempDashboard -replace '\\','/')
    Invoke-Aws cloudwatch put-dashboard --region $region --dashboard-name "$project-operation" --dashboard-body $fileUri | Out-Null
}
finally { Remove-Item $tempDashboard -Force -ErrorAction SilentlyContinue }
Write-Host "Monitoring configured. SNS: $snsArn"
