# Complete Google Cloud Secret Manager Setup Guide

This guide walks you through setting up SMTP2Graph with Google Cloud Secret Manager instead of Kubernetes Secrets.

## Prerequisites

- GKE cluster with Workload Identity enabled
- `gcloud` CLI installed and configured
- `kubectl` configured for your cluster
- Helm 3.x installed

## Step 1: Enable Required APIs

```bash
# Set your project
export PROJECT_ID="your-project-id"
gcloud config set project $PROJECT_ID

# Enable required APIs
gcloud services enable secretmanager.googleapis.com
gcloud services enable container.googleapis.com
```

## Step 2: Install Secrets Store CSI Driver

```bash
# Install the Secrets Store CSI Driver
helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts
helm repo update

helm install csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver \
  --namespace kube-system \
  --set syncSecret.enabled=true \
  --set enableSecretRotation=true
```

## Step 3: Create Secrets in Google Secret Manager

### App Registration Secrets

```bash
# Tenant
echo "contoso" | gcloud secrets create smtp2graph-tenant --data-file=-

# App ID
echo "01234567-89ab-cdef-0123-456789abcdef" | gcloud secrets create smtp2graph-app-id --data-file=-

# Certificate Thumbprint
echo "0123456789ABCDEF0123456789ABCDEF01234567" | gcloud secrets create smtp2graph-cert-thumbprint --data-file=-

# Certificate Key (from file)
gcloud secrets create smtp2graph-cert-key --data-file=./client.key
```

### SMTP Users Secret

```bash
# Create users.json file
cat > users.json <<'EOF'
[
  {
    "username": "app1",
    "password": "SecurePassword123!",
    "allowedFrom": ["noreply@example.com"]
  },
  {
    "username": "app2",
    "password": "AnotherPassword456!"
  }
]
EOF

# Upload to Secret Manager
gcloud secrets create smtp2graph-users --data-file=users.json

# Clean up local file
rm users.json
```

### Optional: TLS Certificate Secrets

```bash
# If you have TLS certificates
gcloud secrets create smtp2graph-tls-cert --data-file=./server.crt
gcloud secrets create smtp2graph-tls-key --data-file=./server.key
```

## Step 4: Create Google Service Account

```bash
# Create a Google Service Account for workload identity
export GSA_NAME="smtp2graph-sa"
export GSA_EMAIL="${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

gcloud iam service-accounts create $GSA_NAME \
  --display-name="SMTP2Graph Service Account"
```

## Step 5: Grant Secret Access Permissions

```bash
# Grant access to each secret
for secret in smtp2graph-tenant smtp2graph-app-id smtp2graph-cert-thumbprint smtp2graph-cert-key smtp2graph-users; do
  gcloud secrets add-iam-policy-binding $secret \
    --member="serviceAccount:${GSA_EMAIL}" \
    --role="roles/secretmanager.secretAccessor"
done

# If using TLS
# gcloud secrets add-iam-policy-binding smtp2graph-tls-cert \
#   --member="serviceAccount:${GSA_EMAIL}" \
#   --role="roles/secretmanager.secretAccessor"
#
# gcloud secrets add-iam-policy-binding smtp2graph-tls-key \
#   --member="serviceAccount:${GSA_EMAIL}" \
#   --role="roles/secretmanager.secretAccessor"
```

## Step 6: Configure Workload Identity

```bash
# Set namespace and KSA name
export NAMESPACE="default"
export KSA_NAME="smtp-relay"

# Allow the Kubernetes service account to impersonate the Google service account
gcloud iam service-accounts add-iam-policy-binding $GSA_EMAIL \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:${PROJECT_ID}.svc.id.goog[${NAMESPACE}/${KSA_NAME}]"
```

## Step 7: Create SecretProviderClass Resources

```bash
# Update the example files with your project ID
export PROJECT_ID="your-project-id"

# Create temporary directory
mkdir -p /tmp/smtp2graph-spc

# App Registration SecretProviderClass
cat > /tmp/smtp2graph-spc/appreg-spc.yaml <<EOF
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: smtp2graph-appreg-spc
  namespace: ${NAMESPACE}
spec:
  provider: gcp
  parameters:
    secrets: |
      - resourceName: "projects/${PROJECT_ID}/secrets/smtp2graph-tenant/versions/latest"
        fileName: "tenant"
      - resourceName: "projects/${PROJECT_ID}/secrets/smtp2graph-app-id/versions/latest"
        fileName: "appId"
      - resourceName: "projects/${PROJECT_ID}/secrets/smtp2graph-cert-thumbprint/versions/latest"
        fileName: "certificateThumbprint"
      - resourceName: "projects/${PROJECT_ID}/secrets/smtp2graph-cert-key/versions/latest"
        fileName: "certificateKey"
EOF

# SMTP Users SecretProviderClass
cat > /tmp/smtp2graph-spc/users-spc.yaml <<EOF
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: smtp2graph-users-spc
  namespace: ${NAMESPACE}
spec:
  provider: gcp
  parameters:
    secrets: |
      - resourceName: "projects/${PROJECT_ID}/secrets/smtp2graph-users/versions/latest"
        fileName: "users"
EOF

# Apply the SecretProviderClass resources
kubectl apply -f /tmp/smtp2graph-spc/appreg-spc.yaml
kubectl apply -f /tmp/smtp2graph-spc/users-spc.yaml
```

## Step 8: Create Helm Values File

```bash
cat > values-gcp.yaml <<EOF
# Service account configuration
serviceAccount:
  create: true
  name: smtp-relay
  annotations:
    iam.gke.io/gcp-service-account: ${GSA_EMAIL}

# Secret configuration using GCP Secret Manager
secrets:
  appRegistration:
    enabled: true
    useSecretProviderClass: true
    secretProviderClass:
      name: "smtp2graph-appreg-spc"
      mountPath: "/mnt/secrets-store/appreg"
      tenantFile: "tenant"
      appIdFile: "appId"
      certificateThumbprintFile: "certificateThumbprint"
      certificateKeyFile: "certificateKey"

  smtpUsers:
    enabled: true
    useSecretProviderClass: true
    secretProviderClass:
      name: "smtp2graph-users-spc"
      mountPath: "/mnt/secrets-store/users"
      usersFile: "users"

  tls:
    enabled: false
    # Uncomment to enable TLS with GCP Secret Manager
    # useSecretProviderClass: true
    # secretProviderClass:
    #   name: "smtp2graph-tls-spc"
    #   mountPath: "/mnt/secrets-store/tls"
    #   certFile: "tls.crt"
    #   keyFile: "tls.key"

# SMTP2Graph configuration
config:
  mode: full
  receive:
    port: 587
    secure: false
    requireAuth: true
    maxSize: 25m
  send:
    retryLimit: 3
    retryInterval: 5

# Service configuration
service:
  type: LoadBalancer
  port: 587

# Resource configuration
resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 250m
    memory: 256Mi
EOF
```

## Step 9: Install the Helm Chart

```bash
# Install the chart
helm install smtp-relay ./smtp-relay \
  --namespace ${NAMESPACE} \
  -f values-gcp.yaml

# Watch the deployment
kubectl get pods -n ${NAMESPACE} -w
```

## Step 10: Verify Installation

```bash
# Check pod status
kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=smtp-relay

# View initContainer logs to see secret loading
kubectl logs -n ${NAMESPACE} $(kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=smtp-relay -o name | head -n1) -c config-init

# View application logs
kubectl logs -n ${NAMESPACE} $(kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=smtp-relay -o name | head -n1) -c smtp-relay

# Get the external IP
kubectl get svc -n ${NAMESPACE} smtp-relay
```

## Troubleshooting

### Pod stuck in "ContainerCreating"

```bash
# Check events
kubectl describe pod -n ${NAMESPACE} $(kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=smtp-relay -o name | head -n1)

# Common issues:
# 1. Workload Identity not configured correctly
# 2. IAM permissions missing
# 3. SecretProviderClass not found
# 4. Secrets don't exist in Secret Manager
```

### Verify Workload Identity

```bash
# Check service account annotation
kubectl get sa -n ${NAMESPACE} smtp-relay -o yaml

# Should show:
# annotations:
#   iam.gke.io/gcp-service-account: smtp2graph-sa@PROJECT_ID.iam.gserviceaccount.com
```

### Verify Secret Access

```bash
# Test secret access from a test pod
kubectl run -it --rm test-pod \
  --image=google/cloud-sdk:slim \
  --serviceaccount=smtp-relay \
  --namespace=${NAMESPACE} \
  -- gcloud secrets versions access latest --secret=smtp2graph-tenant
```

### View CSI Driver Logs

```bash
# Check CSI driver logs
kubectl logs -n kube-system -l app=csi-secrets-store
```

## Rotating Secrets

To rotate secrets:

```bash
# Update the secret in Secret Manager
echo "new-value" | gcloud secrets versions add smtp2graph-tenant --data-file=-

# Restart the pods to pick up the new secret
kubectl rollout restart deployment -n ${NAMESPACE} smtp-relay

# Secrets are fetched at pod startup, so restarting will fetch the latest version
```

## Cleanup

```bash
# Uninstall the chart
helm uninstall smtp-relay -n ${NAMESPACE}

# Delete SecretProviderClass resources
kubectl delete secretproviderclass -n ${NAMESPACE} smtp2graph-appreg-spc smtp2graph-users-spc

# Delete secrets from Secret Manager
for secret in smtp2graph-tenant smtp2graph-app-id smtp2graph-cert-thumbprint smtp2graph-cert-key smtp2graph-users; do
  gcloud secrets delete $secret --quiet
done

# Delete Google Service Account
gcloud iam service-accounts delete $GSA_EMAIL --quiet

# Uninstall CSI Driver (optional)
helm uninstall csi-secrets-store -n kube-system
```

## Best Practices

1. **Use Secret Versions**: Pin to specific versions for production deployments
2. **Enable Rotation**: Use `enableSecretRotation=true` in CSI driver
3. **Least Privilege**: Only grant access to required secrets
4. **Audit Logging**: Enable Cloud Audit Logs for secret access
5. **Backup**: Export secret configurations before making changes
6. **Testing**: Test in a non-production cluster first
7. **Monitoring**: Set up alerts for failed secret access attempts

## Additional Resources

- [GCP Secret Manager Documentation](https://cloud.google.com/secret-manager/docs)
- [Workload Identity Documentation](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity)
- [Secrets Store CSI Driver](https://secrets-store-csi-driver.sigs.k8s.io/)
- [GCP Provider for Secrets Store CSI Driver](https://github.com/GoogleCloudPlatform/secrets-store-csi-driver-provider-gcp)
