#!/usr/bin/env bash
# Sends one test inquiry straight to the API, then sends the same request id again
# to show the duplicate protection. Usage: scripts/smoke-test.sh
set -euo pipefail

STACK="${STACK:-inquiry-service}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-west-2}"
API_URL="$(aws cloudformation describe-stacks --stack-name "$STACK" \
  --query "Stacks[0].Outputs[?OutputKey=='ApiUrl'].OutputValue" --output text)"
SITE_URL="$(aws cloudformation describe-stacks --stack-name "$STACK" \
  --query "Stacks[0].Outputs[?OutputKey=='SiteUrl'].OutputValue" --output text)"
REQUEST_ID="$(uuidgen | tr 'A-Z' 'a-z')"
BODY="{\"requestId\":\"${REQUEST_ID}\",\"name\":\"Dilan Patel (smoke test)\",\"email\":\"test@example.com\",\"message\":\"Hello from the smoke test.\"}"

echo "--- 1st request (should save and email)"
curl -s -X POST "${API_URL}/inquiries" -H "Origin: ${SITE_URL}" -H 'Content-Type: application/json' -d "$BODY"
echo
echo "--- same request id again (should report duplicate, no second email)"
curl -s -X POST "${API_URL}/inquiries" -H "Origin: ${SITE_URL}" -H 'Content-Type: application/json' -d "$BODY"
echo
echo "--- invalid request (should return 400)"
curl -s -X POST "${API_URL}/inquiries" -H 'Content-Type: application/json' -d '{"name":"","email":"nope","message":""}'
echo
