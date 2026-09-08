# Shared encrypted assets

Standard pattern: keep reusable SOPS-encrypted assets in `~/.chezmoi/secrets/`, named `*.sops.yaml` (or another deliberate SOPS-supported format). Git distributes ciphertext; `.chezmoiignore` excludes this whole directory from home-directory deployment. Consumers read from the checkout and explicitly decrypt/apply after operator approval. No automatic decryption or deployment hooks are configured.

## Decryption key

Install SOPS, age and the 1Password CLI through approved tooling. Obtain an authorized 1Password session or separately provisioned `OP_SERVICE_ACCOUNT_TOKEN`. The shared age private key is stored at:

```text
op://Local Dev/ed3dnet ed3d.net localdev age key/password
```

In an authorized shell, without shell tracing enabled:

```sh
# Do not enable set -x or print the resulting variable.
SOPS_AGE_KEY="$(op read 'op://Local Dev/ed3dnet ed3d.net localdev age key/password')" && export SOPS_AGE_KEY
```

Stop if the lookup fails; do not continue with an empty key. Do not read token files or source a credential-loading shell profile without permission. Never put the age private key, service-account token, or decrypted secret in Git, a chezmoi template, logs, or command arguments. Unset `SOPS_AGE_KEY` when finished. An approved direnv loader may perform the same lookup; inspect it before allowing execution.

The public age recipient is `age127lfjxqr3t58rvn0x79cu6w3x0t9ztxw6rwctnrk7amhjpyja43s49vnnp`. It is safe to include in encryption policy; it cannot decrypt files. The private key stays in 1Password. Anyone able to obtain that private key and this repository can decrypt these shared assets, so scope access deliberately.

## Existing asset: Cloudflare

`cloudflare-api-token.sops.yaml` is the canonical encrypted Kubernetes Secret for the shared Cloudflare integration. Its readable metadata names Secret `cloudflare-api-token` in namespace `cert-manager`; `stringData.api-token` is encrypted. A cluster also requires a namespace-adjusted copy in `external-dns`. The token's actual zone permissions must be confirmed before use on a new machine.

After validating the destination context and obtaining deployment approval, decrypt directly into the consumer with pipeline failure handling:

```sh
set -o pipefail
sops -d "$HOME/.chezmoi/secrets/cloudflare-api-token.sops.yaml" |
  kubectl --context localdev apply -f -
```

This applies only the cert-manager copy. Follow the [K3s guide](../knowledge-base/local-k3s-development-cluster.md) for namespace prerequisites and the second copy. Do not print plaintext for inspection. Kubernetes stores its own Secret copies; Git synchronization does not rotate deployed credentials. Update both copies during rotation and restart environment-variable consumers such as ExternalDNS as appropriate.

## Add or rotate an asset

1. Decide whether the value truly should be shared. Keep per-cluster application passwords in their owning infrastructure repository unless deliberately sharing them. Shared encryption keys do not imply shared application identities.
2. Prefer editing an existing encrypted file with `sops edit <absolute-path>`; existing SOPS metadata carries its recipient/encryption policy. Use a trusted editor and account for its plaintext temporary files, swap files and backups.
3. For a new file, explicitly provide the recipient and encryption scope, or introduce a reviewed creation rule. This checkout does not currently supply a `.sops.yaml` creation policy. The admin repository's `k8s/` creation rule does not cover `~/.chezmoi/secrets/`. For Kubernetes YAML matching the current pattern, specify `--age <public-recipient>` and `--encrypted-regex '^(data|stringData)$'`. Other formats need an appropriate policy; do not assume fields outside this regex are encrypted.
4. Verify every sensitive field is encrypted and SOPS metadata is present before staging. Metadata, names, annotations and comments remain readable in the Kubernetes pattern. Encrypt before writing into Git-tracked locations; avoid plaintext intermediate files.
5. Review and commit only intended ciphertext and documentation. Pull before editing and push afterward. Coordinate rotation with all consuming machines; old ciphertext remains decryptable in Git history with the corresponding key, so revocation must happen at the credential issuer too.

Moving an existing encrypted file is a byte-preserving operation and does not require decryption. Do not rename fields or edit encrypted metadata by hand: use SOPS when changing its contents. Encryption-at-rest does not authorize automatic use, make public metadata private, or replace destination RBAC, secure backups and transport security.
