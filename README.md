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

1. **Bastion Host:** A machine with internet access to download images, and network access to the disconnected environment.
2. **Mirror Registry:** An existing, running container registry in the disconnected network.
3. **DNS/DHCP Services:** Pre-configured DNS records for API, Ingress, and node hostnames, plus DHCP for IP allocation (if not using static IPs).
4. **Pull Secret:** A valid Red Hat pull secret (downloaded from Red Hat Hybrid Cloud Console).
5. **Tools Installed on Bastion:**
   - `oc` (OpenShift CLI)
   - `oc-mirror` plugin
   - `podman` or `docker`

---

### Repository Structure

*(Adjust this section based on how you organize your files)*

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