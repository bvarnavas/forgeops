#!/bin/bash
#
# Installs and configures AWS EFS. 
# Run this script from the ansible-config server.
#

set -o errexit
set -o pipefail
set -o nounset

source ../etc/os-aws-env.cfg

# Get the name of the IAM role associated with the EC2 instances
# OS_AWS_IAM_SETUP_ROLE=$(aws iam list-roles|grep ForgeOps-OpenShift-OpenShiftStack|grep SetupRole|grep RoleName|sed 's/\"RoleName\"\: \"//g'|sed 's/\",//g')

# Get the ARN of the EFS full access policy
# OS_AWS_IAM_EFS_POLICY=arn:aws:iam::aws:policy/AmazonElasticFileSystemFullAccess

# Add the policy to the IAM role
# aws iam attach-role-policy --role-name ${OS_AWS_IAM_SETUP_ROLE} --policy-arn ${OS_AWS_IAM_EFS_POLICY}

# Get the ID of the security group linked to the EC2 instances.
OS_AWS_EC2_SG_ID=$(aws ec2 describe-security-groups --filters Name=tag:"aws:cloudformation:logical-id",Values=OpenShiftSecurityGroup \
     --region ${OS_AWS_REGION} --query 'SecurityGroups[0].GroupId'|sed s/\"//g)


# Create the new EFS, associate with the VPC's 3 private subnets and the security group.
OS_AWS_EFS_ID=$(aws efs create-file-system --performance-mode maxIO --creation-token OS-AWS-NFSMount --query 'FileSystemId' --output text)


# Get the AWS ID for each private subnet
OS_AWS_PRIVATE_SUBNET_1_ID=$(aws ec2 describe-subnets --filters "Name=cidr-block,Values=${OS_AWS_PRIVATE_SUBNET_1_CIDR}" --query 'Subnets[0].SubnetId'|sed s/\"//g)
OS_AWS_PRIVATE_SUBNET_2_ID=$(aws ec2 describe-subnets --filters "Name=cidr-block,Values=${OS_AWS_PRIVATE_SUBNET_2_CIDR}" --query 'Subnets[0].SubnetId'|sed s/\"//g)
OS_AWS_PRIVATE_SUBNET_3_ID=$(aws ec2 describe-subnets --filters "Name=cidr-block,Values=${OS_AWS_PRIVATE_SUBNET_3_CIDR}" --query 'Subnets[0].SubnetId'|sed s/\"//g)


# Wait until EFS is ready and then display its AWS ID
while :
do
    OS_AWS_EFS_STATUS=$(aws efs describe-file-systems \
                      --file-system-id ${OS_AWS_EFS_ID} --query 'FileSystems[0].LifeCycleState' --output text)

    if [ $OS_AWS_EFS_STATUS == "available" ]; then
      echo "File system created with ID: ${OS_AWS_EFS_ID}. Please record this Id to configure backup and restore."
      break
    else
      sleep 10
      echo "Waiting for EFS volume..."
    fi

done

# Create a mount point using the private subnet from each availability zone, and grant access to EC2 instances by linking their security group. 
aws efs create-mount-target --file-system-id ${OS_AWS_EFS_ID} --subnet-id ${OS_AWS_PRIVATE_SUBNET_1_ID} --security-groups ${OS_AWS_EC2_SG_ID}
aws efs create-mount-target --file-system-id ${OS_AWS_EFS_ID} --subnet-id ${OS_AWS_PRIVATE_SUBNET_2_ID} --security-groups ${OS_AWS_EC2_SG_ID}
aws efs create-mount-target --file-system-id ${OS_AWS_EFS_ID} --subnet-id ${OS_AWS_PRIVATE_SUBNET_3_ID} --security-groups ${OS_AWS_EC2_SG_ID}


# Create and configure permissions to the /export directory in EFS
sudo yum install -y nfs-utils
mkdir /efs
mount -t nfs -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport ${OS_AWS_EFS_ID}.efs.${OS_AWS_REGION}.amazonaws.com:/ /efs
mkdir /efs/export
chmod 755 /efs/export


echo ""
echo "EFS installation and configuration completed."
echo ""





