#!/usr/bin/env bash
# Deletes everything the stack created. The SES identity is left alone (it is yours).
set -euo pipefail

STACK="${STACK:-inquiry-service}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-west-2}"

BUCKET="$(aws cloudformation describe-stacks --stack-name "$STACK" \
  --query "Stacks[0].Outputs[?OutputKey=='BucketName'].OutputValue" --output text)"
echo "Emptying s3://${BUCKET}"
aws s3 rm "s3://${BUCKET}" --recursive
echo "Deleting stack ${STACK}"
aws cloudformation delete-stack --stack-name "$STACK"
aws cloudformation wait stack-delete-complete --stack-name "$STACK"
echo "Deleted."
