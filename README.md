# terraform-deploy-openstack

Step-by-step guide to installing Terraform on macOS and deploying a RHEL9 VM on OpenStack.

---

## Table of Contents

1. [Install Terraform on macOS](#1-install-terraform-on-macos)
2. [Set Up OpenStack Authentication](#2-set-up-openstack-authentication)
3. [Clone This Repository](#3-clone-this-repository)
4. [Configure Your Deployment](#4-configure-your-deployment)
5. [Deploy the VM](#5-deploy-the-vm)
6. [Connect to the VM](#6-connect-to-the-vm)
7. [Destroy the VM](#7-destroy-the-vm)
8. [Troubleshooting](#8-troubleshooting)

---

## 1. Install Terraform on macOS

### Option A — Homebrew (recommended)

If you do not have Homebrew installed:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Install Terraform:

```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
```

Verify the installation:

```bash
terraform -version
```

Expected output:

```
Terraform v1.x.x
on darwin_arm64
```

### Option B — Manual Install

1. Go to https://developer.hashicorp.com/terraform/downloads
2. Download the macOS ARM64 (Apple Silicon) or AMD64 (Intel) zip
3. Unzip and move the binary:

```bash
unzip terraform_*.zip
sudo mv terraform /usr/local/bin/
terraform -version
```

### Enable Tab Completion (optional)

```bash
terraform -install-autocomplete
```

---

## 2. Set Up OpenStack Authentication

Terraform uses your `clouds.yaml` file to authenticate with OpenStack. No credentials are ever stored in Terraform files.

### Download clouds.yaml

Log in to your OpenStack Horizon web console and download your `clouds.yaml`:

**Profile menu (top right) → OpenStack RC File → Download clouds.yaml**

### Install clouds.yaml

```bash
mkdir -p ~/.config/openstack
cp ~/Downloads/clouds.yaml ~/.config/openstack/clouds.yaml
```

### Application Credentials (required for MFA / federated identity)

If your OpenStack cluster uses MFA or an external identity provider, you must use application credentials — password auth will not work via the API.

**Create an application credential in Horizon:**

1. Log in to the Horizon web console (MFA handled by the browser)
2. Go to **Identity → Application Credentials**
3. Click **Create Application Credential**
4. Set a name (e.g. `terraform-deploy`)
5. In the **Roles** field select `member`
6. Click **Create Application Credential**
7. Copy the **ID** and **Secret** shown — the secret is only displayed once

**Update your `~/.config/openstack/clouds.yaml`:**

```yaml
clouds:
  openstack:
    auth:
      auth_url: https://your-cluster:13000/v3
      application_credential_id: "<paste id here>"
      application_credential_secret: "<paste secret here>"
    auth_type: v3applicationcredential
    interface: public
    identity_api_version: 3
```

### Verify Authentication

Install the OpenStack CLI to test:

```bash
pip3 install python-openstackclient
openstack --os-cloud openstack token issue
```

A table with a token ID confirms authentication is working.

---

## 3. Clone This Repository

```bash
git clone https://github.com/geeteq/terraform-deploy-openstack.git
cd terraform-deploy-openstack
```

---

## 4. Configure Your Deployment

### Copy the example variables file

```bash
cp terraform.tfvars.example terraform.tfvars
```

### Edit terraform.tfvars

Open `terraform.tfvars` in your editor and fill in your values:

```hcl
cloud_name        = "openstack"     # must match your clouds.yaml cloud name
vm_name           = "jumpbox"
image_name        = "rhel9"         # exact image name in OpenStack
flavor_name       = "m1.medium"     # exact flavor name in OpenStack
network_name      = "your-network"  # network to attach the VM to
availability_zone = "nova"
floating_ip_pool  = ""              # external network name for a public IP, or leave empty
baremetal_user    = "baremetal"
ssh_public_key    = "ssh-rsa AAAA... user@host"

security_groups = [
  "default",
  "ssh-access"
]

packages = [
  "mtr"
]
```

### Find your OpenStack resource names

If you are unsure of image, flavor, or network names, list them:

```bash
openstack --os-cloud openstack image list
openstack --os-cloud openstack flavor list
openstack --os-cloud openstack network list
```

### Get your SSH public key

```bash
cat ~/.ssh/id_rsa.pub
```

If you do not have an SSH key yet:

```bash
ssh-keygen -t rsa -b 4096 -C "your@email.com"
cat ~/.ssh/id_rsa.pub
```

Paste the output as the value of `ssh_public_key` in `terraform.tfvars`.

---

## 5. Deploy the VM

### Initialise Terraform

Downloads the OpenStack provider plugin. Run this once per project:

```bash
terraform init
```

Expected output:

```
Initializing the backend...
Initializing provider plugins...
- Finding terraform-provider-openstack/openstack versions matching "~> 1.54"...
- Installing terraform-provider-openstack/openstack v1.54.x...

Terraform has been successfully initialized!
```

### Plan

Preview what Terraform will create before applying:

```bash
terraform plan
```

Review the output carefully. You should see resources to be created:

```
Plan: 3 to add, 0 to change, 0 to destroy.
```

### Apply

Create the VM:

```bash
terraform apply
```

Type `yes` when prompted to confirm.

Terraform will provision the VM and print outputs when complete:

```
Apply complete! Resources: 3 added, 0 changed, 0 destroyed.

Outputs:

instance_id  = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
instance_ip  = "10.0.0.10"
floating_ip  = "203.0.113.10"
ssh_command  = "ssh baremetal@203.0.113.10"
```

> Cloud-init runs after the VM reaches ACTIVE state. Wait 2-3 minutes before connecting to allow packages to install.

---

## 6. Connect to the VM

Use the `ssh_command` from the Terraform output:

```bash
ssh baremetal@<ip-from-output>
```

The `mtr` package is pre-installed via cloud-init. Verify it:

```bash
mtr --version
```

---

## 7. Destroy the VM

To delete all resources created by Terraform:

```bash
terraform destroy
```

Type `yes` when prompted. This removes the VM and floating IP (if created).

---

## 8. Troubleshooting

### "Error: Error creating OpenStack server"

- Verify image, flavor, and network names match exactly what is in OpenStack
- Run `openstack image list`, `openstack flavor list`, `openstack network list` to confirm

### "Error: couldn't configure provider"

- Verify `~/.config/openstack/clouds.yaml` exists and the cloud name matches `cloud_name` in `terraform.tfvars`
- Test auth: `openstack --os-cloud openstack token issue`

### "The request you made needs authentication"

- Your password auth is being rejected. Use application credentials instead (see [Section 2](#2-set-up-openstack-authentication))
- If your cluster uses MFA or federated identity, password auth via API is not supported

### "Error: Invalid application credential"

- You must explicitly select a role (e.g. `member`) when creating the application credential in Horizon
- If that fails, ask your OpenStack admin to create the credential on your behalf:

```bash
openstack application credential create \
  --user <your-username> \
  --user-domain <your-domain> \
  --role member \
  terraform-deploy
```

### VM is ACTIVE but SSH times out

Cloud-init is still running. Wait 2-3 minutes and try again. You can monitor progress from the Horizon console log.

### How to re-run without destroying

Terraform is idempotent — if the VM already exists with the same name, running `terraform apply` again will detect no changes and do nothing.
