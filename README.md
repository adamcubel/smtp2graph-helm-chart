# SMTP2Graph Helm Chart

A Helm chart for deploying [SMTP2Graph](https://www.smtp2graph.com) on Kubernetes. SMTP2Graph is an SMTP relay that receives emails and forwards them to Microsoft 365 using the Microsoft Graph API.

## Features

- Secure configuration management using Kubernetes Secrets
- Automatic config merging via initContainer
- TCP-based health probes for SMTP port monitoring
- Support for certificate-based and client secret authentication
- Dynamic SMTP user management
- Optional TLS support for secure SMTP connections
- Configurable resource limits and autoscaling

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- Azure App Registration with Microsoft Graph API permissions
- Pre-existing Kubernetes secrets (see below)

## Installation

The chart supports two methods for managing secrets:
1. **Kubernetes Secrets** (default) - Native Kubernetes secrets
2. **Google Cloud Secret Manager** - Using SecretProviderClass and CSI driver

### 1. Create Required Secrets

#### Option A: Using Kubernetes Secrets (Default)

Before installing the chart, you must create the required secrets in your cluster.

#### Azure App Registration Secret

```bash
kubectl create secret generic smtp2graph-appreg \
  --from-literal=tenant=your-tenant-name \
  --from-literal=appId=your-app-id \
  --from-literal=certificateThumbprint=your-cert-thumbprint \
  --from-file=certificateKey=./client.key
```

See [examples/secret-appreg.yaml](smtp-relay/examples/secret-appreg.yaml) for more details.

#### SMTP Users Secret

```bash
kubectl create secret generic smtp2graph-users \
  --from-literal=users='[{"username":"user1","password":"pass1"},{"username":"user2","password":"pass2"}]'
```

See [examples/secret-users.yaml](smtp-relay/examples/secret-users.yaml) for more details.

#### Optional: TLS Certificate Secret

```bash
kubectl create secret tls smtp2graph-tls \
  --cert=./server.crt \
  --key=./server.key
```

See [examples/secret-tls.yaml](smtp-relay/examples/secret-tls.yaml) for more details.

#### Option B: Using Google Cloud Secret Manager

For GKE clusters, you can use Google Cloud Secret Manager with the Secrets Store CSI Driver.

**Prerequisites:**
- GKE cluster with Workload Identity enabled
- Secrets Store CSI Driver installed
- Google Cloud Secret Manager API enabled

**1. Create SecretProviderClass resources:**

```bash
# Apply the SecretProviderClass definitions
kubectl apply -f smtp-relay/examples/secretproviderclass-appreg.yaml
kubectl apply -f smtp-relay/examples/secretproviderclass-users.yaml
kubectl apply -f smtp-relay/examples/secretproviderclass-tls.yaml  # Optional
```

See example files:
- [secretproviderclass-appreg.yaml](smtp-relay/examples/secretproviderclass-appreg.yaml)
- [secretproviderclass-users.yaml](smtp-relay/examples/secretproviderclass-users.yaml)
- [secretproviderclass-tls.yaml](smtp-relay/examples/secretproviderclass-tls.yaml)

**2. Create secrets in Google Secret Manager:**

```bash
# App Registration secrets
gcloud secrets create smtp2graph-tenant --data-file=- <<EOF
your-tenant-name
EOF

gcloud secrets create smtp2graph-app-id --data-file=- <<EOF
01234567-89ab-cdef-0123-456789abcdef
EOF

gcloud secrets create smtp2graph-cert-thumbprint --data-file=- <<EOF
0123456789ABCDEF0123456789ABCDEF01234567
EOF

gcloud secrets create smtp2graph-cert-key --data-file=./client.key

# SMTP Users
gcloud secrets create smtp2graph-users --data-file=./users.json
```

**3. Grant IAM permissions:**

```bash
# For each secret, grant access to your Kubernetes service account
gcloud secrets add-iam-policy-binding smtp2graph-tenant \
  --member="serviceAccount:YOUR_PROJECT_ID.svc.id.goog[default/smtp-relay]" \
  --role="roles/secretmanager.secretAccessor"

# Repeat for all secrets
```

**4. Configure Workload Identity:**

```bash
# Annotate the Kubernetes service account
kubectl annotate serviceaccount smtp-relay \
  iam.gke.io/gcp-service-account=YOUR_GSA@YOUR_PROJECT_ID.iam.gserviceaccount.com

# Bind Google Service Account to Kubernetes Service Account
gcloud iam service-accounts add-iam-policy-binding \
  YOUR_GSA@YOUR_PROJECT_ID.iam.gserviceaccount.com \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:YOUR_PROJECT_ID.svc.id.goog[default/smtp-relay]"
```

### 2. Install the Chart

#### Using Kubernetes Secrets (Default):

```bash
# Install the chart with Kubernetes secrets
helm install smtp-relay ./smtp-relay \
  --set secrets.appRegistration.secretName=smtp2graph-appreg \
  --set secrets.smtpUsers.secretName=smtp2graph-users
```

#### Using Google Cloud Secret Manager:

```bash
# Install the chart with GCP Secret Manager
helm install smtp-relay ./smtp-relay \
  --set secrets.appRegistration.useSecretProviderClass=true \
  --set secrets.appRegistration.secretProviderClass.name=smtp2graph-appreg-spc \
  --set secrets.smtpUsers.useSecretProviderClass=true \
  --set secrets.smtpUsers.secretProviderClass.name=smtp2graph-users-spc
```

Or create a custom values file:

```yaml
# values-gcp.yaml
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
```

Then install:

```bash
helm install smtp-relay ./smtp-relay -f values-gcp.yaml
```

### 3. Verify Installation

```bash
# Check pod status
kubectl get pods -l app.kubernetes.io/name=smtp-relay

# View initContainer logs to see merged configuration
kubectl logs <pod-name> -c config-init

# View application logs
kubectl logs <pod-name> -c smtp-relay
```

## Configuration

The following table lists the configurable parameters of the SMTP2Graph chart and their default values.

### Basic Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of replicas | `1` |
| `image.repository` | Image repository | `smtp2graph/smtp2graph` |
| `image.tag` | Image tag | `v1.1.4` |
| `image.pullPolicy` | Image pull policy | `IfNotPresent` |

### SMTP2Graph Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `config.mode` | Operation mode (full, receive, send) | `full` |
| `config.receive.port` | SMTP port | `587` |
| `config.receive.secure` | Require TLS | `false` |
| `config.receive.requireAuth` | Require authentication | `true` |
| `config.receive.maxSize` | Maximum message size | `25m` |
| `config.send.retryLimit` | Number of retry attempts | `3` |
| `config.send.retryInterval` | Minutes between retries | `5` |

### Secret Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `secrets.appRegistration.enabled` | Enable app registration secret | `true` |
| `secrets.appRegistration.secretName` | Name of app registration secret | `smtp2graph-appreg` |
| `secrets.smtpUsers.enabled` | Enable SMTP users secret | `true` |
| `secrets.smtpUsers.secretName` | Name of SMTP users secret | `smtp2graph-users` |
| `secrets.tls.enabled` | Enable TLS secret | `false` |
| `secrets.tls.secretName` | Name of TLS secret | `smtp2graph-tls` |

### Service Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `service.type` | Service type (ClusterIP, NodePort, LoadBalancer) | `LoadBalancer` |
| `service.port` | Service port | `587` |
| `service.loadBalancerIP` | Static IP for LoadBalancer (cloud provider specific) | `""` |
| `service.loadBalancerSourceRanges` | Restrict access to specific IP ranges | `[]` |
| `service.externalTrafficPolicy` | External traffic policy (Cluster or Local) | Not set |
| `service.sessionAffinity` | Session affinity (None or ClientIP) | Not set |

### Probe Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `livenessProbe.tcpSocket.port` | Liveness probe port | `smtp` |
| `livenessProbe.initialDelaySeconds` | Liveness initial delay | `10` |
| `readinessProbe.tcpSocket.port` | Readiness probe port | `smtp` |
| `readinessProbe.initialDelaySeconds` | Readiness initial delay | `5` |

See [values.yaml](smtp-relay/values.yaml) for all available configuration options.

## How It Works

### Configuration Management

The chart uses a sophisticated configuration management approach:

1. **ConfigMap**: Stores non-sensitive base configuration
2. **Secrets**: Store sensitive data (app credentials, SMTP users, TLS certs)
3. **InitContainer**: Merges ConfigMap and Secrets into final config at runtime
4. **EmptyDir Volume**: Shares merged config between initContainer and main container

### InitContainer Process

The initContainer (`mikefarah/yq`) performs the following:

1. Copies base config from ConfigMap to `/data/config.yml`
2. Merges Azure App Registration details from secret
3. Merges SMTP users from secret (JSON array format)
4. Copies TLS certificates if enabled
5. Outputs final configuration for verification

### Health Probes

The chart uses **TCP socket probes** instead of HTTP probes because SMTP2Graph is a pure SMTP service:

- **Liveness Probe**: Checks if port 587 is accepting connections (restarts pod on failure)
- **Readiness Probe**: Ensures port 587 is ready before routing traffic

### Load Distribution

The service is configured as **LoadBalancer** type by default, which:

1. **Provisions an external load balancer** (on supported cloud providers like AWS, Azure, GCP)
2. **Automatically distributes traffic** across all healthy pods in the deployment
3. **Provides external access** to the SMTP service from outside the cluster

**Important Notes:**
- Kubernetes services automatically load balance traffic across pods regardless of service type
- LoadBalancer provides external access + cloud provider load balancing
- For multiple replicas, set `replicaCount` > 1 in values.yaml
- Use `externalTrafficPolicy: Local` to preserve client source IP (disables cross-node load balancing)
- Use `sessionAffinity: ClientIP` for sticky sessions (keeps same client connected to same pod)

**Example: Multi-replica with sticky sessions**
```bash
helm install smtp-relay ./smtp-relay \
  --set replicaCount=3 \
  --set service.sessionAffinity=ClientIP \
  --set service.sessionAffinityConfig.clientIP.timeoutSeconds=10800
```

**Example: Restrict access by IP**
```bash
helm install smtp-relay ./smtp-relay \
  --set service.loadBalancerSourceRanges={10.0.0.0/8,192.168.0.0/16}
```

### Google Cloud Secret Manager Integration

The chart supports **Google Cloud Secret Manager** as an alternative to Kubernetes Secrets, providing:

1. **Centralized Secret Management**: Store secrets in GCP Secret Manager
2. **Automatic Rotation**: Secrets are fetched at pod startup
3. **Fine-grained IAM**: Control access using GCP IAM policies
4. **Audit Logging**: Track secret access in Cloud Logging
5. **Workload Identity**: Secure authentication without service account keys

**How it works:**
1. Secrets are stored in Google Secret Manager
2. `SecretProviderClass` resources define which secrets to mount
3. The Secrets Store CSI Driver mounts secrets as files in the pod
4. The initContainer reads these files and merges them into the SMTP2Graph config

**Architecture:**
```
Google Secret Manager → SecretProviderClass → CSI Driver → Pod Volume → InitContainer → Config Merge
```

**Setup Requirements:**
- GKE cluster with Workload Identity enabled
- Secrets Store CSI Driver installed: [Installation Guide](https://secrets-store-csi-driver.sigs.k8s.io/getting-started/installation.html)
- Google Cloud Secret Manager API enabled
- Appropriate IAM permissions configured

**Advantages over Kubernetes Secrets:**
- ✅ Secrets never stored in etcd
- ✅ Centralized management across multiple clusters
- ✅ Built-in versioning and rotation
- ✅ Integration with GCP security ecosystem
- ✅ Compliance-friendly audit trails

See the [examples directory](smtp-relay/examples/) for complete SecretProviderClass templates.

## Upgrading

### Updating Configuration

To update non-sensitive configuration:

```bash
helm upgrade smtp-relay ./smtp-relay \
  --set config.receive.maxSize=50m \
  --set config.send.retryLimit=5
```

### Updating Secrets

To update secrets, modify the secret and restart the pods:

```bash
# Update secret
kubectl edit secret smtp2graph-appreg

# Restart pods to pick up changes
kubectl rollout restart deployment smtp-relay
```

## Uninstallation

```bash
helm uninstall smtp-relay
```

Note: Secrets are not automatically deleted. Remove them manually if needed:

```bash
kubectl delete secret smtp2graph-appreg smtp2graph-users smtp2graph-tls
```

## Troubleshooting

### View Merged Configuration

```bash
kubectl logs <pod-name> -c config-init
```

### Check SMTP Connectivity

```bash
# Port forward to test locally
kubectl port-forward svc/smtp-relay 587:587

# Test with telnet or openssl
telnet localhost 587
# or
openssl s_client -connect localhost:587 -starttls smtp
```

### Common Issues

#### Pod stuck in Init:Error

- Check initContainer logs: `kubectl logs <pod-name> -c config-init`
- Verify secrets exist: `kubectl get secret smtp2graph-appreg smtp2graph-users`
- Verify secret keys match values.yaml configuration

#### Liveness probe failing

- Check if SMTP2Graph is listening on port 587
- View application logs: `kubectl logs <pod-name>`
- Verify port configuration in values.yaml

## Security Considerations

1. **Never commit secrets to version control**
2. Use Kubernetes RBAC to restrict secret access
3. Consider using external secret management (e.g., Azure Key Vault, HashiCorp Vault)
4. Enable TLS for production SMTP connections
5. Use strong passwords for SMTP users
6. Regularly rotate certificates and credentials

## Additional Resources

- [SMTP2Graph Documentation](https://www.smtp2graph.com)
- [SMTP2Graph GitHub](https://github.com/SMTP2Graph/SMTP2Graph)
- [Microsoft Graph API](https://docs.microsoft.com/en-us/graph/)
- [Helm Documentation](https://helm.sh/docs/)

## License

This Helm chart is provided as-is. See SMTP2Graph project for application license.
