#!/bin/bash
# Add missing Windows Clustering security group rules
# This adds NetBIOS and additional Kerberos ports needed for clustering

set -e

STACK_NAME="${1:-sql-ag-demo}"
REGION="${2:-us-east-1}"

echo "===== Adding Missing Windows Clustering Ports ====="
echo "Stack: $STACK_NAME"
echo "Region: $REGION"
echo ""

# Get Security Group ID and VPC CIDR from CloudFormation
echo "[1/3] Getting security group ID from CloudFormation..."
SG_ID=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --region "$REGION" \
  --query 'Stacks[0].Outputs[?OutputKey==`SecurityGroupId`].OutputValue' \
  --output text)

VPC_CIDR="10.0.0.0/16"  # Default from your template

if [ -z "$SG_ID" ]; then
  echo "ERROR: Could not find security group ID in stack outputs"
  exit 1
fi

echo "Security Group ID: $SG_ID"
echo "VPC CIDR: $VPC_CIDR"
echo ""

# Add missing Windows Clustering rules
echo "[2/3] Adding missing Windows Clustering rules..."

# NetBIOS Name Service (UDP 137)
echo "Adding NetBIOS Name Service (UDP 137)..."
aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" \
  --ip-permissions IpProtocol=udp,FromPort=137,ToPort=137,IpRanges="[{CidrIp=$VPC_CIDR,Description='NetBIOS Name Service'}]" \
  --region "$REGION" 2>/dev/null || echo "  (Rule may already exist)"

# NetBIOS Datagram Service (UDP 138)
echo "Adding NetBIOS Datagram Service (UDP 138)..."
aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" \
  --ip-permissions IpProtocol=udp,FromPort=138,ToPort=138,IpRanges="[{CidrIp=$VPC_CIDR,Description='NetBIOS Datagram Service'}]" \
  --region "$REGION" 2>/dev/null || echo "  (Rule may already exist)"

# NetBIOS Session Service (TCP 139)
echo "Adding NetBIOS Session Service (TCP 139)..."
aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" \
  --ip-permissions IpProtocol=tcp,FromPort=139,ToPort=139,IpRanges="[{CidrIp=$VPC_CIDR,Description='NetBIOS Session Service'}]" \
  --region "$REGION" 2>/dev/null || echo "  (Rule may already exist)"

# Kerberos Password Change (TCP/UDP 464)
echo "Adding Kerberos Password Change (TCP/UDP 464)..."
aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" \
  --ip-permissions IpProtocol=tcp,FromPort=464,ToPort=464,IpRanges="[{CidrIp=$VPC_CIDR,Description='Kerberos Password Change'}]" \
  --region "$REGION" 2>/dev/null || echo "  (Rule may already exist)"

aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" \
  --ip-permissions IpProtocol=udp,FromPort=464,ToPort=464,IpRanges="[{CidrIp=$VPC_CIDR,Description='Kerberos Password Change UDP'}]" \
  --region "$REGION" 2>/dev/null || echo "  (Rule may already exist)"

# Windows Remote Management (WinRM) - TCP 5985, 5986
echo "Adding WinRM (TCP 5985-5986)..."
aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" \
  --ip-permissions IpProtocol=tcp,FromPort=5985,ToPort=5986,IpRanges="[{CidrIp=$VPC_CIDR,Description='WinRM'}]" \
  --region "$REGION" 2>/dev/null || echo "  (Rule may already exist)"

# Active Directory Web Services (ADWS) - TCP 9389
echo "Adding ADWS (TCP 9389)..."
aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" \
  --ip-permissions IpProtocol=tcp,FromPort=9389,ToPort=9389,IpRanges="[{CidrIp=$VPC_CIDR,Description='Active Directory Web Services'}]" \
  --region "$REGION" 2>/dev/null || echo "  (Rule may already exist)"

echo ""
echo "[3/3] Verifying security group rules..."
echo ""

aws ec2 describe-security-groups \
  --group-ids "$SG_ID" \
  --region "$REGION" \
  --query 'SecurityGroups[0].IpPermissions[*].[IpProtocol,FromPort,ToPort,IpRanges[0].Description]' \
  --output table

echo ""
echo "===== Security Group Rules Updated! ====="
echo ""
echo "Next Steps:"
echo "1. Run the troubleshooting script on SQL01: .\Troubleshoot-Clustering.ps1"
echo "2. Then try creating the cluster again"
echo ""