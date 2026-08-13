# Deploying  Assisted Installer

Objective: OpenShift 4.21.26 Bare-Metal Installation Using the Agent-based Installer


#### 0. Scope

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

#### 1. Target Architecture

We are installing:

| Parameter | Value |
|---|---|
| OpenShift | `4.21.26` |
| Cluster name | `ocpcluster` |
| Base domain | `example.com` |
| Cluster domain | `ocpcluster.example.com` |
| Platform | `baremetal` |
| Load balancer | `OpenShiftManagedDefault` |
| External LB | **NOT REQUIRED** |
| Control planes | `3` |
| Workers | `3` |
| Networking | `Static IPv4` |
| Network plugin | `OVNKubernetes` |
| Installation | `Agent-based Installer` |
| Environment | `Disconnected` |

The Agent-based Installer supports an HA topology consisting of three control-plane nodes plus compute nodes. For platform: baremetal, apiVIPs and ingressVIPs must be specified.

The important load-balancer configuration will be:

  ```yaml
  platform:
    baremetal:
      loadBalancer:
        type: OpenShiftManagedDefault
      apiVIPs:
      - 192.168.50.20
      ingressVIPs:
      - 192.168.50.21
  ```

OpenShiftManagedDefault causes OpenShift's internal API/Ingress load-balancing components to be deployed; UserManaged would instead require an out-of-band load balancer.

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

Do not allow the machine, pod, or service networks to overlap with each other or with existing infrastructure networks. The Agent-based Installer requires apiVIPs and ingressVIPs when platform: baremetal is used.

💥 VERY IMPORTANT

Do not configure these addresses manually on any server:

  ```text
  192.168.50.20   API VIP
  192.168.50.21   Ingress VIP
  ```

They must be:

  - reserved
  - reachable on the machine network
  - not allocated to another machine
  - not allocated by DHCP
  - not included later in the MetalLB pool

OpenShift will manage these two VIPs because we are using:

  ```yaml
  loadBalancer:
    type: OpenShiftManagedDefault
  ```

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

  ```bash
  dig +short api.ocpcluster.example.com
  dig +short api-int.ocpcluster.example.com
  dig +short test.apps.ocpcluster.example.com
  ```

Expected:

  ```text
  192.168.50.20
  192.168.50.20
  192.168.50.21
  ```

Check the nodes:

  ```bash
  for h in \
  master-0 master-1 master-2 \
  worker-0 worker-1 worker-2
  do
      echo "=== $h ==="
      dig +short ${h}.ocpcluster.example.com
  done
  ```

Check reverse DNS:

  ```bash
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
  ```

Correct DNS before proceeding if these results are wrong.

#### 4. Verify the VIPs Are Free

The following two IPs must not already belong to anything:

  ```text
  192.168.50.20
  192.168.50.21
  ```

At minimum:

  ```bash
  ping -c 3 192.168.50.20
  ping -c 3 192.168.50.21
  ```

There should be no existing host using them.

If the installation host is on the same L2 network, a better duplicate-address check is:


  ```bash
  sudo arping -D -c 3 -I <INTERFACE> 192.168.50.20
  sudo arping -D -c 3 -I <INTERFACE> 192.168.50.21
  ```

Replace <INTERFACE> with the interface connected to 192.168.50.0/24. For example:

  ```bash
  ip -br addr
  ```

Expected output:

  ```text
  eno1    UP    192.168.50.10/24
  ```
Then use:

```bash
sudo arping -D -c 3 -I eno1 192.168.50.20
sudo arping -D -c 3 -I eno1 192.168.50.21
```

#### 5. Verify Network/Firewall Requirements

There is one Agent-based Installer-specific requirement that must not be missed:

**All six nodes -> master-0/rendezvous -> TCP/8090**

In our example:

  ```text
  192.168.50.31:8090
  ```

During discovery/bootstrap all hosts communicate with the Assisted Service running on the rendezvous host over TCP/8090. The port is only required during installation. Also ensure the normal OpenShift machine-network communication is not blocked, including access to:

  ```text
  API VIP:
  192.168.50.20:6443

  Machine Config Server:
  192.168.50.20:22623

  Ingress:
  192.168.50.21:80
  192.168.50.21:443
  ```

and normal unrestricted cluster-node communication required by OpenShift.
