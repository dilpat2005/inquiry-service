#!/usr/bin/env bash
# Deploys the whole stack: infrastructure (CloudFormation), Lambda code, and the website.
# Usage: scripts/deploy.sh owner@example.com sender@yourdomain.com
#   owner  = where notifications are delivered
#   sender = From address; its domain must be a verified SES identity with DKIM
set -euo pipefail

OWNER_EMAIL="${1:?Usage: scripts/deploy.sh owner@example.com sender@yourdomain.com}"
SENDER_EMAIL="${2:?Usage: scripts/deploy.sh owner@example.com sender@yourdomain.com}"
SENDER_DOMAIN="${SENDER_EMAIL#*@}"
STACK="${STACK:-inquiry-service}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-west-2}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "== Checking SES identity for ${SENDER_DOMAIN} in ${AWS_DEFAULT_REGION}"
VERIFIED="$(aws sesv2 get-email-identity --email-identity "$SENDER_DOMAIN" \
  --query VerifiedForSendingStatus --output text 2>/dev/null || echo missing)"
if [ "$VERIFIED" != "True" ]; then
  echo "${SENDER_DOMAIN} is not a verified SES identity in ${AWS_DEFAULT_REGION} (status: ${VERIFIED})."
  echo "Create it with: aws sesv2 create-email-identity --email-identity ${SENDER_DOMAIN}"
  echo "then publish the 3 DKIM CNAME records it returns, wait for DKIM SUCCESS, and rerun."
  exit 1
fi
echo "Note: while SES is in sandbox mode, ${OWNER_EMAIL} must be a verified address or on a verified domain."

echo "== Deploying CloudFormation stack ${STACK}"
aws cloudformation deploy \
  --template-file "$ROOT/template.yaml" \
  --stack-name "$STACK" \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides "OwnerEmail=${OWNER_EMAIL}" "SenderEmail=${SENDER_EMAIL}"

out() {
  aws cloudformation describe-stacks --stack-name "$STACK" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text
}
FUNCTION="$(out FunctionName)"
BUCKET="$(out BucketName)"
API_URL="$(out ApiUrl)"
SITE_URL="$(out SiteUrl)"

echo "== Uploading Lambda code to ${FUNCTION}"
TMP="$(mktemp -d)"
cp "$ROOT/src/handler.py" "$TMP/handler.py"
(cd "$TMP" && zip -q function.zip handler.py)
aws lambda update-function-code --function-name "$FUNCTION" --zip-file "fileb://$TMP/function.zip" >/dev/null
aws lambda wait function-updated --function-name "$FUNCTION"
rm -rf "$TMP"

echo "== Publishing website to s3://${BUCKET}"
echo "window.INQUIRY_API_URL = \"${API_URL}\";" > "$ROOT/web/config.js"
aws s3 sync "$ROOT/web/" "s3://${BUCKET}/" --delete

echo
echo "Done."
echo "  Site: ${SITE_URL}"
echo "  API:  ${API_URL}/inquiries"
