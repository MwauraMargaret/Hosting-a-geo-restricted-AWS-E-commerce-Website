#!/bin/bash
# Bootstrap nginx and publish the storefront from S3.
# The launch template in cloudformation.yaml sets SITE_BUCKET and AWS_REGION
# before these lines. Keep the two copies of this script aligned.
set -euo pipefail
exec > /var/log/user-data.log 2>&1

if [[ -z "${SITE_BUCKET:-}" || -z "${AWS_REGION:-}" ]]; then
  echo "SITE_BUCKET and AWS_REGION are required" >&2
  exit 1
fi

dnf install -y nginx
install -d -m 755 /usr/share/nginx/html

cat > /usr/share/nginx/html/index.html <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Meridian Market</title>
</head>
<body>
  <p>Meridian Market is publishing the storefront. Refresh shortly.</p>
</body>
</html>
EOF

cat > /usr/local/bin/pull-site.sh <<EOF
#!/bin/bash
set -euo pipefail
if aws s3api head-object --bucket "$SITE_BUCKET" --key index.html --region "$AWS_REGION" >/dev/null 2>&1; then
  aws s3 sync "s3://$SITE_BUCKET/" /usr/share/nginx/html/ --delete --region "$AWS_REGION"
  systemctl reload nginx || systemctl restart nginx
fi
EOF
chmod 755 /usr/local/bin/pull-site.sh

systemctl enable nginx
systemctl start nginx
/usr/local/bin/pull-site.sh || true
