# Red Hat Openshift Cluster Baremetal Installation with Assisted Installed


# OpenShift Disconnected Installation via Assisted Installer

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

- 3 bare-metal control plane nodes.
- 2 or more bare-metal worker nodes.
- DHCP service available on the machine network.
- DNS service accessible from all cluster nodes.
- NTP service accessible from all cluster nodes.
- A container registry accessible from all OpenShift nodes.
- A RHEL 9 system for preparing and mirroring the OpenShift content.
- A mechanism to boot the generated Agent ISO on every bare-metal server:
  - BMC virtual media, or
  - physical media, or
  - PXE/HTTP boot if available.
- API and application ingress load balancing infrastructure, when using `platform: none`.

For this project, additional worker capacity will be required later for **OpenShift Virtualization** and **IBM Fusion Data Access for SAN**. Their sizing and configuration are outside the scope of the base OpenShift installation prerequisites.

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

When DHCP is used, no static networkConfig is required in **agent-config.yaml**





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