# Red Hat Openshift Cluster Baremetal Installation with Assisted Installed

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

Forward DNS resolution must be available before starting the installation.

At minimum, prepare records for:

  ```text
  api.<cluster-name>.<base-domain>
  api-int.<cluster-name>.<base-domain>
  *.apps.<cluster-name>.<base-domain>
  ```

DNS resolution should also be available for the individual control plane and worker nodes.

Example:

  ```text
  api.ocp.example.com
  api-int.ocp.example.com
  *.apps.ocp.example.com

  master01.ocp.example.com
  master02.ocp.example.com
  master03.ocp.example.com

  worker01.ocp.example.com
  worker02.ocp.example.com
  worker03.ocp.example.com
  ```

Where possible, configure DHCP to provide the expected hostname to each node.

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

A RHEL 9 x86_64 system is required to prepare the disconnected installation content.

Recommended repositories:

  ```bash
  sudo subscription-manager repos --disable="*" \
    --enable="rhel-9-for-x86_64-baseos-rpms" \
    --enable="rhel-9-for-x86_64-appstream-rpms"
  ```

Install the basic required utilities:

  ```bash
  sudo dnf install -y \
    container-tools \
    openssl \
    jq \
    curl \
    wget \
    tar \
    gzip \
    bind-utils
  ```

The host used to download the OpenShift content must have access to the Red Hat container registries.

If the final mirror registry is located inside the disconnected environment, the mirrored content must be transferred using removable storage or another approved transfer mechanism.

Required installation tools

The following tools are required:

openshift-install
oc
oc-mirror

For this deployment:

OpenShift Container Platform: 4.21.26
openshift-install:            4.21.26
oc:                           4.21.x
oc-mirror:                    current oc-mirror v2

Verify the binaries before starting:

openshift-install version
oc version --client
oc mirror --v2 --help



















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