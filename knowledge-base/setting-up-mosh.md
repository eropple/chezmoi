# Setting up Mosh

Grounded: 2026-09-10, from live diagnosis and a firewall repair on **odysseus**. The persistent fix was applied and its live rules verified. A successful client connection after the fix was **not confirmed during the session**. This is an operational guide, not provisioning automation; chezmoi excludes this knowledge-base directory from deployment.

## Prerequisites and connection model

Mosh uses SSH to authenticate and launch `mosh-server`, then uses a separate UDP connection for the terminal session. Working SSH does **not** prove that Mosh's UDP path works.

- Install Mosh on the client and server using the appropriate trusted package manager, with operator approval. On Ubuntu/Debian the package is `mosh`; it supplies `mosh`, `mosh-client`, and `mosh-server`.
- Confirm SSH login works, the server executable is available, and the server has a working UTF-8 locale.
- Allow the chosen UDP port range through the actual host firewall and any intervening network controls. The normal Mosh server range is UDP `60000–61000`.
- Agree on LAN versus Tailscale access before opening ports. Restrict access to intended sources; do not disable the firewall or expose unrelated container services.

Basic checks:

```sh
command -v mosh mosh-client mosh-server ssh
mosh --version
locale
ip -brief address
ip route
```

On odysseus, Mosh `1.4.0` (Ubuntu package `1.4.0-1ubuntu5`) was already installed and `LANG=en_US.UTF-8` was valid. Reinstallation was not the solution.

## Recognizing the failure

Observed symptom: SSH authentication completed, then Mosh displayed a blank screen with “waiting to connect on 60001” and eventually timed out. The same client successfully used Mosh with other machines.

The server was listening on `172.27.4.40:60001`. During a synchronized client retry, a packet-header capture showed incoming UDP from `172.27.3.195` to that socket, with no Mosh replies.

Useful diagnostics, run on the server:

```sh
pgrep -a mosh
ss -ulnp
sudo ufw status verbose
sudo iptables -t filter -S
sudo iptables -t mangle -S
sudo iptables -t raw -S
sudo nft list ruleset
```

Capture during an actual retry, not after the client has timed out:

```sh
sudo timeout 60 tcpdump -nn -i any 'udp dst portrange 60000-61000 or udp src portrange 60000-61000'
```

This prints packet headers, not payload dumps. The broad filter can also include unrelated traffic using an ephemeral port in that range; match the client/server addresses when interpreting results.

- No incoming packets during a confirmed active retry: investigate the selected destination, client, routing, and upstream filtering.
- Incoming packets but no replies: inspect all host filtering stages, the listening socket, and server behavior.
- Replies leaving but no connection: investigate return-path filtering/routing and the client.

Do not infer reachability from an idle capture or from an inactive UFW alone.

## Odysseus root cause: a custom mangle-table firewall

UFW was inactive and the filter-table INPUT policy was ACCEPT. However, a separate custom firewall in the **mangle table** ran before those rules:

- `PREROUTING` jumped to `ODY_PRE`.
- `INPUT` jumped to `ODY_INPUT`.
- Both chains trusted internal/container interfaces and `tailscale0`, allowed established/related traffic, and allowed new SSH, Tailscale transport, DHCP, and ICMP traffic.
- Both ended in DROP, with no exception for Mosh UDP ports.

Thus LAN Mosh packets were dropped in `ODY_PRE` before reaching the server socket. Adding a UFW or filter-table ACCEPT rule would not override this earlier drop.

Persistent rule generation lives in:

- `/etc/odysseus-firewall/firewall.sh`
- `/etc/odysseus-firewall/firewall.conf`

The `odysseus-firewall` systemd service was enabled and active. The script generates IPv4 and IPv6 rules, validates both families, and applies its own chains without flushing unrelated rules. Do not replace this firewall wholesale or directly rewrite nftables tables managed by iptables-nft, Kubernetes, or Tailscale.

## Persistent LAN fix applied

Reference network values (inspect and adapt on other machines):

| Setting | Odysseus value |
|---|---|
| LAN interface | `enp1s0` |
| LAN subnet | `172.27.0.0/20` |
| Server LAN address | `172.27.4.40` |
| Allowed Mosh ports | UDP `60000:61000` |
| Server Tailscale address | `100.70.41.73` |

With operator approval, the following was added inside the script's existing `if [[ $family == 4 ]]; then` block, within the host-service exception block (`$chain != ODY_FWD`), before the DHCP exception:

```bash
# Allow LAN Mosh sessions to this host, not forwarded/container traffic.
printf -- '-A %s -i enp1s0 -s 172.27.0.0/20 -m addrtype --dst-type LOCAL -p udp --dport 60000:61000 -j RETURN\n' "$chain"
```

This generates an exception in **both `ODY_PRE` and `ODY_INPUT`**, not `ODY_FWD`. `RETURN` allows processing to continue through the remaining firewall stages; it does not bypass them. The exception is restricted to IPv4 LAN sources entering the specified interface and targeting a local address. It does not open IPv6 LAN access or forwarding.

Keep the current administrative SSH connection open. Before future changes, preserve the existing file and any symlink target in a unique private operation directory under `~/.chezmoi-backups/`, following the repository's backup contract. Review the exact diff, validate, then apply with approval:

```sh
bash -n /etc/odysseus-firewall/firewall.sh
sudo /etc/odysseus-firewall/firewall.sh check
sudo /etc/odysseus-firewall/firewall.sh apply
sudo iptables -t mangle -S ODY_PRE
sudo iptables -t mangle -S ODY_INPUT
systemctl is-enabled odysseus-firewall
systemctl is-active odysseus-firewall
```

For this incident, the original script was preserved at `/etc/odysseus-firewall/firewall.sh.before-mosh`. This is a historical recovery location, not the backup convention for future work. A user-owned staging copy was used because the file-edit tool could not directly write the root-owned script; the validated result was installed root-owned with mode `0755` before applying.

Verification completed during the repair:

- Shell syntax passed.
- IPv4 and IPv6 rule validation passed.
- Apply completed successfully.
- Both live chains contained the scoped UDP exception before their final DROP.
- The firewall service remained enabled and active.

**Still required:** retry the normal client command and confirm an interactive terminal. The session did not include that final confirmation or a reboot-persistence test.

To roll back this specific repair if necessary, restore the verified pre-change script with its ownership/mode, run `check`, then `apply`. Do not flush the firewall or remove unrelated rules.

## Tailscale alternative

On the inspected configuration, `tailscale0` is trusted in both custom host chains. A client with appropriate tailnet access can instead target:

```sh
mosh ed@100.70.41.73
```

This avoids the LAN-only exception path. Tailscale connectivity and grants/ACLs still need to permit the connection. This alternative was identified from the configuration, not tested end-to-end during the repair. Adapt the username and address on other hosts; do not assume that a hostname resolves to the Tailscale address rather than the LAN address.
