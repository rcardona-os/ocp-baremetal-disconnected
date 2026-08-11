# Sneakernet Mirroring

Red Hat specifically designed the oc-mirror tool to handle this exact scenario using a "mirror-to-disk" workflow. Instead of syncing images over a network to a registry, you pack the OpenShift release, operators, and required images into a massive archive file directly onto an intermediary storage device (like a high-capacity USB drive or external hard disk).Here is how that physical transfer workflow operates in practice:

### ⚠️ Prerequisites & Storage Warning

Before beginning the sneakernet process, ensure your intermediary media (USB drive, external HDD) has sufficient storage capacity. While a base OpenShift release may only take a few gigabytes, adding operators (like OpenShift Data Foundation, OpenShift Virtualization, or Pipelines) can quickly inflate the archive size. **It is recommend a drive with at least 100GB to 250GB of free space** depending on how many operators you mirror.

0. Installating binaries and dependencies

#### Steps

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

1. Preparing the images

You will also need an `imageset-config.yaml` file to define exactly what you want to mirror. If you don't have one yet, here is a basic example to get you started:

  ```yaml
  # example-imageset-config.yaml
  kind: ImageSetConfiguration
  apiVersion: mirror.openshift.io/v2alpha1
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
  ```

2. Mirror to Disk (Connected Environment):Requires internet access.On a machine connected to the internet, you run **oc-mirror** targeting a local directory on your portable media (e.g., a mounted USB drive) instead of a registry URL.

```bash
# Note the file:// protocol instead of docker://
oc mirror --config imageset-config.yaml file:///mnt/usb-drive/mirror-archive
```

💥 This downloads and packages all requested container images, along with the metadata, into a .tar archive on the drive.


3. The Physical Air-Gap Transfer:The Sneakernet.You safely unmount the USB drive, physically walk it across the facility—often passing it through security scanners or malware kiosks as required by the organization—and plug it into a Bastion host sitting entirely inside the restricted network.

4. Mirror to Registry (Disconnected Environment):No internet access.From the internal Bastion host, you run oc-mirror again. This time, you instruct it to unpack the archive from the USB drive and push the images into your internal, disconnected container registry (like Quay, Nexus, or the Red Hat Mirror Registry).


  ```bash
  oc mirror --from file:///mnt/usb-drive/mirror-archive docker://internal-registry.local:5000
  ```


Once that final step is complete, your internal registry is fully populated. You then point your Assisted Installer (and the resulting OpenShift cluster) at that internal registry, and the installation proceeds completely isolated from the outside world.


---

99. Apply the Configuration to the Cluster (Optional : Post-Install/Day 2)

Once **oc-mirror** successfully pushes the images to your internal registry, it automatically generates a results-xxx directory inside your working folder. This folder contains critical Kubernetes manifests (ImageContentSourcePolicy or ImageDigestMirrorSet, and CatalogSource files). If you are using the Assisted Installer, you will need to apply these manifests to your cluster after it finishes installing (or inject them during installation if supported) so the nodes know to pull images from your internal registry instead of the internet.

  ```bash
  # Navigate to the generated results directory
  cd oc-mirror-workspace/results-*/

  # Apply the Image Content Source Policy (tells nodes where to redirect pulls)
  oc apply -f imageContentSourcePolicy.yaml 
  # OR in newer OCP versions: oc apply -f imageDigestMirrorSet.yaml

  # Apply the Catalog Source (makes the mirrored Operators appear in OperatorHub)
  oc apply -f catalogSource-cs-redhat-operator-index.yaml
  ```