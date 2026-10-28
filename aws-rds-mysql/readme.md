The commands assume your existing EKS cluster and VPC are the ones we confirmed earlier. They create a standard RDS MySQL instance, not Aurora.

## 1. Set environment variables

Copy and paste into Bash or AWS CloudShell:

bash

```
export AWS_REGION="us-west-2"
export EKS_CLUSTER_NAME="se-lab-eks"
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

export VPC_ID="vpc-0c3392f71bfb0827f"
export DB_INSTANCE_ID="se-lab-mysql"
export DB_NAME="selabdb"
export DB_USERNAME="dbadmin"
export DB_INSTANCE_CLASS="db.t3.micro"
export DB_ENGINE="mysql"
export DB_ENGINE_VERSION="8.4.11"
export DB_PORT="3306"
export DB_STORAGE_GB="20"

export DB_SG_ID="sg-0d79fcc23ad9e7267"
export SUBNET_1="subnet-03e220f2010954b1e"
export SUBNET_2="subnet-0fc1fcad63e7e8a98"
export SUBNET_3="subnet-038912fee2d0e47b9"
export DB_SUBNET_GROUP="se-lab-mysql-subnets"

export K8S_NAMESPACE="mysql"
export K8S_CLIENT_POD="mysql-client"
export K8S_SECRET_NAME="mysql-rds-credentials"

export AWS_PAGER=""
```

## 2. Verify AWS access and existing resources

bash

```
aws sts get-caller-identity

aws eks describe-cluster \
  --region "$AWS_REGION" \
  --name "$EKS_CLUSTER_NAME" \
  --query 'cluster.status' \
  --output text

aws ec2 describe-security-groups \
  --region "$AWS_REGION" \
  --group-ids "$DB_SG_ID" \
  --query 'SecurityGroups[0].VpcId' \
  --output text

aws rds describe-db-instances \
  --region "$AWS_REGION" \
  --db-instance-identifier "$DB_INSTANCE_ID" \
  --query 'DBInstances[0].DBInstanceIdentifier' \
  --output text 2>/dev/null || true
```

If `se-lab-mysql` already exists, do not run the creation commands again.

## 3. Set the database password

bash

```
read -rsp "Enter a strong RDS master password: " DB_PASSWORD
echo
```

Keep this terminal session open while you use the variable.

## 4. Create the DB subnet group

First, confirm the three subnets belong to your VPC:

bash

```
aws ec2 describe-subnets \
  --region "$AWS_REGION" \
  --subnet-ids "$SUBNET_1" "$SUBNET_2" "$SUBNET_3" \
  --query 'Subnets[*].[SubnetId,VpcId,AvailabilityZone]' \
  --output table
```

Create the subnet group:

bash

```
aws rds create-db-subnet-group \
  --region "$AWS_REGION" \
  --db-subnet-group-name "$DB_SUBNET_GROUP" \
  --db-subnet-group-description "Private subnets for EKS MySQL lab" \
  --subnet-ids "$SUBNET_1" "$SUBNET_2" "$SUBNET_3"
```

If the subnet group already exists, skip creation and verify it:

bash

```
aws rds describe-db-subnet-groups \
  --region "$AWS_REGION" \
  --db-subnet-group-name "$DB_SUBNET_GROUP"
```

## 5. Check the MySQL engine version

bash

```
aws rds describe-db-engine-versions \
  --region "$AWS_REGION" \
  --engine "$DB_ENGINE" \
  --query "DBEngineVersions[?EngineVersion=='$DB_ENGINE_VERSION'].EngineVersion" \
  --output table
```

If `8.4.11` is unavailable, choose an engine version returned by this command.

## 6. Create the RDS MySQL database

Only run this if the instance does not already exist:

bash

```
aws rds create-db-instance \
  --region "$AWS_REGION" \
  --db-instance-identifier "$DB_INSTANCE_ID" \
  --engine "$DB_ENGINE" \
  --engine-version "$DB_ENGINE_VERSION" \
  --db-instance-class "$DB_INSTANCE_CLASS" \
  --allocated-storage "$DB_STORAGE_GB" \
  --storage-type gp3 \
  --db-name "$DB_NAME" \
  --master-username "$DB_USERNAME" \
  --master-user-password "$DB_PASSWORD" \
  --vpc-security-group-ids "$DB_SG_ID" \
  --db-subnet-group-name "$DB_SUBNET_GROUP" \
  --port "$DB_PORT" \
  --no-publicly-accessible \
  --no-multi-az \
  --backup-retention-period 1 \
  --storage-encrypted \
  --no-deletion-protection
```

Note: AWS charges may apply. The instance class and storage settings do not guarantee Free Tier eligibility.

Wait for the database:

bash

```
aws rds wait db-instance-available \
  --region "$AWS_REGION" \
  --db-instance-identifier "$DB_INSTANCE_ID"
```

Retrieve the endpoint:

bash

```
export DB_ENDPOINT="$(
  aws rds describe-db-instances \
    --region "$AWS_REGION" \
    --db-instance-identifier "$DB_INSTANCE_ID" \
    --query 'DBInstances[0].Endpoint.Address' \
    --output text
)"

echo "RDS endpoint: $DB_ENDPOINT"
```

## 7. Configure Kubernetes access

Connect `kubectl` to your existing EKS cluster:

bash

```
aws eks update-kubeconfig \
  --region "$AWS_REGION" \
  --name "$EKS_CLUSTER_NAME"
```

Create the namespace if needed:

bash

```
kubectl create namespace "$K8S_NAMESPACE" \
  --dry-run=client -o yaml | kubectl apply -f -
```

Create or update the database credentials Secret:

bash

```
kubectl create secret generic "$K8S_SECRET_NAME" \
  --namespace "$K8S_NAMESPACE" \
  --from-literal=username="$DB_USERNAME" \
  --from-literal=password="$DB_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

unset DB_PASSWORD
```

## 8. Create the MySQL client pod

bash

```
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${K8S_CLIENT_POD}
  namespace: ${K8S_NAMESPACE}
  labels:
    app: mysql-client
spec:
  containers:
    - name: mysql-client
      image: mysql:8.4
      command: ["sh", "-c", "sleep infinity"]
      env:
        - name: MYSQL_HOST
          value: "${DB_ENDPOINT}"
        - name: MYSQL_DATABASE
          value: "${DB_NAME}"
        - name: MYSQL_USER
          valueFrom:
            secretKeyRef:
              name: ${K8S_SECRET_NAME}
              key: username
        - name: MYSQL_PWD
          valueFrom:
            secretKeyRef:
              name: ${K8S_SECRET_NAME}
              key: password
  restartPolicy: Always
EOF
```

Wait for the pod:

bash

```
kubectl wait \
  --namespace "$K8S_NAMESPACE" \
  --for=condition=Ready "pod/$K8S_CLIENT_POD" \
  --timeout=180s
```

## 9. Connect and test

bash

```
kubectl exec -it \
  -n "$K8S_NAMESPACE" \
  "$K8S_CLIENT_POD" -- \
  mysql -h "$DB_ENDPOINT" \
  -P "$DB_PORT" \
  -u "$DB_USERNAME" \
  -p "$DB_NAME"
```

Enter the database password when prompted.

Inside MySQL:

sql

```
SELECT VERSION();
SELECT DATABASE();
SHOW TABLES;
```

## 10. Important networking requirement

Your RDS security group must allow inbound TCP port `3306` from the appropriate EKS worker-node or pod security group. The commands above reuse your existing security group and do not change its inbound rules.

If connection attempts time out, inspect the security-group rules and subnet routing before changing anything.
