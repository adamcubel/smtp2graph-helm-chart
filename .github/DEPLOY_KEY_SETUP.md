# GitHub Deploy Key Setup for Release Workflow

This document explains how to set up a GitHub Deploy Key to allow the release workflow to push Chart.yaml version updates to the protected `main` branch.

## Why Deploy Keys?

Branch protection rules typically prevent direct pushes to protected branches like `main`. However, the release workflow needs to:
1. Update the `version` field in `smtp-relay/Chart.yaml`
2. Commit and push this change back to `main`
3. Create git tags for releases

A **Deploy Key** with write access allows the GitHub Actions workflow to bypass branch protection rules and push commits.

## Setup Instructions

### Step 1: Generate SSH Key Pair

On your local machine, generate a new SSH key pair specifically for this repository:

```bash
# Generate a new SSH key (use a meaningful name)
ssh-keygen -t ed25519 -C "github-actions-deploy-key" -f ~/.ssh/smtp2graph_deploy_key

# This creates two files:
# - ~/.ssh/smtp2graph_deploy_key (private key)
# - ~/.ssh/smtp2graph_deploy_key.pub (public key)
```

**Important**: Use a strong passphrase or leave it empty (not recommended for production).

### Step 2: Add Public Key as Deploy Key

1. Go to your GitHub repository: `https://github.com/YOUR_USERNAME/smtp2graph-helm-chart`
2. Click **Settings** → **Deploy keys**
3. Click **Add deploy key**
4. Fill in the form:
   - **Title**: `GitHub Actions Release Workflow`
   - **Key**: Paste the contents of `~/.ssh/smtp2graph_deploy_key.pub`
   - **Allow write access**: ✅ **CHECK THIS BOX** (very important!)
5. Click **Add key**

### Step 3: Add Private Key as Repository Secret

1. Go to your GitHub repository: `https://github.com/YOUR_USERNAME/smtp2graph-helm-chart`
2. Click **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Fill in the form:
   - **Name**: `DEPLOY_KEY`
   - **Secret**: Paste the contents of `~/.ssh/smtp2graph_deploy_key` (the private key, not the .pub file)
5. Click **Add secret**

### Step 4: Verify the Setup

The workflow is already configured to use the deploy key. You can verify it's working by:

1. Create a test PR with `[patch]` in the title
2. Merge the PR to `main`
3. Watch the release workflow run:
   - Go to **Actions** tab
   - Click on the "Release Helm Chart" workflow
   - Verify the "Commit version update" step succeeds

## How It Works

The workflow uses the deploy key in the checkout step:

```yaml
- name: Checkout
  uses: actions/checkout@v4
  with:
    fetch-depth: 0
    ssh-key: ${{ secrets.DEPLOY_KEY }}
```

When the workflow pushes to `main`, it uses SSH authentication with the deploy key, which has write permissions and can bypass branch protection.

## Preventing Infinite Loops

The commit message includes `[skip ci]` to prevent the workflow from triggering itself:

```yaml
git commit -m "chore: bump chart version to X.Y.Z [skip ci]"
```

This ensures that:
1. PR merge triggers release workflow
2. Workflow updates Chart.yaml and pushes to main
3. The `[skip ci]` tag prevents another workflow run
4. Process completes successfully

## Security Considerations

1. **Keep Private Key Secret**: Never commit or share the private key
2. **Rotate Keys Regularly**: Generate new keys periodically (every 6-12 months)
3. **Audit Access**: Review deploy key usage in GitHub audit logs
4. **Least Privilege**: This key only has access to this repository
5. **Delete Old Keys**: Remove unused deploy keys from GitHub

## Troubleshooting

### Error: "Permission denied (publickey)"

**Cause**: The private key secret is not set correctly or doesn't match the public deploy key.

**Solution**:
1. Verify the `DEPLOY_KEY` secret contains the entire private key
2. Ensure the deploy key on GitHub matches the public key
3. Regenerate the key pair if needed

### Error: "Protected branch update failed"

**Cause**: The deploy key doesn't have write access enabled.

**Solution**:
1. Go to **Settings** → **Deploy keys**
2. Edit the deploy key
3. Check **Allow write access**
4. Save changes

### Commit Still Triggers Another Workflow

**Cause**: The `[skip ci]` tag is not working.

**Solution**:
1. Verify the commit message includes `[skip ci]`
2. Check GitHub Actions settings for skip patterns
3. Ensure no other workflows trigger on all pushes without skip filters

### Deploy Key Not Being Used

**Cause**: The secret name doesn't match.

**Solution**:
1. Verify the secret is named exactly `DEPLOY_KEY` (case-sensitive)
2. Check the workflow file references `${{ secrets.DEPLOY_KEY }}`
3. Ensure the secret is available in the repository (not organization-level)

## Alternative: Personal Access Token (PAT)

If you prefer not to use deploy keys, you can use a Personal Access Token instead:

1. Create a PAT with `repo` scope
2. Add it as a secret named `PAT_TOKEN`
3. Update the checkout step:
   ```yaml
   - name: Checkout
     uses: actions/checkout@v4
     with:
       fetch-depth: 0
       token: ${{ secrets.PAT_TOKEN }}
   ```

**Note**: PATs are tied to a user account and may have broader permissions than deploy keys. Deploy keys are repository-specific and more secure.

## Cleanup

If you need to remove the deploy key:

1. Delete the deploy key from GitHub: **Settings** → **Deploy keys**
2. Delete the repository secret: **Settings** → **Secrets and variables** → **Actions**
3. Remove the private key from your local machine:
   ```bash
   rm ~/.ssh/smtp2graph_deploy_key
   rm ~/.ssh/smtp2graph_deploy_key.pub
   ```

## References

- [GitHub Deploy Keys Documentation](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/managing-deploy-keys)
- [GitHub Actions Checkout Action](https://github.com/actions/checkout)
- [GitHub Actions Secrets](https://docs.github.com/en/actions/security-guides/encrypted-secrets)
- [Skipping Workflow Runs](https://docs.github.com/en/actions/managing-workflow-runs/skipping-workflow-runs)
