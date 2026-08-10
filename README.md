# Red Hat Openshift Cluster
### Baremetal Installation with Assisted Installed

This repository contains the configuration, scripts, and documentation required to deploy a Red Hat OpenShift Container Platform (OCP) cluster in a disconnected (air-gapped) environment using the local Assisted Installer.

### Table of Contents

- [Architecture Overview](#architecture-overview)
- [Prerequisites](#prerequisites)
- [Repository Structure](#repository-structure)
- [Step 1: Mirroring Content](#step-1-mirroring-content)
- [Step 2: Deploying the Local Assisted Installer](#step-2-deploying-the-local-assisted-installer)
- [Step 3: Cluster Configuration](#step-3-cluster-configuration)
- [Step 4: Installation](#step-4-installation)
- [Post-Installation (Day 2)](#post-installation-day-2)
- [Troubleshooting](#troubleshooting)

---

### Architecture Overview

*(Provide a brief overview of your deployment architecture here. E.g., Number of control plane/compute nodes, network topology, and the location of the Bastion host and Mirror Registry.)*

* **OCP Version:** `4.21.26`
* **Infrastructure Provider:** `Bare Metal`
* **Registry Solution:** `Red Hat Public Registries / Private Local Mirrored Registry`

---

#### Prerequisites

Before beginning the installation, ensure the following infrastructure and requirements are met:

# Prerequisites

This procedure describes the installation of **Red Hat OpenShift Container Platform 4.21.26** on bare-metal infrastructure in a **disconnected environment**, using the **Agent-based Installer**.

The deployment assumes that DHCP is available for the OpenShift nodes.

## Infrastructure

The following infrastructure must be available before starting the installation:

- Bastion Host
- 3 bare-metal control plane nodes.
- 2 or more bare-metal worker nodes.
- DHCP service available on the machine network.
- DNS service accessible from all cluster nodes.
- NTP service accessible from all cluster nodes.
- A container registry accessible from all OpenShift nodes.
- A RHEL 9 system for preparing and mirroring the OpenShift content.
- A mechanism to boot the generated Agent ISO on every bare-metal server:
  - BMC virtual media
- API and application ingress load balancing infrastructure, when using `platform: none`.

For this project, additional worker capacity will be required later for **OpenShift Virtualization** and **IBM Fusion Data Access for SAN**. Their sizing and configuration are outside the scope of the base OpenShift installation prerequisites.

## Bastion Host

A machine with internet access to download images, and network access to the disconnected environment. Any type of linux base system will serve the purpose, but it is worth to mention that this procesure has been tested on RHEL9.

## DHCP

DHCP must provide network configuration to every OpenShift node.

At minimum, each node must receive:

- IP address
- subnet mask/prefix
- default gateway
- DNS server(s)

It is strongly recommended to use **DHCP reservations** so that each OpenShift node consistently receives the same IP address.

The IP address of one of the control plane nodes must be known in advance. This node will become the temporary **rendezvous host** during the Agent-based installation.

Example:

  ```text
  master01 -> 192.168.10.21
  master02 -> 192.168.10.22
  master03 -> 192.168.10.23
  ```

The selected rendezvous address will later be configured in **agent-config.yaml**.

When DHCP is used, no static networkConfig is required in **agent-config.yaml**.

## DNS

DNS must be configured and operational before starting the installation.

The following components require forward DNS resolution:

- Kubernetes API
- Internal Kubernetes API
- OpenShift application wildcard
- Control plane nodes
- Worker nodes
- Mirror registry

At minimum, create the following records:

```text
api.<cluster-name>.<base-domain>
api-int.<cluster-name>.<base-domain>
*.apps.<cluster-name>.<base-domain>
```

Each control plane and worker node should also have an individual A record.

Example:

  ```text
  api.ocp.example.com           -> 192.168.10.10
  api-int.ocp.example.com       -> 192.168.10.10
  *.apps.ocp.example.com        -> 192.168.10.11

  master01.ocp.example.com      -> 192.168.10.21
  master02.ocp.example.com      -> 192.168.10.22
  master03.ocp.example.com      -> 192.168.10.23

  worker01.ocp.example.com      -> 192.168.10.31
  worker02.ocp.example.com      -> 192.168.10.32
  worker03.ocp.example.com      -> 192.168.10.33
  ```

- Reverse DNS

Reverse DNS resolution using PTR records must also be configured for:

Kubernetes API
Internal Kubernetes API
All control plane nodes
All worker nodes

Example:

192.168.10.21 -> master01.ocp.example.com
192.168.10.22 -> master02.ocp.example.com
192.168.10.23 -> master03.ocp.example.com

192.168.10.31 -> worker01.ocp.example.com
192.168.10.32 -> worker02.ocp.example.com
192.168.10.33 -> worker03.ocp.example.com

The API load-balancer address must also provide reverse resolution for the API endpoint.

For example:

192.168.10.10 -> api.ocp.example.com

api-int.<cluster-name>.<base-domain> normally resolves to the same API load-balancer address and is used for internal cluster communication.

A PTR record is not required for the OpenShift application wildcard:

*.apps.<cluster-name>.<base-domain>

Because DHCP is used in this deployment, it is recommended that DHCP provides a stable hostname and address to each node, preferably using DHCP reservations based on MAC address.

Before starting the installation, validate both forward and reverse resolution:

  ```bash
  dig api.ocp.example.com +short
  dig api-int.ocp.example.com +short

  dig master01.ocp.example.com +short
  dig worker01.ocp.example.com +short

  dig -x 192.168.10.21 +short
  dig -x 192.168.10.31 +short
  ```

Forward and reverse DNS should return the expected hostname/IP relationship.


🔥 For OCP 4.21 with Agent-based Installer and `platform: none`, Red Hat explicitly requires reverse DNS for the Kubernetes API, control-plane nodes and compute nodes; the application wildcard does **not** require a PTR.


## NTP

All OpenShift nodes must have access to a reliable NTP source.

Consistent time synchronization is required across:

- Control plane nodes
- Worker nodes
- Mirror registry
- Istallation host
- DNS/load-balancer infrastructure


## Network connectivity

All OpenShift nodes must be able to communicate with each other over the cluster network.

During the Agent-based installation, every node must also be able to reach the rendezvous host on:

  ```text
  TCP/8090
  ```

Port 8090 is used by the Assisted Service during node discovery and installation and is only required during the installation process.

The nodes must also be able to reach:
Tthe mirror registry (in case of disconneceted deployment)
DNS servers
NTP servers
API load balancer
Application ingress load balancer

Internet access from the OpenShift nodes is not required if the deployment will be disconnected.

## Mirror preparation host (optional)

Navigate to this produce to configure it [HERE](cluster-registry/mirror-registry-commons.md)


## Bare-metal server preparation

Before installation:

- Enable CPU virtualization extensions in the server BIOS/UEFI.
- Confirm that the intended RHCOS installation disk is visible.
- Record the MAC address of the network interface used by each node.
- Confirm DHCP operation from the intended OpenShift network.
- Confirm DNS and NTP connectivity.
- Confirm that each server can boot the Agent ISO.
- Confirm access to the server BMC or remote console where available.

The RHCOS installation disk must be clearly identifiable, particularly if additional SAN storage is visible to the servers.

SAN LUNs intended for IBM Fusion should preferably not be presented to the nodes during the initial OpenShift installation.

## Information to collect

Before proceeding with the installation, collect the following information:

  ```text
  Cluster name:
  Base domain:

  Machine network:
  DHCP range:
  Default gateway:
  DNS server(s):
  NTP server(s):

  API address:
  Ingress address:

  Mirror registry FQDN:
  Mirror registry port:

  Control plane node MAC addresses:
  Worker node MAC addresses:

  Rendezvous control plane node:
  Rendezvous IP:

  RHCOS installation disk for each node:
  ```

The rendezvousIP must be reserved and known before generating the Agent ISO.


If the registry uses a private or self-signed CA, its CA certificate must be available so it can later be added to the OpenShift trust bundle.


















---

### Repository Structure


```text
├── manifests/            # Custom Kubernetes manifests applied during Day-0/Day-1
├── mirror/               # Scripts and ImageSetConfigurations for oc-mirror
│   └── imageset-config.yaml
├── scripts/              # Helper scripts for automation
│   ├── 01-mirror-images.sh
│   ├── 02-setup-ai.sh
│   └── 03-generate-iso.sh
├── assisted-installer/   # Configuration for deploying the local AI service
└── README.md             # This file