# Deploying  Assisted Installer

Objective: OpenShift 4.21.26 Bare-Metal Installation Using the Agent-based Installer


#### 1. Scope

The Agent-based Installer generates one bootable ISO containing the configuration required to discover and install the physical hosts. Red Hat supports disconnected HA clusters consisting of three control-plane nodes and compute nodes with this installation method.

This procedure installs:

- OpenShift Container Platform 4.21.26
- Cluster name: ocpcluster
- Base domain: example.com
- Cluster FQDN: ocpcluster.example.com
- Bare-metal platform
- Fully disconnected environment
- Static node IP addresses
- Existing DNS
- Existing disconnected container registry
- Three control-plane nodes
- Three worker nodes
- Agent-based Installer
- IPv4
- OVN-Kubernetes

#### 2. Example Network Plan

Replace these addresses with the real IP addresses.

| Purpose | Name | Example IP |
|---|---|---:|
| Gateway | — | 192.168.50.1 |
| DNS | — | 192.168.50.10 |
| NTP | — | 192.168.50.11 |
| API VIP | `api.ocpcluster.example.com` | 192.168.50.20 |
| Ingress VIP | `*.apps.ocpcluster.example.com` | 192.168.50.21 |
| Master 0 / Rendezvous | `master-0.ocpcluster.example.com` | 192.168.50.31 |
| Master 1 | `master-1.ocpcluster.example.com` | 192.168.50.32 |
| Master 2 | `master-2.ocpcluster.example.com` | 192.168.50.33 |
| Worker 0 | `worker-0.ocpcluster.example.com` | 192.168.50.41 |
| Worker 1 | `worker-1.ocpcluster.example.com` | 192.168.50.42 |
| Worker 2 | `worker-2.ocpcluster.example.com` | 192.168.50.43 |

Cluster networks:

  ```text
  Machine network:  192.168.50.0/24
  Pod network:      10.128.0.0/14
  Service network:  172.30.0.0/16
  ```

Do not allow the machine, pod, or service networks to overlap with each other or with existing infrastructure networks.

The Agent-based Installer requires apiVIPs and ingressVIPs when platform: baremetal is used.

#### 3. Verify DNS Before Doing Anything Else

The following records should already exist.

| DNS Name | IP Address |
|---|---:|
| `api.ocpcluster.example.com` | 192.168.50.20 |
| `api-int.ocpcluster.example.com` | 192.168.50.20 |
| `*.apps.ocpcluster.example.com` | 192.168.50.21 |
| `master-0.ocpcluster.example.com` | 192.168.50.31 |
| `master-1.ocpcluster.example.com` | 192.168.50.32 |
| `master-2.ocpcluster.example.com` | 192.168.50.33 |
| `worker-0.ocpcluster.example.com` | 192.168.50.41 |
| `worker-1.ocpcluster.example.com` | 192.168.50.42 |
| `worker-2.ocpcluster.example.com` | 192.168.50.43 |

PTR records for the physical nodes should also resolve correctly.

Check from the installation/bastion host:

dig +short api.ocpcluster.example.com
dig +short api-int.ocpcluster.example.com
dig +short test.apps.ocpcluster.example.com

Expected:

192.168.50.20
192.168.50.20
192.168.50.21

Check the nodes:

for h in \
master-0 master-1 master-2 \
worker-0 worker-1 worker-2
do
    echo "=== $h ==="
    dig +short ${h}.ocpcluster.example.com
done

Check reverse DNS:

for ip in \
192.168.50.31 \
192.168.50.32 \
192.168.50.33 \
192.168.50.41 \
192.168.50.42 \
192.168.50.43
do
    echo "=== $ip ==="
    dig +short -x ${ip}
done

Correct DNS before proceeding if these results are wrong.