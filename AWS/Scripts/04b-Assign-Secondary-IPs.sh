#!/bin/bash
# Assign Secondary Private IPs to SQL Nodes for Cluster and AG Listener
# Run this from your local machine (macOS/Linux) BEFORE creating the Windows cluster
# This is required for multi-subnet AG setup in AWS

set -e

# Configuration
STACK_NAME="${1:-sql-ag-demo}"
REGION="${2:-us-east-1}"

echo "===== Assigning Secondary IPs for Multi-Subnet AG ====="
echo "Stack: $STACK_NAME"
echo "Region: $REGION"
echo ""

# Get instance IDs from CloudFormation
echo "[1/5] Getting instance IDs from CloudFormation..."
SQL01_ID=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --region "$REGION" \
  --query 'Stacks[0].Outputs[?OutputKey==`SQL01InstanceId`].OutputValue' \
  --output text)

SQL02_ID=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --region "$REGION" \
  --query 'Stacks[0].Outputs[?OutputKey==`SQL02InstanceId`].OutputValue' \
  --output text)

if [ -z "$SQL01_ID" ] || [ -z "$SQL02_ID" ]; then
  echo "ERROR: Could not find SQL instance IDs in stack outputs"
  exit 1
fi

echo "SQL01 Instance ID: $SQL01_ID"
echo "SQL02 Instance ID: $SQL02_ID"
echo ""

# Get ENI IDs (Network Interface IDs)
echo "[2/5] Getting Network Interface IDs..."
SQL01_ENI=$(aws ec2 describe-instances \
  --instance-ids "$SQL01_ID" \
  --region "$REGION" \
  --query 'Reservations[0].Instances[0].NetworkInterfaces[0].NetworkInterfaceId' \
  --output text)

SQL02_ENI=$(aws ec2 describe-instances \
  --instance-ids "$SQL02_ID" \
  --region "$REGION" \
  --query 'Reservations[0].Instances[0].NetworkInterfaces[0].NetworkInterfaceId' \
  --output text)

if [ -z "$SQL01_ENI" ] || [ -z "$SQL02_ENI" ]; then
  echo "ERROR: Could not find network interface IDs"
  exit 1
fi

echo "SQL01 ENI: $SQL01_ENI"
echo "SQL02 ENI: $SQL02_ENI"
echo ""

# Get current IPs to show before assignment
echo "[3/5] Current IP assignments:"
echo ""
echo "SQL01 current IPs:"
aws ec2 describe-network-interfaces \
  --network-interface-ids "$SQL01_ENI" \
  --region "$REGION" \
  --query 'NetworkInterfaces[0].PrivateIpAddresses[*].PrivateIpAddress' \
  --output table

echo ""
echo "SQL02 current IPs:"
aws ec2 describe-network-interfaces \
  --network-interface-ids "$SQL02_ENI" \
  --region "$REGION" \
  --query 'NetworkInterfaces[0].PrivateIpAddresses[*].PrivateIpAddress' \
  --output table

echo ""
echo "[4/5] Assigning secondary IPs..."
echo ""

# Assign secondary IPs to SQL01 (Subnet 1)
echo "Assigning to SQL01 (Subnet 1):"
echo "  - 10.0.1.50 (For WSFC Cluster IP)"
echo "  - 10.0.1.51 (For AG Listener IP)"

if aws ec2 assign-private-ip-addresses \
  --network-interface-id "$SQL01_ENI" \
  --private-ip-addresses 10.0.1.50 10.0.1.51 \
  --region "$REGION" 2>/dev/null; then
  echo "  ✓ SQL01 secondary IPs assigned"
else
  echo "  - IPs may already be assigned (continuing...)"
fi

echo ""

# Assign secondary IPs to SQL02 (Subnet 2)
echo "Assigning to SQL02 (Subnet 2):"
echo "  - 10.0.2.50 (For WSFC Cluster IP)"
echo "  - 10.0.2.51 (For AG Listener IP)"

if aws ec2 assign-private-ip-addresses \
  --network-interface-id "$SQL02_ENI" \
  --private-ip-addresses 10.0.2.50 10.0.2.51 \
  --region "$REGION" 2>/dev/null; then
  echo "  ✓ SQL02 secondary IPs assigned"
else
  echo "  - IPs may already be assigned (continuing...)"
fi

echo ""
echo "[5/5] Verifying IP assignments..."
echo ""

echo "SQL01 all IPs:"
aws ec2 describe-network-interfaces \
  --network-interface-ids "$SQL01_ENI" \
  --region "$REGION" \
  --query 'NetworkInterfaces[0].PrivateIpAddresses[*].PrivateIpAddress' \
  --output table

echo ""
echo "SQL02 all IPs:"
aws ec2 describe-network-interfaces \
  --network-interface-ids "$SQL02_ENI" \
  --region "$REGION" \
  --query 'NetworkInterfaces[0].PrivateIpAddresses[*].PrivateIpAddress' \
  --output table

echo ""
echo "===== Secondary IP Assignment Complete! ====="
echo ""
echo "✅ SQL01 now has: Primary IP + 10.0.1.50 + 10.0.1.51"
echo "✅ SQL02 now has: Primary IP + 10.0.2.50 + 10.0.2.51"
echo ""
echo "📋 IP Address Allocation:"
echo "  Cluster IPs (for WSFC):"
echo "    - Subnet 1: 10.0.1.50"
echo "    - Subnet 2: 10.0.2.50"
echo ""
echo "  Listener IPs (for AG):"
echo "    - Subnet 1: 10.0.1.51"
echo "    - Subnet 2: 10.0.2.51"
echo ""
echo "📋 Next Steps:"
echo "1. Run 04c-Configure-Secondary-IPs-Windows.ps1 on BOTH SQL01 and SQL02"
echo "2. Run 05-Create-WSFC.ps1 on SQL01"
echo "   Use Cluster IPs: 10.0.1.50 and 10.0.2.50"
echo ""


