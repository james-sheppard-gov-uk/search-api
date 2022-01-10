#!/usr/bin/env bash

set -euo pipefail

EC2_NAME="govuk-${GOVUK_ENVIRONMENT}-search-ltr-generation"
S3_BUCKET="govuk-${GOVUK_ENVIRONMENT}-search-relevancy"
GIT_BRANCH="deployed-to-${GOVUK_ENVIRONMENT}"
AWS_REGION="eu-west-1"

find_instance_id() {
  aws ec2 describe-instances --region "$AWS_REGION" --query "Reservations[*].Instances[*].InstanceId" --filters Name=instance-state-name,Values=running,pending  Name=tag:Name,Values="$EC2_NAME" --output=text
}

echo "Scaling up ASG..."
aws autoscaling set-desired-capacity \
    --region "$AWS_REGION" \
    --auto-scaling-group-name "$EC2_NAME" \
    --desired-capacity 1

instance_id=$(find_instance_id)
while [[ "$instance_id" == "" ]]; do
  echo "    still waiting for instance ID..."
  sleep 30
  instance_id=$(find_instance_id)
done

echo "Waiting on instance ${instance_id}..."
aws ec2 wait instance-status-ok \
    --region "$AWS_REGION" \
    --instance-ids "${instance_id}"

echo "$SSH_PRIVATE_KEY" > /tmp/concourse_ssh_key
chmod 400 /tmp/concourse_ssh_key

instance_hostname=$(aws ec2 describe-instances --region "$AWS_REGION" --query "Reservations[*].Instances[*].PrivateDnsName" --filter Name=tag:Name,Values="$EC2_NAME" --output=text | tr -d "\r\n")

echo "Connecting to instance..."
NOW="$(date +%s)"
ssh -i /tmp/concourse_ssh_key -o StrictHostKeyChecking=no "ubuntu@${instance_hostname}" env \
  NOW="${NOW}" \
  GIT_BRANCH="deployed-to-${GOVUK_ENVIRONMENT}" \
  S3_BUCKET="govuk-${GOVUK_ENVIRONMENT}-search-relevancy" \
  ELASTICSEARCH_URI=$ELASTICSEARCH_URI \
  BIGQUERY_CREDENTIALS=$BIGQUERY_CREDENTIALS \
  'bash -s' < ./ltr/concourse/train_and_deploy_model.sh

echo "Scaling down ASG..."
aws autoscaling set-desired-capacity \
    --region "$AWS_REGION" \
    --auto-scaling-group-name "$EC2_NAME" \
    --desired-capacity 0

echo "$NOW" > "out/${GOVUK_ENVIRONMENT}-${OUTPUT_FILE_NAME}-$(date +%s).txt"
