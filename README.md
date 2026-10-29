# Vault SPIFFE Demo

This demo deploys **Vault Enterprise** inside a local **kind** (Kubernetes in Docker) cluster using **Helmfile**. Terraform configures X.509 and JWT **SPIFFE Verifiable Identity Documents (SVIDs)**. Workload pods authenticate with Kubernetes service accounts, retrieve and save their SVIDs, then inspect the X.509 certificate or log back into Vault using the JWT. No SPIRE agent, SPIFFE Workload API, or CSI driver is required.

## Prerequisites

Ensure you have the following CLI tools installed:

- [kind](https://kind.sigs.k8s.io) (Kubernetes in Docker)
- [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/) (Kubernetes CLI)
- [helm](https://helm.sh) (Kubernetes package manager)
- [helmfile](https://helmfile.readthedocs.io/en/latest/) (Declarative Helm release manager)
- [vault](https://developer.hashicorp.com/vault/install)
- [jq](https://jqlang.org/) (JSON processor)
- [Terraform](https://developer.hashicorp.com/terraform/install) (Vault configuration)
- [OpenSSL](https://www.openssl.org/) (certificate inspection)

You will also need a container runtime:

- [docker](https://www.docker.com) or [podman](https://podman.io)

A valid **Vault Enterprise license** is required. The deployment uses the Vault Enterprise image and reads the license from the `VAULT_LICENSE` environment variable.

### With `nix` and `direnv`

If you are using Nix with flakes, you can enter a shell with all required tools:

```bash
nix develop
```

If you use `direnv`, run `direnv allow` to automatically load the dev environment.

## Setup the Environment

### 1. Create the kind Cluster

Create the local Kubernetes cluster using the provided configuration:

```bash
kind create cluster --config kind-config.yaml
```

### 2. Deploy Vault via Helmfile

Export the contents of your license file in the same shell that runs `helmfile apply`, replacing the path below with your license file's location:

```bash
export VAULT_LICENSE="$(cat /path/to/vault.hclic)"
helmfile apply
```

`VAULT_LICENSE` must contain the license itself, not the file path. Helmfile fails if the variable is missing or empty. The setup chart creates a Kubernetes Secret from it, which Vault mounts to load the license. Do not commit the license to the repository.

### 3. Verify the Deployment

Check that Vault is running and the Gateway components are ready:

```bash
watch kubectl get pods -A
```

The Vault pod is expected to show `Running` with `0/1` containers ready at this stage. Vault becomes ready only after initialization and unsealing in the next step. Press Ctrl+C to stop watching and continue.

### 4. Initialize and Unseal Vault

Once Vault is running and the Gateway is available, initialize it with one unseal key and a threshold of one for this local demo:

```bash
export VAULT_ADDR=http://localhost:8200
vault operator init -n 1 -t 1 -format json | tee keys.json
```

Initialize Vault only once. The generated `keys.json` contains the unseal key and initial root token; keep it private and do not commit it. The single-key configuration is for this demo only, not production.

Unseal Vault using the first key:

```bash
vault operator unseal $(jq -r '.unseal_keys_b64[0]' keys.json)
```

Repeat the unseal command after Vault restarts; do not initialize it again or overwrite `keys.json`.

### 5. Configure Identity Issuance and Kubernetes Authentication

Log in with an administrative Vault token, then apply the Terraform configuration:

```bash
vault login
export TF_VAR_vault_address="$VAULT_ADDR"
terraform -chdir=config init
terraform -chdir=config apply
```

This enables `auth/kubernetes/` with roles named `x509-demo` and `jwt-demo`. Each role accepts only its matching service account in the `default` namespace and grants access to that workload's X.509 and JWT SVID issuance endpoints. Vault uses its own in-cluster service account to call the Kubernetes TokenReview API; the Helm chart grants it `system:auth-delegator` permissions. No reviewer token needs to be copied into Terraform.

Terraform also configures the `pki/` secrets engine with a Vault-generated CA, the `spiffe/` JWT-SVID issuer for `example.org`, and two SPIFFE auth mounts: `auth/spiffe-cert/` for certificate login and `auth/spiffe-jwt/` for JWT login. JWT login requires audience `vault`. The JWT auth mount uses a static trust bundle fetched at apply time; reapply Terraform after signing-key rotation to refresh it.

## Run the Examples

Each example runs a Vault client that logs in with its Kubernetes service account and saves an SVID under `/svid-data`. The X.509 example prints the public certificate for inspection, without certificate login. The JWT example unsets the bootstrap token and logs back in using the JWT-SVID, printing the resulting policies without exposing tokens.

Both containers use only the bundled Vault CLI, with no package downloads, and work with the existing HTTP listener. They run the demo once, then stay running for inspection. SVIDs and tokens are not renewed. Files are stored in memory-backed volumes and disappear when the pod is deleted. Keep JWTs and Vault tokens private.

### Example 01: X.509-SVID

Deploy the certificate example using the existing HTTP endpoint. No TLS listener or server-CA Secret is needed:

```bash
kubectl apply -f examples/01-x509-svid.yaml
kubectl logs -f x509-demo
```

The pod uses service account and Kubernetes auth role `x509-demo` to authorize issuance. It requests an X.509-SVID for `spiffe://example.org/ns/default/sa/x509-demo`, saves the public certificate and CA, and discards the bootstrap token. It does not save the private key or perform SPIFFE certificate login; that login would require TLS.

Files saved in the pod:

- `/svid-data/svid.pem`: X.509-SVID certificate.
- `/svid-data/bundle.pem`: SVID issuing CA certificate.

Inspect the certificate and SPIFFE URI SAN:

```bash
kubectl exec x509-demo -- cat /svid-data/svid.pem \
  | openssl x509 -noout -issuer -ext subjectAltName
```

### Example 02: JWT-SVID

The JWT example works with the existing HTTP listener:

```bash
kubectl apply -f examples/02-jwt-svid.yaml
kubectl logs -f jwt-demo
```

The pod uses service account and Vault role `jwt-demo`. It requests a JWT-SVID for `spiffe://example.org/ns/default/sa/jwt-demo` with audience `vault`, then sends it in the `Authorization: Bearer` header to `auth/spiffe-jwt/login`.

Files saved in the pod:

- `/svid-data/svid.jwt`: JWT-SVID.
- `/svid-data/vault-token`: token returned by the SPIFFE login.

Read the JWT from the pod and decode its payload locally, without entering the container's shell:

```bash
kubectl exec jwt-demo -- cat /svid-data/svid.jwt \
  | jq -R 'split(".")[1]
    | gsub("-"; "+") | gsub("_"; "/")
    | . + ("=" * ((4 - length % 4) % 4))
    | @base64d | fromjson'
```

This prints the JWT claims but does not verify the signature. Avoid sharing sensitive claims in logs.

## Clean Up

Delete the demo pods and their service accounts:

```bash
kubectl delete --ignore-not-found -f examples/01-x509-svid.yaml
kubectl delete --ignore-not-found -f examples/02-jwt-svid.yaml
```

To delete the kind cluster completely:

```bash
kind delete cluster --name vault-spiffe-demo
```
