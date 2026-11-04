param(
    [string]$StackName = "geo-restricted-store",
    [string]$Region = "us-east-1"
)

$ErrorActionPreference = "Stop"
$env:AWS_PAGER = ""

function Assert-LastExit {
    param([string]$Action)
    if ($LASTEXITCODE -ne 0) {
        throw "$Action failed with exit code $LASTEXITCODE."
    }
}

$bucket = aws cloudformation describe-stacks `
    --region $Region `
    --stack-name $StackName `
    --query "Stacks[0].Outputs[?OutputKey=='SiteBucketName'].OutputValue" `
    --output text
Assert-LastExit "Reading the site bucket name"

if ($bucket -and $bucket -ne "None") {
    aws s3 rm "s3://$bucket" --recursive --region $Region
    Assert-LastExit "Emptying the site bucket"
}

aws cloudformation delete-stack --region $Region --stack-name $StackName
Assert-LastExit "Deleting the stack"

Write-Host "Waiting for stack deletion. CloudFront often takes 15 minutes or more."
aws cloudformation wait stack-delete-complete --region $Region --stack-name $StackName
Assert-LastExit "Waiting for stack deletion"
Write-Host "Stack $StackName deleted."
