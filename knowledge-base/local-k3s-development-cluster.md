# Setting up an independent local K3s development cluster

Grounded: 2026-09-08. Reference implementation: `~/system-admin/this-server/` on Zagreus, in system-admin commit `be695d97b0218c5816a0860b14db4d8fdeed126a`. This guide describes inspected repository configuration, **not a live cluster audit or a tested fresh installation**. Upstream K3s requirements, configuration, networking, and registry documentation were also consulted on that date.

## Purpose and agent contract

Build an independent, single-node Linux development environment with Kubernetes, private network access, DNS/TLS automation, and selected shared development services. Hermes and Zagreus are examples of independent peers, not members of one cluster; their databases and persistent volumes are not replicated between machines.

This is an operational guide, not provisioning automation. It lives in the chezmoi source checkout and is excluded from deployment. Pulling dotfiles does not install K3s, change host services, create DNS records, or deploy workloads. The consuming agent must inspect the destination, resolve prerequisites with the operator, present a plan, and obtain approval before installation, service changes, trust changes, or resource deployment.

Do not copy a complete working machine blindly. Do not deploy every file under `k8s/` recursively. Select components explicitly, adapt identities and credentials, and apply in dependency order. Never read token files or decrypt secrets merely to document the setup; never print resolved credentials. Existing `.local` access restrictions and unmanaged shell conventions still apply.

## 1. Distinguish the layers

| Layer | Components | Responsibility |
|---|---|---|
| Host system services | Linux, Tailscale daemon, K3s service and its container runtime, host firewall/routing, disks/mounts, trust store | Prerequisites outside the manifest repository; require host administration |
| Base cluster infrastructure | K3s API/control plane and node, cluster DNS, Traefik ingress, ServiceLB, local-path provisioning | Makes Kubernetes and the reference ingress/storage patterns work |
| Additional cluster infrastructure | cert-manager, ExternalDNS; optionally observability and CloudNativePG operator | Installed as cluster resources; not separate host daemons |
| Optional shared development services | MinIO S3, Zot registry, Temporal, Grafana/Prometheus/Loki/Tempo/Alloy, optional Infisical | Services consumed by projects; select according to need and capacity |
| Discovery metadata | `devenv-meta` ConfigMap and derived Secrets | No running application; publishes contracts for selected services |
| Project application workloads | Project images, deployments, workers, databases, secrets, namespaces, RBAC | Separate project lifecycle; **not installed by this bootstrap** |

A healthy K3s node does not require MinIO, Temporal, a registry, observability, or Infisical. The complete reference development platform includes several of these for convenience. CloudNativePG installs an operator, not a database: consuming services create their own `Cluster` resources. Temporal includes its own PostgreSQL dependency but not your projects' workflow workers.

The inspected repository contains infrastructure and shared-service manifests, not downstream project deployments. `k8s/dns-tls/manifests/90-hello.yaml` is a disposable ingress validation application, not a prerequisite. Its current production Let's Encrypt annotation should be changed to staging or an approved private issuer for testing.

Infisical is documented as not deployed on Zagreus. Its manifests describe an optional **in-cluster** application backed by CNPG, not a host systemd service. Directory presence is not proof a service is running.

## 2. Decisions and prerequisites before changing a machine

Record the following with the operator:

- **New peer or replacement?** Prefer a new peer identity. Reusing an existing identity requires an explicit DNS/controller handover and data migration plan.
- **Linux execution host:** K3s runs on Linux. A macOS development machine can be a client or use an explicitly provisioned Linux VM; this repository does not define VM networking, lifecycle, or storage.
- **Capacity:** upstream minimum for a K3s server is 2 CPU cores and 2 GB RAM, excluding workload requirements. The full stack needs substantially more. Choose resources based on chart requests, runtime overhead, retention, builds, and application demand; the large Zagreus workstation is not a minimum specification.
- **Storage:** choose an SSD-backed persistent data location and filesystem before installation. Confirm free capacity, inode headroom, mount ordering, and backups. Use UUID/labels for mounts, not unstable device numbering. Do not assume another machine has Zagreus's extra-storage disk.
- **Networking:** establish Tailscale membership, stable machine identity, MagicDNS resolution, and tailnet grants/ACLs allowing intended clients. Check pod/service CIDRs against LAN/VPN/other cluster routes. Default K3s ranges are `10.42.0.0/16` and `10.43.0.0/16`.
- **Ports and exposure:** check conflicts on 80/443, Kubernetes API 6443, and K3s internal ports. Default Traefik ServiceLB uses host ports 80/443. A DNS name pointing to Tailscale is **not a firewall**: verify ingress, NodePorts, host listeners, and the API are not reachable from unintended LAN/public interfaces. Keep the firewall and deliberately configure/test it rather than blindly disabling it. Never expose Flannel VXLAN UDP 8472 publicly. Additional multi-node ports are outside this single-node design.
- **DNS:** choose an operator-controlled Cloudflare zone, unique per-machine suffix, and unique ExternalDNS TXT owner. Obtain appropriate Cloudflare token permissions and ACME account email. DNS records targeting tailnet names should be DNS-only, not Cloudflare-proxied.
- **Secrets:** authorized 1Password CLI session/service-account environment, SOPS, and age. Access to the shared encryption key does not by itself justify reusing another cluster's application passwords or CA private key.
- **Tools:** K3s/kubectl, Git, curl, DNS/HTTPS diagnostics, 1Password CLI, SOPS and age; direnv is optional for the documented environment loader. Prefer mise for declared tools and approved OS packages for system services. A container builder/push client is a separate decision: Docker/Podman are not prerequisites for K3s and were not installed on the reference host.
- **Scope and durability:** agree on which shared services to install, persistence/retention, backup destination, restore test, and whether this is disposable development data. Single-node means no high availability.

Do not overwrite existing kubeconfig, systemd units, firewall rules, registry configuration, CA files, shell startup, or mounts. Back up affected existing files and symlink targets, using private operation directories under `~/.chezmoi-backups/` for cutovers. Keep a working administrative connection open.

## 3. Obtain and adapt the reference manifests

The source is the administration notebook's `this-server/` subtree, **not this knowledge-base directory**. If absent on the new machine, obtain the reviewed manifests from the operator's administration repository through an approved channel. Do not assume `~/system-admin` exists everywhere or invent a clone URL. Keep machine-specific infrastructure in a separate reviewed checkout; chezmoi distributes this guide, not cluster state.

Read `this-server/AGENTS.md`, `docs/user-guide.md`, and each selected `k8s/<feature>/CLAUDE.md`, then inspect the manifests and scripts. Documentation has known drift (section 10). Revalidate chart repositories, versions, architecture support, and Kubernetes compatibility before installing; historical pins are evidence, not a recommendation to install outdated software indefinitely.

### Identity worksheet

| Setting | Reference value | New peer action |
|---|---|---|
| Host/node name | `zagreus` | Choose unique hostname |
| Public DNS suffix | `zagreus.ed3d.dev` | Choose `<machine>.<zone>` |
| Tailscale target | `zagreus.tail056dd.ts.net` | Use actual new MagicDNS hostname |
| ExternalDNS owner | `zagreus-k3s` | Choose unique owner; do not share with peers |
| Cloudflare zone filter | `ed3d.dev` | Use actual apex zone supported by provider discovery |
| Kube context | `localdev` | Preserve convention only if unambiguous; otherwise use a distinct context |
| Local CA | Legacy `daedalus`-named CA | Deliberately choose new CA or approved shared trust domain |
| Application passwords | Per-Zagreus encrypted values | Mint fresh for independent peer |

Inspect all manifests, ConfigMaps, scripts and documentation for old suffixes, email, owner IDs, host IPs, registry endpoints, certificate names, and secret references. Update service URLs consistently, including `devenv-meta`. Do not use indiscriminate replacement over encrypted SOPS files. Preserve encryption validity by editing through SOPS.

The reference ExternalDNS uses apex `domainFilters: [ed3d.dev]` because subdomain-only filtering failed zone discovery. That apex filter is broad: pair it with strict source annotations, unique ownership, least-privilege API access, and review of generated endpoints. `policy: sync` deletes owned DNS records when their sources disappear. Separate owners prevent peer controllers from managing one another's owned records, but are not a substitute for sensible source and domain scope.

## 4. Establish host services and base K3s

The notebook has **no complete host installer, systemd unit, firewall policy, or K3s configuration file**. Reconstruct these using current upstream documentation and explicit operator decisions; applying YAML cannot fill this gap.

1. Inspect OS/architecture, existing Kubernetes/container services, routes, listeners, storage and mounts. Confirm this is the intended machine.
2. Install and enroll Tailscale through approved official instructions. Verify the machine and a separate client can resolve and reach one another; do not assume enrollment implies all needed ACL access.
3. Select and pin a compatible K3s version. The inspected reference documents `v1.34.5+k3s1`; review security and compatibility before retaining that pin. Download and inspect the official installer before approved execution rather than blindly piping it into a privileged shell.
4. Record persistent settings in `/etc/rancher/k3s/config.yaml` where appropriate: node identity, chosen data location, network ranges and any API TLS SANs for approved remote access. Merge existing settings. The upstream installer can replace previously supplied service arguments when rerun; keep the full configuration accounted for.
5. Install one K3s **server with scheduling enabled** (server plus agent on the same node). Retain the reference's Traefik and local-path facilities. K3s supplies its runtime; installing Docker is unnecessary. A different ingress/CNI/storage design requires deliberate adaptation of the manifests.
6. Configure host networking/firewall for the intended private access model. K3s/ServiceLB exposure may involve more interfaces than the Tailscale DNS target suggests. Test both permitted access and forbidden access.
7. Provision a private kubeconfig. `/etc/rancher/k3s/k3s.yaml` is administrative material: do not commit it, make it world-readable, or overwrite an existing `~/.kube/config`. Merge with existing contexts using a backed-up workflow. Use mode 0600. Remote clients need a reachable server address and valid TLS SANs; never solve this by disabling TLS verification.
8. Verify base readiness before additional charts:

   ```sh
   sudo systemctl is-active k3s
   kubectl --context localdev get nodes -o wide
   kubectl --context localdev get pods -A
   kubectl --context localdev get storageclass
   kubectl --context localdev -n kube-system get services
   ```

   Substitute the agreed context in every command. Confirm node Ready, system pods healthy, cluster DNS working, Traefik available, and `local-path` present. Validate a disposable PVC with operator approval; an API object alone does not prove storage works.

The reference registry also documents `fs.inotify.max_user_instances >= 1024`, persisted under `/etc/sysctl.d/99-inotify.conf`. Check and merge this only if deploying Zot and necessary for the selected version. It is a host setting, not a Helm value.

## 5. Secrets, DNS and certificate foundations

### Secret handling

The reference `.envrc` retrieves `SOPS_AGE_KEY` from the 1Password item `op://Local Dev/ed3dnet ed3d.net localdev age key/password` and selects kubeconfig. Inspect it before `direnv allow`; it executes code and makes an external secret lookup. A separately provisioned authorized 1Password session/token must already be available. Do not source the live `.zshrc` or read token files as a shortcut.

`.sops.yaml` encrypts `data` and `stringData` in `k8s/**/*.sops.yaml`; metadata remains readable. For a new peer, generate fresh cluster application credentials, encrypt before committing, and preserve expected Secret names/keys. The reference age key is shared between peers for encryption-at-rest only. Sharing an encryption key does not synchronize databases or make application passwords interchangeable.

Use decrypted data only in a reviewed in-memory pipeline after approval, for example:

```sh
set -o pipefail
sops -d k8s/<feature>/secrets/<name>.sops.yaml |
  kubectl --context localdev apply -f -
```

This is a pattern, not a runnable literal command. Do not log plaintext, redirect it to ordinary files, or expose it in process arguments. SOPS protects the Git source, not automatically Kubernetes datastore contents: separately review K3s secrets-at-rest encryption, RBAC, administrative kubeconfig access, and backup protection.

### DNS/TLS installation order

1. Create `cert-manager` and `external-dns` namespaces explicitly before their Secrets.
2. Provision `cloudflare-api-token` with key `api-token` in **both** namespaces. The source encrypted Secret names `cert-manager`; prepare the second copy with a reviewed namespace-only transformation. `kubectl -n` does not override contradictory YAML metadata. Never dump the token to inspect it.
3. Confirm token access includes DNS record edits and the zone-read/discovery permissions required by the selected Cloudflare integrations, scoped to the intended zone. Resolve missing privileges with the operator, not by defaulting to unrestricted credentials.
4. If using `local-dev-ca`, provision the CA keypair Secret in `cert-manager`. Decide whether to mint a new peer CA or share the existing trust domain. Never casually copy a CA private key; only distribute its public certificate to clients.
5. Apply `k8s/dns-tls/manifests/10-cert-manager.yaml` as a K3s HelmChart. Wait for CRDs, controllers, and **webhook readiness**, not merely a running main pod.
6. Apply `15-clusterissuer.yaml` after adapting ACME email and settings. It defines production and staging Let's Encrypt DNS-01 issuers plus `local-dev-ca`.
7. Apply adapted `20-external-dns.yaml`, then review/apply `21-external-dns-rbac-patch.yaml` as required by the selected version. Check controller permissions and logs. This patch is omitted from the older feature README-style instructions.
8. Verify with a deliberately disposable standard Ingress, preferably staging/private CA initially. Confirm the CNAME targets the new Tailscale hostname, ownership TXT records identify the correct controller, and the Certificate becomes Ready. DNS propagation is asynchronous; diagnose events and authoritative/public resolution rather than assuming a fixed delay guarantees success.

The reference uses Cloudflare **DNS-01**, which does not require public inbound HTTP access. Its standard Ingresses mostly use Let's Encrypt production even though traffic is private. Staging certificates are intentionally untrusted; private CA certificates require explicitly installing the public root into each relevant client/application trust store. A public DNS record can reveal a service hostname even when the service is tailnet-only.

A Traefik `IngressRoute` is not equivalent to a standard `Ingress` for automation. The reference Temporal gRPC route uses an explicit `Certificate` and an annotated `ExternalName` Service for DNS, with an `IngressRoute` forwarding h2c to the backend. Follow `k8s/temporal/manifests/30-grpc-ingress.yaml`; do not assume cert-manager/ExternalDNS infer everything from the route CRD.

## 6. Select and install shared development services

### Chart lifecycle convention

Use **K3s `helm.cattle.io/v1` HelmChart resources**, not direct `helm install/upgrade` against the cluster. Objects live in `kube-system`, with `targetNamespace` selecting the workload namespace. The Helm controller creates `helm-install-<name>` Jobs. Inspect chart/job status, events and logs; a successful `kubectl apply` is only acceptance of desired state.

Within a component, create namespace, provision Secrets, and apply numeric-order manifests. Do not bulk-apply the entire tree. Wait for required CRDs/webhooks/storage before dependent objects.

### Dependency-aware sequence

1. **Optional observability base:** create `monitoring`, provision encrypted Grafana admin credentials, apply `k8s/observability/manifests/10-kube-prometheus-stack.yaml`. Wait for readiness and monitoring CRDs. Then install Loki, Tempo and Alloy in numeric order, including Alloy's supplemental RBAC in `40-alloy.yaml`.
2. **Optional CNPG:** apply `k8s/cloudnative-pg/manifests/10-cloudnative-pg-operator.yaml`, and wait for operator/webhook/CRDs. The checked-in chart enables PodMonitor, so kube-prometheus-stack must precede it. If intentionally omitting monitoring, adapt that setting and any other monitoring resources rather than treating observability as inherently required for PostgreSQL.
3. **Optional Zot and MinIO:** these do not depend on CNPG; deploy after their namespace/secret/storage/ingress prerequisites are ready. They may be installed independently of one another.
4. **Optional Temporal:** create namespace and DB credentials, apply `10-temporal-db.yaml`, wait for the CNPG `temporal-db` Cluster to be Ready, then apply `20-temporal.yaml` and `30-grpc-ingress.yaml`. Inspect schema initialization jobs and frontend/UI health before declaring success.
5. **Discovery metadata last:** adapt `k8s/devenv-meta/manifests/20-configmap.yaml` to the services actually installed and verified. Review `deploy.sh` before running: it derives Grafana/MinIO Secrets from canonical SOPS files. If those services are omitted, adapt/omit the relevant metadata and derivation; do not publish nonexistent endpoints.

### Service behaviors and constraints

| Service | Reference contract | Important choices |
|---|---|---|
| MinIO | `s3.<suffix>` API, `s3-console.<suffix>` UI, in-cluster `minio.minio.svc.cluster.local:9000` | Single Deployment with `Recreate`, RWO local PVC, 60Gi; fresh credentials; pin/review `pgsty/minio:latest` |
| Zot | `registry.<suffix>` registry and UI | No authentication in reference; tailnet access is the security boundary; 20Gi; confirm actual rendered Service name |
| Temporal | `temporal.<suffix>` UI, `temporal-grpc.<suffix>:443` TLS gRPC, in-cluster `temporal-frontend.temporal.svc.cluster.local:7233` | CNPG 20Gi with `temporal` and `temporal_visibility`; 32 history shards is an immutable initialization choice; workers deployed separately |
| Observability | `grafana.<suffix>` UI; Prometheus metrics, Loki logs, Tempo traces, Alloy collection/OTLP | Logs collected automatically from pods; traces require instrumentation/exporter config; metrics require appropriate scrape configuration; restrict ingestion/access |
| CNPG | Operator and CRDs in `cnpg-system` | No automatic application DB or backup policy; each service owns its database resources |
| devenv-meta | Endpoint ConfigMap and selected derived credentials | No workload; cross-namespace consumers need explicit RBAC or controlled replication |

Reference observability requests: Prometheus 10Gi, Grafana 1Gi, Alertmanager 1Gi, Loki 10Gi, Tempo 5Gi (27Gi total), with documented 7-day retention for metrics/logs/traces. Together with MinIO, Zot and Temporal, the main selected stack requests about **127Gi**, excluding images, logs outside those stores, runtime/database overhead, backups and downstream applications. PVC requests are not a complete capacity plan or necessarily hard disk quotas.

For Zot, configure `/etc/rancher/k3s/registries.yaml` only after the new endpoint and TLS work. This is **host configuration**, outside Kubernetes manifests. Merge existing settings, configure a trusted `ca_file` where needed, and restart K3s in an approved maintenance window. Configure every node that pulls images, including a schedulable server. Do not disable certificate verification. Containerd normally tries an implicit default registry endpoint after mirrors; a mirror entry is not an egress allowlist. Avoid a bootstrap dependency in which K3s can only pull the registry's own image from a registry that has not started.

A registry does not build images. Choose and install an approved build/push tool separately, publish a disposable image, and verify a pod can pull it through the intended node configuration.

## 7. Optional applications are a separate operation

Do not install these merely because their directories are present:

- **Infisical:** optional in-cluster application with a CNPG database, not a base K3s dependency. It has additional secret and encryption-key lifecycle requirements. Losing/changing the encryption key can make stored data unusable. Its reference DB request is another 10Gi.
- **Project workloads:** install from their own reviewed repositories after infrastructure acceptance. Give each project appropriate namespaces, RBAC, secrets, quotas, PVCs, ingress/DNS ownership, and application-specific backup policy. Provision Temporal workers, S3 buckets/access policies, and database roles separately. Do not hand every project administrative kubeconfig or shared root credentials by default.

## 8. Acceptance checks and handoff

Verify on the destination rather than treating this guide as evidence of runtime success:

- Host service survives restart; node Ready; system pods healthy; DNS and storage tests pass.
- Approved tailnet clients can reach selected endpoints, validate TLS, and authenticate where required. Test that unintended network paths cannot reach the unauthenticated registry or other sensitive listeners.
- ExternalDNS records use the new target and owner; no peer records were modified. Check cert-manager Certificate/Issuer status and renewal-related events.
- Helm install Jobs complete; all selected deployments/statefulsets are ready; PVCs are bound and on the intended disk.
- MinIO: approved disposable bucket/object round trip. Zot: push/pull disposable image. Temporal: TLS gRPC connection and a disposable workflow with a separately supplied worker. Do not confuse UI availability with backend functionality.
- Observability: confirm actual targets, pod logs, and a known test trace; installed collectors alone do not establish data flow.
- Verify actual Service names before publishing internal URLs. Cross-namespace Secret access is explicitly authorized or replicated; do not grant blanket access for convenience.
- Publish only installed, healthy services in `devenv-meta` and `docs/user-guide.md`. Record destination-specific context, URLs, trust procedure, versions and remaining gaps. The reference contract requires updating `docs/user-guide.md` whenever consumer-visible functionality changes.
- Re-run the reviewed metadata derivation after rotating Grafana/MinIO credentials; updating canonical SOPS files alone leaves derived Secrets stale.
- Record backup locations and perform a restore test appropriate to retained data. Git synchronization is not a data backup.

Useful read-only diagnostics (use the agreed context):

```sh
kubectl --context localdev get nodes
kubectl --context localdev get pods -A
kubectl --context localdev get pvc -A
kubectl --context localdev -n kube-system get helmcharts
kubectl --context localdev get certificates -A
kubectl --context localdev get clusterissuers
kubectl --context localdev -n registry get services
kubectl --context localdev -n kube-system logs job/helm-install-<name>
```

The final command is a placeholder. Review logs before sharing; runtime logs can contain private data.

## 9. Persistence, upgrades and recovery

All reference persistent services use single-node `local-path`. This is not distributed storage or high availability. Verify the actual StorageClass reclaim/expansion settings. The reference documents non-expandable storage; do not assume editing a PVC request will grow it. Plan explicit migration when resizing. Deleting a PVC, namespace, database Cluster, HelmChart, or uninstalling K3s can destroy data or trigger cleanup.

The notebook does not supply a complete backup/restore procedure. Establish application-consistent database and object-store backups, configuration/secret recovery, a protected off-host destination and tested restore sequence. CNPG installation alone does not configure backups. Copying manifests, encrypted passwords and public CA certificates to a replacement does not copy persistent application data. Protect the K3s datastore and server token as required by the chosen upstream recovery procedure; never commit either.

For chart failures, inspect HelmChart status, install Job logs, events, CRDs/webhooks, image pulls, PVCs and Secret presence before retrying. Finalizer removal is a **last-resort recovery step**, not a routine bootstrap command: understand why cleanup stalled and what resources/data would be orphaned before approving it. Do not blindly paste a finalizer-removal command from older notes.

Upgrade one dependency layer at a time after checking compatibility and backups. Revalidate chart repositories and pins, allow readiness checks to complete, and retain recovery instructions. Changing host registry settings restarts the single node and interrupts workloads. With ExternalDNS `sync`, resource deletion can also delete DNS; teardown and replacement require planned controller/ownership handling.

## 10. Known source gaps and discrepancies

These findings were obtained from repository inspection, not live verification:

1. **Host bootstrap is missing:** installer choices, K3s flags, Tailscale enrollment, firewall rules, data-root placement, registry file contents and user systemd units are outside the checkout. Do not claim this is a self-contained installer.
2. **DNS instructions omit resources:** include the chosen local CA Secret and review `21-external-dns-rbac-patch.yaml`; feature instructions alone omit them. Wait for the webhook as well as pods.
3. **Temporal feature instructions omit external gRPC:** include `30-grpc-ingress.yaml` if publishing that endpoint.
4. **Registry metadata is inconsistent:** user guide/devenv-meta advertise `docker-registry.registry.svc.cluster.local:5000`, but the Ingress targets Service `zot` and no inspected manifest defines `docker-registry`. Verify rendered Services and correct metadata, rather than publishing the stale URL.
5. **Optional application presence is not deployment evidence:** Infisical has checked-in manifests but is documented as undeployed. Treat it as a separate operator-approved installation, not an available endpoint.
6. **Chart sources need review:** Zot's checked-in chart repository uses HTTP; select a verified trusted distribution source before deployment. Loki docs warn of a chart repository migration while the manifest still uses the older URL. Do not assume either location/version remains valid.
7. **Historical pins are not a compatibility guarantee:** inspected versions include cert-manager chart `v1.17.2`, ExternalDNS chart `1.20.0`, kube-prometheus-stack `82.10.3`, Loki `6.54.0`, Tempo `2.0.0`, Alloy `1.6.2`, CNPG chart `0.27.1`, Zot image `v2.1.15`, and Temporal chart `1.0.0-rc.2`. MinIO and the hello sample use `latest`. Distinguish chart versions from application versions and verify supported combinations.
8. **Private access is intent, not demonstrated enforcement:** Tailscale CNAMEs do not prove firewall or listener isolation. Audit actual host/Kubernetes exposure before relying on an unauthenticated endpoint.
9. **Old machine notes drift:** root system-admin instructions still describe Dropbox dotfiles; this machine has migrated to chezmoi. Do not use that historical note to overwrite current dotfile conventions. The `daedalus` CA name is a retained historical identity, not the new machine's name.

## Source map and upstream references

All local paths below are relative to the reference `~/system-admin/this-server/`. They are navigation references, not assumed files on every machine:

- `AGENTS.md`: architecture, peer identity, HelmChart contract, full dependency order and excluded services.
- `docs/user-guide.md`: downstream consumer contract; cross-check against manifests and actual deployed services.
- `.envrc`, `.sops.yaml`: approved environment-loader and encrypted source conventions; inspect before executing.
- `k8s/dns-tls/CLAUDE.md` and `manifests/{10-cert-manager,15-clusterissuer,20-external-dns,21-external-dns-rbac-patch,90-hello}.yaml`: DNS/TLS and validation.
- `k8s/observability/CLAUDE.md` and `manifests/`: monitoring/storage topology and collector permissions.
- `k8s/cloudnative-pg/CLAUDE.md` and `manifests/10-cloudnative-pg-operator.yaml`: operator/PodMonitor dependency.
- `k8s/{minio,registry,temporal}/CLAUDE.md` and corresponding `manifests/`: optional shared-service deployment and persistence.
- `k8s/temporal/manifests/30-grpc-ingress.yaml`: explicit DNS/certificate/gRPC routing pattern.
- `k8s/devenv-meta/{CLAUDE.md,deploy.sh,manifests/20-configmap.yaml}`: derived credentials and endpoint publication.
- `k8s/infisical/`: optional in-cluster application, not automatic installation scope.

Official K3s references consulted for portable host guidance:

- [Requirements](https://docs.k3s.io/installation/requirements): resource minima, Linux/architecture and network requirements.
- [Configuration](https://docs.k3s.io/installation/configuration): installer/service configuration persistence and config-file behavior.
- [Networking services](https://docs.k3s.io/networking/networking-services): default Traefik/ServiceLB host-port behavior.
- [Private registry configuration](https://docs.k3s.io/installation/private-registry): host registry file, CA trust, restarts and fallback behavior.

Before execution, also consult current official Tailscale, cert-manager/Cloudflare, selected chart, K3s backup/restore and secrets-encryption documentation for decisions that this reference cannot settle. The consuming agent must resolve those with the operator rather than silently inventing destination configuration.
