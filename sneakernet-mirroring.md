# Sneakernet Mirroring

Red Hat specifically designed the oc-mirror tool to handle this exact scenario using a "mirror-to-disk" workflow. Instead of syncing images over a network to a registry, you pack the OpenShift release, operators, and required images into a massive archive file directly onto an intermediary storage device (like a high-capacity USB drive or external hard disk).Here is how that physical transfer workflow operates in practice:

### ⚠️ Prerequisites & Storage Warning

Before beginning the sneakernet process, ensure your intermediary media (USB drive, external HDD) has sufficient storage capacity. While a base OpenShift release may only take a few gigabytes, adding operators (like OpenShift Data Foundation, OpenShift Virtualization, or Pipelines) can quickly inflate the archive size. **For this deployment it is recommend a drive with at least 500GB of free space** depending on how many operators you mirror.

### 0. Installating binaries and dependencies

- Install depencides
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

  podman --version
  skopeo --version
  openssl version
  ```

- Download the binaries; _oc, oc-mirror, openshift-install and mirror-registry_ [__HERE__](https://console.redhat.com/openshift/downloads) 

  ![](media/binaries_disconnected.png)

- Installing oc binary
  ```bash    
  tar xvzf openshift-client-linux.tar.gz
  sudo mv oc /usr/local/bin/oc
  sudo chmod +x /usr/local/bin/oc
  ```

- Install the `oc-mirror` plugin:
  ```bash
  tar xvzf oc-mirror.tar.gz
  sudo install -m 0755 oc-mirror /usr/local/bin/oc-mirror
  umask 0022
  ```

- Verify the tool
  ```bash
  oc version --client
  oc mirror --v2 --help
  openshift-install version
  ```

### 1. Preparing the images

#### Red Hat Openshift Base Images and Operators

You will also need an `imageset-config.yaml` file to define exactly what you want to mirror. If you don't have one yet, here is a basic example to get you started:

  ```yaml
  # example-imageset-config.yaml
  apiVersion: mirror.openshift.io/v2alpha1
  kind: ImageSetConfiguration

  mirror:

    platform:
      architectures:
        - amd64
      channels:
        - name: stable-4.21
          type: ocp
          minVersion: "4.21.26"
          maxVersion: "4.21.26"
      graph: false

    operators:
      - catalog: registry.redhat.io/redhat/redhat-operator-index:v4.21
        packages:

          - name: kubevirt-hyperconverged
            channels:
              - name: stable

          - name: numaresources-operator
            channels:
              - name: "4.21"

  ...
  ```

#### IBM Fusion Access for SAN

IBM Fusion 2.13 introduces Fusion Access for SAN as a Fusion Data Foundation 4.21 capability. IBM's current disconnected procedure for OCP 4.21+ says the disconnected environment needs three IBM-related sets of content [DOCS](https://www.ibm.com/docs/en/fusion-software/2.13.0?topic=images-mirroring-fusion-data-foundation):

  - Red Hat Operators
  - Fusion Data Foundation 4.21
  - IBM Storage Scale 6.0.1.0 images

IBM's current oc-mirror v2 configuration for Fusion Data Foundation 4.21 uses

#### IBM Fusion Access for SAN

This deployment uses **IBM Fusion Access for SAN as a standalone Operator**.

For OpenShift Container Platform 4.21 or later, IBM supports two deployment models:

  - Fusion Access for SAN integrated with Fusion Data Foundation.
  - Fusion Access for SAN deployed using the standalone Fusion Access for SAN Operator.

This procedure uses the **standalone Fusion Access for SAN Operator** and does not deploy Fusion Data Foundation.

The standalone deployment requires:

  - IBM Fusion Access for SAN Operator.
  - Kernel Module Management (KMM) Operator.
  - IBM Storage Scale components required by the selected Fusion Access release.
  - IBM entitlement credentials for entitled images hosted in `cp.icr.io`.

The Fusion Access Operator package is:

  ```text
  openshift-fusion-access-operator
  ```

#### Complete ImageSetConfiguration for this installation

  ```bash
  cat imageset-config.yaml
  ```

  ``` yaml
  apiVersion: mirror.openshift.io/v2alpha1
  kind: ImageSetConfiguration

  mirror:

    # =========================================================
    # OpenShift Container Platform 4.21.26
    # =========================================================
    platform:
      architectures:
        - amd64

      channels:
        - name: stable-4.21
          type: ocp
          minVersion: "4.21.26"
          maxVersion: "4.21.26"

      graph: false


    # =========================================================
    # Operators
    # =========================================================
    operators:

      # ---------------------------------------------------------
      # Red Hat Operators
      # ---------------------------------------------------------
      - catalog: registry.redhat.io/redhat/redhat-operator-index:v4.21
        packages:

          # OpenShift Virtualization
          - name: kubevirt-hyperconverged

          # NUMA-aware scheduling
          - name: numaresources-operator

          # Required by IBM Fusion Access for SAN for
          # GPFS kernel module lifecycle management
          - name: kernel-module-management

          # Host networking for bridges, bonds, VLANs, etc.
          - name: kubernetes-nmstate-operator


      # ---------------------------------------------------------
      # IBM Fusion Access for SAN
      #
      # Standalone Fusion Access for SAN Operator
      # ---------------------------------------------------------
      - catalog: registry.redhat.io/redhat/certified-operator-index:v4.21
        packages:

          - name: openshift-fusion-access-operator
  ```

 ⚡️ Important: the cp.icr.io credentials must contain the customer's IBM Fusion entitlement. IBM explicitly requires that entitlement for these images [DOCS](https://www.ibm.com/docs/en/fusion-software/2.13.0?topic=images-mirroring-fusion)


#### IBM Connected Side

IBM requires the username to be literally cp, with the customer's IBM entitlement key as the password; the entitlement must include IBM Fusion.

- Authenticate to the IBM Entitled Container Registry

IBM Fusion Access for SAN and IBM Storage Scale use entitled container images hosted in:

  ```text
  cp.icr.io
  ``` 

require authentication with an IBM entitlement key.

The IBM public Operator images hosted under:

  ```text
  icr.io/cpopen/..
  ```

- Obtain the IBM entitlement key

Obtain an entitlement key from the IBM Container Software Library using an IBMid associated with the customer's IBM Fusion entitlement.

The entitlement key must provide access to the IBM Fusion / IBM Storage Scale images required by this deployment.

The credentials used for cp.icr.io are:
  ```text
  Registry:  cp.icr.io
  Username:  cp
  Password:  <IBM entitlement key>
```

⚡️ NOTE: The username is always cp. The entitlement key is used as the password.

- Create a persistent authentication file

For oc-mirror, use an explicit authentication file rather than relying only on the default Podman runtime authentication file.

- Create a protected directory:
  ```bash
  mkdir -p "${HOME}/.config/oc-mirror"
  chmod 700 "${HOME}/.config/oc-mirror"
  ```

export MIRROR_AUTH_FILE="${HOME}/.config/oc-mirror/auth.json"

- Authenticate to the IBM Entitled Container Registry:
  ```bash
  podman login \
    --authfile "${MIRROR_AUTH_FILE}" \
    --username cp \
    cp.icr.io
  ```

- Enter the IBM entitlement key when prompted:
  ```bash
  Password: <IBM entitlement key>
  Login Succeeded!
  ```

Using the password prompt avoids placing the entitlement key directly in the shell command history.

- Add the Red Hat credentials to the same authentication file

The same authentication file can contain credentials for all source registries required by oc-mirror.

Authenticate to the Red Hat registry:
  ```bash
  podman login \
    --authfile "${MIRROR_AUTH_FILE}" \
    registry.redhat.io
  ```

Enter the Red Hat registry username and password when prompted.

The authentication file should now contain entries for at least:
  ```text
  cp.icr.io
  registry.redhat.io
  ```

quay.io and icr.io/cpopen normally contain publicly accessible content and do not require IBM entitlement credentials.

Verify the configured registry entries without displaying the credentials:
  ```bash
  jq -r '.auths | keys[]' "${MIRROR_AUTH_FILE}"
  ```

  Example:
  ```text
  cp.icr.io
  registry.redhat.io
  ```
  
#### Verify IBM entitlement access
 

Authentication to cp.icr.io does not necessarily prove that the IBMid has the correct product entitlement.

Verify access against one of the entitled IBM Storage Scale images defined in imageset-config.yaml.

For example:
  ```bash
  skopeo inspect \
    --authfile "${MIRROR_AUTH_FILE}" \
    docker://cp.icr.io/cp/gpfs/<image>@sha256:<digest> \
    > /dev/null
  ```

A successful command confirms that the entitlement key can access that image.

If the command returns an authentication or authorization error, verify that:

  - the entitlement key is valid
  - the IBMid associated with the key has IBM Fusion entitlement
  - access to cp.icr.io is permitted through the firewall/proxy
  - the requested IBM Storage Scale image is included in the customer's entitlement


----

### 2. Mirror to Disk (media, directory on OS, etc)
apiVersion: mirror.openshift.io/v2alpha1
  kind: ImageSetConfiguration

  mirror:

    # =========================================================
    # OpenShift Container Platform 4.21.26
    # =========================================================
    platform:
      architectures:
        - amd64

      channels:
        - name: stable-4.21
          type: ocp
          minVersion: "4.21.26"
          maxVersion: "4.21.26"

      # Update graph is not required for the initial installation.
      graph: false


    # =========================================================
    # Operator catalogs
    # =========================================================
    operators:

      # ---------------------------------------------------------
      # Red Hat Operators
      # ---------------------------------------------------------
      - catalog: registry.redhat.io/redhat/redhat-operator-index:v4.21
        packages:

          # OpenShift Virtualization
          - name: kubevirt-hyperconverged

          # NUMA-aware scheduling
          - name: numaresources-operator

          # Required by IBM Fusion Access for SAN / Storage Scale
          - name: kernel-module-management

          # Node networking: bridges, bonds, VLANs, etc.
          - name: kubernetes-nmstate-operator

          # Required by IBM Fusion Data Foundation
          - name: local-storage-operator

          # Required by IBM Fusion Data Foundation
          - name: lvms-operator


      # ---------------------------------------------------------
      # IBM Fusion Software 2.13 base
      # ---------------------------------------------------------
      - catalog: icr.io/cpopen/isf-operator-software-catalog@sha256:569b3f5158af370abe3dbe049c53be55d32f239a717ca74f1f5e544c697e8f21
        packages:
          - name: isf-operator
            channels:
              - name: v2.0
                minVersion: "2.13.0"
                maxVersion: "2.13.0"


      # ---------------------------------------------------------
      # IBM Fusion Usage Metering Service
      # Required component of IBM Fusion
      # ---------------------------------------------------------
      - catalog: icr.io/cpopen/ibm-usage-metering-operator-catalog@sha256:a97cef95c73ac6dacea010818757b4ed9b7440f4c0ec4154a091f248c68d1c9e
        full: true
        packages:
          - name: ibm-usage-metering-operator
            channels:
              - name: v1.0


      # ---------------------------------------------------------
      # IBM Fusion Data Foundation 4.21
      #
      # Fusion Access for SAN is integrated with FDF on OCP 4.21.
      # ---------------------------------------------------------
      - catalog: icr.io/cpopen/isf-data-foundation-catalog:v4.21
        packages:

          - name: cephcsi-operator

          - name: mcg-operator

          - name: ocs-operator

          - name: odf-csi-addons-operator

          - name: odf-multicluster-orchestrator

          - name: odf-operator

          - name: odr-cluster-operator

          - name: odr-hub-operator

          - name: ocs-client-operator

          - name: odf-prometheus-operator

          - name: recipe

          - name: rook-ceph-operator

          - name: odf-dependencies

          - name: odf-external-snapshotter-operator

          # IBM Storage Scale / CNSA integration
          - name: ibm-spectrum-scale-operator

          - name: cnsa-dependencies


    # =========================================================
    # Additional images
    # =========================================================
    additionalImages:

      # ---------------------------------------------------------
      # IBM Fusion Software 2.13 catalog
      # ---------------------------------------------------------
      - name: icr.io/cpopen/isf-operator-software-catalog:2.13.0-13849@sha256:569b3f5158af370abe3dbe049c53be55d32f239a717ca74f1f5e544c697e8f21


      # ---------------------------------------------------------
      # IBM Fusion Usage Metering catalog
      # ---------------------------------------------------------
      - name: icr.io/cpopen/ibm-usage-metering-operator-catalog:2.13.0-24525@sha256:a97cef95c73ac6dacea010818757b4ed9b7440f4c0ec4154a091f248c68d1c9e


      # =========================================================
      # IBM Storage Scale 6.0.1.0
      #
      # Required for IBM Fusion Access for SAN on OCP 4.21.
      # These are pinned to the image digests published by IBM
      # for Storage Scale 6.0.1.0.
      # =========================================================

      # CSI sidecars
      - name: cp.icr.io/cp/gpfs/csi/csi-attacher:v4.11.0@sha256:b74b05b39501565022883fc128002b4cb857a7bb6c858606bcb3fdedba0b0b80

      - name: cp.icr.io/cp/gpfs/csi/csi-node-driver-registrar:v2.16.0@sha256:ab482308a4921e28a6df09a16ab99a457e9af9641ff44fb1be1a690d07ce8b70

      - name: cp.icr.io/cp/gpfs/csi/csi-provisioner:v6.2.0@sha256:6be9f63ca4caa6c46aae55aa372500949d8a21473d72f819da1f746076b32d4e

      - name: cp.icr.io/cp/gpfs/csi/csi-resizer:v2.1.0@sha256:589e525cddef6d768e68da1f0bc9ffd0a24bf3add3dd010648eb7189976fde79

      - name: cp.icr.io/cp/gpfs/csi/csi-apiVersion: mirror.openshift.io/v2alpha1
  kind: ImageSetConfiguration

  mirror:

    # =========================================================
    # OpenShift Container Platform 4.21.26
    # =========================================================
    platform:
      architectures:
        - amd64

      channels:
        - name: stable-4.21
          type: ocp
          minVersion: "4.21.26"
          maxVersion: "4.21.26"

      # Update graph is not required for the initial installation.
      graph: false


    # =========================================================
    # Operator catalogs
    # =========================================================
    operators:

      # ---------------------------------------------------------
      # Red Hat Operators
      # ---------------------------------------------------------
      - catalog: registry.redhat.io/redhat/redhat-operator-index:v4.21
        packages:

          # OpenShift Virtualization
          - name: kubevirt-hyperconverged

   