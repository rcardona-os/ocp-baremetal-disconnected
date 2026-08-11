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

  - The following is the ImageSetConfiguration file for Red Hat component

  ```bash
  cat imageset-config.yaml
  ```

  ``` yaml
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
          - name: numaresources-operator
          - name: kernel-module-management
          - name: kubernetes-nmstate-operator

      - catalog: registry.redhat.io/redhat/certified-operator-index:v4.21
        packages:

          - name: openshift-fusion-access-operator
  ```

  - The following is the ImageSetConfiguration file for complete deployment including IBM Fusion Access for SAN, but first access to IBM public repositories should be configured.

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

- Complete - The following is the ImageSetConfiguration file for Red Hat component

  ```bash
  cat imageset-config.yaml
  ```

  ```yaml
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
            channels:
              - name: stable

          # NUMA-aware scheduling
          - name: numaresources-operator

          # Required by IBM Fusion Access for SAN
          # for GPFS kernel module lifecycle management
          - name: kernel-module-management
            channels:
              - name: stable

          # Host networking:
          # bridges, bonds, VLANs and VM secondary networks
          - name: kubernetes-nmstate-operator


      # ---------------------------------------------------------
      # IBM Fusion Access for SAN
      #
      # Standalone Fusion Access for SAN Operator.
      # This is NOT Fusion Data Foundation.
      # ---------------------------------------------------------
      - catalog: registry.redhat.io/redhat/certified-operator-index:v4.21
        packages:

          - name: openshift-fusion-access-operator


    # =========================================================
    # IBM Storage Scale operand images
    #
    # REQUIRED for a fully disconnected Fusion Access for SAN
    # deployment, but the exact image set is tied to the
    # Storage Scale version selected by the FusionAccess CR.
    #
    # Do not populate this from the FDF 6.0.1.0 documentation
    # unless IBM confirms that version for the standalone
    # Fusion Access deployment.
    # =========================================================
    additionalImages: []
  ```

----


### 2. Mirror to Disk (media, directory on OS, etc)
The connected host must have internet access to all registries referenced by the `ImageSetConfiguration`.

Before performing the real mirror operation, validate that the required OpenShift and Operator content can be resolved.

#### Validate the Operator content

Confirm that the IBM Fusion Access for SAN Operator is present in the OpenShift 4.21 certified Operator catalog:

```bash
oc mirror list operators \
  --catalog registry.redhat.io/redhat/certified-operator-index:v4.21 \
  --package openshift-fusion-access-operator
```

Confirm the Kernel Module Management Operator:

```bash
oc mirror list operators \
  --catalog registry.redhat.io/redhat/redhat-operator-index:v4.21 \
  --package kernel-module-management
```

Also verify the OpenShift Virtualization package:

```bash
oc mirror list operators \
  --catalog registry.redhat.io/redhat/redhat-operator-index:v4.21 \
  --package kubevirt-hyperconverged
```

#### Perform an `oc-mirror` dry run

Create a persistent workspace and cache:

```bash
mkdir -p "${HOME}/oc-mirror-workspace"
mkdir -p "${HOME}/oc-mirror-cache"
```

Run the dry run:

```bash
oc mirror --v2 \
  --config imageset-config.yaml \
  --authfile "${MIRROR_AUTH_FILE}" \
  --workspace "${HOME}/oc-mirror-workspace" \
  --cache-dir "${HOME}/oc-mirror-cache" \
  file:///mnt/usb-drive/mirror-archive \
  --dry-run
```

Review the generated image mapping:

```bash
grep -Ei \
  'kubevirt|numaresources|kernel-module-management|nmstate|fusion-access' \
  "${HOME}/oc-mirror-workspace/working-dir/dry-run/mapping.txt"
```

The output must contain the required OpenShift Virtualization, KMM, NMState, NUMA and Fusion Access Operator images before proceeding.

> ⚠️ **IBM Storage Scale images**
>
> The standalone Fusion Access for SAN Operator installs IBM Storage Scale after the `FusionAccess` custom resource is created.
>
> In a disconnected environment, the corresponding IBM Storage Scale operand images must also exist in the private registry.
>
> The exact Storage Scale image set is version-specific. Do not reuse the Storage Scale 6.0.1.0 image list documented for the Fusion Data Foundation 4.21 deployment unless IBM confirms that the same Storage Scale version is to be used with the standalone Fusion Access for SAN Operator.
>
> The final `additionalImages` section must therefore be populated with the IBM-published images corresponding to the Storage Scale version selected for this Fusion Access deployment before performing the final production mirror.

#### Mirror the content to disk

After the ImageSetConfiguration has been validated and the required IBM Storage Scale image set has been confirmed, mirror the content to the removable media:

```bash
oc mirror --v2 \
  --config imageset-config.yaml \
  --authfile "${MIRROR_AUTH_FILE}" \
  --workspace "${HOME}/oc-mirror-workspace" \
  --cache-dir "${HOME}/oc-mirror-cache" \
  file:///mnt/usb-drive/mirror-archive
```

The `file://` destination contains the archives and metadata that must be transferred across the air gap.

Verify that the mirror archive was generated:

```bash
find /mnt/usb-drive/mirror-archive \
  -type f \
  -name 'mirror_*.tar' \
  -ls
```

Generate checksums before transferring the media:

```bash
cd /mnt/usb-drive/mirror-archive

sha256sum mirror_*.tar > SHA256SUMS
```

Keep the `oc-mirror` workspace and cache on the connected host. They should not be treated as temporary files because they are useful for subsequent incremental mirror operations.