#!/bin/bash
# Create one EC2 instance per tier with the AWS CLI and point Route 53 records at them.
# Usage: ./launch-instances.sh mysql backend frontend
# Requires: aws CLI configured, and the variables below set for your account.

AMI_ID=${AMI_ID:?Set AMI_ID (RHEL 9 or Amazon Linux 2023)}
SG_ID=${SG_ID:?Set SG_ID (security group id)}
ZONE_ID=${ZONE_ID:?Set ZONE_ID (Route 53 hosted zone id)}
DOMAIN=${DOMAIN:?Set DOMAIN, e.g. example.com}
INSTANCE_TYPE=${INSTANCE_TYPE:-t3.micro}

if [ $# -eq 0 ]; then
    echo "Usage: $0 mysql backend frontend"
    exit 1
fi

for instance in "$@"; do
    INSTANCE_ID=$(aws ec2 run-instances \
        --image-id "$AMI_ID" \
        --instance-type "$INSTANCE_TYPE" \
        --security-group-ids "$SG_ID" \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=bagtrace-$instance},{Key=Project,Value=bagtrace}]" \
        --query 'Instances[0].InstanceId' --output text)

    aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"

    # The frontend is public; the other tiers are reached on their private IPs.
    if [ "$instance" == "frontend" ]; then
        IP=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
            --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
        RECORD="$DOMAIN"
    else
        IP=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
            --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)
        RECORD="$instance.$DOMAIN"
    fi
    echo "bagtrace-$instance: $INSTANCE_ID ($IP) -> $RECORD"

    aws route53 change-resource-record-sets --hosted-zone-id "$ZONE_ID" --change-batch "{
        \"Comment\": \"BagTrace $instance\",
        \"Changes\": [{
            \"Action\": \"UPSERT\",
            \"ResourceRecordSet\": {
                \"Name\": \"$RECORD\",
                \"Type\": \"A\",
                \"TTL\": 1,
                \"ResourceRecords\": [{\"Value\": \"$IP\"}]
            }
        }]
    }" > /dev/null
done
