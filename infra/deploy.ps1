param(
    [Parameter(Mandatory = $true)]
    [string]$DomainName,
    [Parameter(Mandatory = $true)]
    [string]$HostedZoneId,
    [string]$StackName = "geo-restricted-store",
    [string]$Region = "us-east-1",
    [string]$InstanceType = "t3.micro"
)

$ErrorActionPreference = "Stop"
$env:AWS_PAGER = ""

function Assert-LastExit {
    param([string]$Action)
    if ($LASTEXITCODE -ne 0) {
        throw "$Action failed with exit code $LASTEXITCODE."
    }
}

if ($Region -ne "us-east-1") {
    throw "Deploy in us-east-1 so the CloudFront certificate is created in the required Region."
}

if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
    throw "Install the AWS CLI and configure credentials before deploying."
}

$prefixListId = aws ec2 describe-managed-prefix-lists `
    --region $Region `
    --filters "Name=prefix-list-name,Values=com.amazonaws.global.cloudfront.origin-facing" `
    --query "PrefixLists[0].PrefixListId" `
    --output text
Assert-LastExit "Lookup of the CloudFront prefix list"
if ([string]::IsNullOrWhiteSpace($prefixListId) -or $prefixListId -eq "None") {
    throw "Could not find com.amazonaws.global.cloudfront.origin-facing in $Region."
}

$secretPath = Join-Path $PSScriptRoot ".origin-secret"
if (Test-Path $secretPath) {
    $secret = (Get-Content -Raw $secretPath).Trim()
} else {
    $alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".ToCharArray()
    $secret = -join (1..32 | ForEach-Object { $alphabet | Get-Random })
    Set-Content -Path $secretPath -Value $secret -NoNewline
}

$template = Join-Path $PSScriptRoot "cloudformation.yaml"
aws cloudformation deploy `
    --region $Region `
    --stack-name $StackName `
    --template-file $template `
    --capabilities CAPABILITY_IAM `
    --no-fail-on-empty-changeset `
    --parameter-overrides `
        "DomainName=$DomainName" `
        "HostedZoneId=$HostedZoneId" `
        "CloudFrontPrefixListId=$prefixListId" `
        "OriginVerifySecret=$secret" `
        "InstanceType=$InstanceType"
Assert-LastExit "CloudFormation deploy"

$outputs = aws cloudformation describe-stacks `
    --region $Region `
    --stack-name $StackName `
    --query "Stacks[0].Outputs" `
    --output json | ConvertFrom-Json
Assert-LastExit "Reading stack outputs"

function Get-OutputValue {
    param([string]$Key)
    $match = $outputs | Where-Object { $_.OutputKey -eq $Key }
    if (-not $match) { throw "Stack output $Key is missing." }
    return $match.OutputValue
}

$bucket = Get-OutputValue "SiteBucketName"
$asgName = Get-OutputValue "AutoScalingGroupName"
$website = Join-Path (Split-Path $PSScriptRoot -Parent) "website"

aws s3 sync $website "s3://$bucket/" --delete --region $Region --cache-control "no-cache"
Assert-LastExit "Site upload"

$deadline = (Get-Date).AddMinutes(12)
$instanceIds = @()
do {
    $raw = aws autoscaling describe-auto-scaling-groups `
        --region $Region `
        --auto-scaling-group-names $asgName `
        --query "AutoScalingGroups[0].Instances[?LifecycleState=='InService'].InstanceId" `
        --output text
    Assert-LastExit "Reading Auto Scaling instances"
    $instanceIds = @($raw -split "\s+" | Where-Object { $_ -and $_ -ne "None" })
    if ($instanceIds.Count -ge 2) { break }
    Write-Host "Waiting for two in-service instances..."
    Start-Sleep -Seconds 15
} while ((Get-Date) -lt $deadline)

if ($instanceIds.Count -lt 2) {
    throw "Expected two in-service instances, found $($instanceIds.Count)."
}

$deadline = (Get-Date).AddMinutes(12)
do {
    $onlineRaw = aws ssm describe-instance-information `
        --region $Region `
        --filters "Key=InstanceIds,Values=$($instanceIds -join ',')" `
        --query "InstanceInformationList[?PingStatus=='Online'].InstanceId" `
        --output text
    Assert-LastExit "Checking SSM agent status"
    $online = @($onlineRaw -split "\s+" | Where-Object { $_ -and $_ -ne "None" })
    $ready = $true
    foreach ($id in $instanceIds) {
        if ($online -notcontains $id) { $ready = $false }
    }
    if ($ready) { break }
    Write-Host "Waiting for SSM on $($instanceIds -join ', ')..."
    Start-Sleep -Seconds 15
} while ((Get-Date) -lt $deadline)

if (-not $ready) {
    throw "Instances did not register with Systems Manager in time."
}

$paramFile = Join-Path $env:TEMP "meridian-ssm-params.json"
@{
    commands = @(
        "for i in `$(seq 1 60); do [ -x /usr/local/bin/pull-site.sh ] && break; sleep 10; done; test -x /usr/local/bin/pull-site.sh; /usr/local/bin/pull-site.sh"
    )
} | ConvertTo-Json | Set-Content -Path $paramFile -Encoding ascii

$paramUri = "file://" + ($paramFile -replace '\\', '/')
$commandId = aws ssm send-command `
    --region $Region `
    --instance-ids @instanceIds `
    --document-name AWS-RunShellScript `
    --comment "Publish Meridian Market" `
    --parameters $paramUri `
    --query "Command.CommandId" `
    --output text
Assert-LastExit "SSM publish command"
Remove-Item $paramFile -ErrorAction SilentlyContinue

foreach ($id in $instanceIds) {
    $status = "Pending"
    $invocationDeadline = (Get-Date).AddMinutes(15)
    do {
        Start-Sleep -Seconds 10
        $status = aws ssm get-command-invocation `
            --region $Region `
            --command-id $commandId `
            --instance-id $id `
            --query "Status" `
            --output text 2>$null
        if ($LASTEXITCODE -ne 0) { $status = "Pending" }
        Write-Host "$id : $status"
    } while ($status -in @("Pending", "InProgress", "Delayed") -and (Get-Date) -lt $invocationDeadline)

    if ($status -ne "Success") {
        aws ssm get-command-invocation --region $Region --command-id $commandId --instance-id $id
        throw "Publishing the site on $id finished with status $status."
    }
}

Write-Host ""
Write-Host "Storefront: $(Get-OutputValue 'WebsiteUrl')"
Write-Host "CloudFront: https://$(Get-OutputValue 'CloudFrontDomainName')"
Write-Host "Load balancer (expect a timeout): $(Get-OutputValue 'LoadBalancerDnsName')"
