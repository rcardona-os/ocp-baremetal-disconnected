# Mirror Registry Installation

The mirror registry is a small and streamlined container registry used as a target for mirroring the required container images of OpenShift Container Platform for disconnected installations.

__Creating a mirror full documentation__ [__HERE__](https://docs.openshift.com/container-platform/4.12/installing/disconnected_install/installing-mirroring-creating-registry.html)

__Mirroting to a fully disconnected registry from a disk__ [__HERE__](https://docs.openshift.com/container-platform/4.17/disconnected/mirroring/installing-mirroring-disconnected.html#oc-mirror-mirror-to-disk_installing-mirroring-disconnected)

- Prerequisites

  - An OpenShift Container Platform subscription.

  - Red Hat Enterprise Linux 8 (or above) with Podman 3.3 installed.

  - Fully qualified domain name for the Red Hat Quay service, which must resolve through a DNS server.

  - Passwordless sudo access on the target host.

  - Key-based SSH connectivity on the target host. SSH keys are automatically generated for local installs. For remote hosts, you must generate your own SSH keys.

  - 2 or more vCPUs.

  - 8 GB of RAM.

  - Binaries: oc

  - About 12 GB for OpenShift Container Platform 4.12 release images, or about 358 GB for OpenShift Container Platform 4.12 release images and OpenShift Container Platform 4.12 Red Hat Operator images. Up to 1 TB per stream or more is suggested.

  - A hostname with a resolvable URL

$\textcolor{LightSalmon}  {\text{ NOTE: Check that port 8443 is open, as it is the default port where the installer configures the quay service. However that port can also be customized. }}$

- Install podman
  ```bash
  sudo dnf install podman -y
  ```

- Download the `mirror-registry` binary
  ```bash
  wget https://developers.redhat.com/content-gateway/file/pub/openshift-v4/clients/mirror-registry/1.3.9/mirror-registry.tar.gz
  ``` 

- Deploying mirror registry
  ```bash
  tar xzvf mirror-registry.tar.gz
  ```

  ```bash
  sudo ./mirror-registry install --quayHostname registry.sandbox2278opentlc.com --initUser admin --initPassword "quayPass123"
  ```

![`Example Command Launch`](media/quay-0.png)

![`Example Command Result`](media/quay-1.png)

Here it is visible the end point of the registry. Login with credentials user:"admin" password:"quayPass123"

- __(optional)__ in case the default self-signed certs are being used, please use the following procedure
  ```bash
  sudo cp /root/quay-install/quay-rootCA/rootCA.pem /etc/pki/ca-trust/source/anchors/
  ```

  ```bash
  sudo update-ca-trust
  ```

#### Installing oc binary
```bash
curl -LO "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux.tar.gz"
    
tar -xvzf openshift-client-linux.tar.gz
    
sudo mv oc /usr/local/bin/oc

sudo chmod +x /usr/local/bin/oc
```

### The following steps show how to mirror the Openshift Cluster installation packages

- Further documentation [HERE](https://docs.openshift.com/container-platform/4.12/installing/disconnected_install/installing-mirroring-disconnected.html)

- Public repositories (mirrors) [REPOS](https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/latest/)

- Complete the secret file to login at the mirror registry and Red Hat registries, by  merging the `pull-secret.json` (cloud.redhat.com) and the credentials of the mirror registry.
  ```bash
  podman login -u admin --authfile pull-secret.json registry.sandbox2278.opentlc.com:8443 --tls-verify=false
  ```

- Load the needed variables to mirror the images for OCP v4.12
  ```bash
  export OCP_RELEASE="4.16.3"
  export LOCAL_REGISTRY="registry.sandbox2278.opentlc.com:8443"
  export LOCAL_REPOSITORY="ocp4/openshift4"
  export PRODUCT_REPO="openshift-release-dev"
  export LOCAL_SECRET_JSON="./pull-secret.json"
  export RELEASE_NAME="ocp-release"
  export ARCHITECTURE="x86_64"
  ```

- The following command allow to review the images and configuration manifests without actually mirroring them
  ```bash
  oc adm release mirror -a ${LOCAL_SECRET_JSON} \
  --from=quay.io/${PRODUCT_REPO}/${RELEASE_NAME}:${OCP_RELEASE}-${ARCHITECTURE} \
  --to=${LOCAL_REGISTRY}/${LOCAL_REPOSITORY} \
  --to-release-image=${LOCAL_REGISTRY}/${LOCAL_REPOSITORY}:${OCP_RELEASE}-${ARCHITECTURE} --dry-run
  ```

- Mirroring (directly push) the release images to the local registry by using following command
  ```bash
  oc adm release mirror -a ${LOCAL_SECRET_JSON} \
  --from=quay.io/${PRODUCT_REPO}/${RELEASE_NAME}:${OCP_RELEASE}-${ARCHITECTURE} \
  --to=${LOCAL_REGISTRY}/${LOCAL_REPOSITORY} \
  --to-release-image=${LOCAL_REGISTRY}/${LOCAL_REPOSITORY}:${OCP_RELEASE}-${ARCHITECTURE}
  ```

- Save the output of the mirroring, as it indicates that stanza of the ImageContentSource to be use for further OCP installation.

ex.

  ```text
  ...

  Success
  Update image:  registry.sandbox549.opentlc.com:8443/ocp4/openshift4:4.13.12-x86_64
  Mirror prefix: registry.sandbox549.opentlc.com:8443/ocp4/openshift4
  Mirror prefix: registry.sandbox549.opentlc.com:8443/ocp4/openshift4:4.13.12-x86_64

  To use the new mirrored repository to install, add the following section to the install-config.yaml:

  imageContentSources:
  - mirrors:
    - registry.sandbox549.opentlc.com:8443/ocp4/openshift4
    source: quay.io/openshift-release-dev/ocp-release
  - mirrors:
    - registry.sandbox549.opentlc.com:8443/ocp4/openshift4
    source: quay.io/openshift-release-dev/ocp-v4.0-art-dev


  To use the new mirrored repository for upgrades, use the following to create an ImageContentSourcePolicy:

  apiVersion: operator.openshift.io/v1alpha1
  kind: ImageContentSourcePolicy
  metadata:
    name: example
  spec:
    repositoryDigestMirrors:
    - mirrors:
      - registry.sandbox549.opentlc.com:8443/ocp4/openshift4
      source: quay.io/openshift-release-dev/ocp-release
    - mirrors:
      - registry.sandbox549.opentlc.com:8443/ocp4/openshift4
      source: quay.io/openshift-release-dev/ocp-v4.0-art-dev

  ....
  ```

---
### Generate customized openshift-install binary specifically for the mirrored registry
- This part of the mirroring corresponds to the creation of the installation program that is based on the content that were mirrored in the previous step.
  ```bash
  oc adm release extract -a ${LOCAL_SECRET_JSON} \
  --command=openshift-install "${LOCAL_REGISTRY}/${LOCAL_REPOSITORY}:${OCP_RELEASE}-${ARCHITECTURE}"
  ```


---

### Mirroring Operator Catalogs
- Listing the existing operators that will be mirrored. There are different catalog namespaces; _redhat-operators_, _certified-operators_, _redhat-marketplace_ and _community-operators_ from which the index image can be gathered.

---

### EXTRA help commands

---

- commands to query existing tags on quay registry

  - __(option 1)__ listing existing tags
  ```bash
  skopeo login registry.sandbox549.opentlc.com:8443

  ```
  ```bash
  skopeo list-tags docker://registry.sandbox549.opentlc.com:8443/ocp4/openshift4
  ```

  - __(option 2)__ listing existing tags
  ```bash
  curl -L https://github.com/regclient/regclient/releases/latest/download/regctl-linux-amd64 >regctl
  ```
  ```bash
  chmod 755 regctl
  ```
  ```bash
  regctl tag ls registry.sandbox549.opentlc.com:8443/ocp4/openshift4
  ```
  - __(option 3)__ listing repositories/catalogs
  ```bash
  curl -X GET -k --header 'Content-Type: application/json' \
  --data '{ "username": "admin", "password":"quaypass123"}' \
  https://registry.sandbox549.opentlc.com:8443/v2/_catalog
  ```
  
  - __(option 4)__ list tags in the mirrored repo
  ```bash
  podman login -u admin --authfile pull-secret.json registry.sandbox549.opentlc.com:8443 --tls-verify=false
  ```

  ```bash
  podman search --list-tags registry.sandbox549.opentlc.com:8443/ocp4/openshift4 --limit 100 --tls-verify=false
  ```


---

- further
  ```bash
  curl -su $DOCKER_USERNAME:$DOCKER_PASSWORD https://$DOCKER_REGISTRY/v2/_catalog | jq .
  ```
  ```bash
  curl -su admin:quayPass123 https://registry.sandbox549.opentlc.com:8443/v2/_catalog | jq .
  ```


---

extract certs from quay registry
```bash
openssl s_client -connect registry.ocp-private.com:8443 -showcerts
```

NOTE: When configuring OpenShift with a private registry, you need to add the appropriate certificate to the install-config.yaml. Based on the output of the openssl s_client command you provided, the certificate that should be added is the Root CA Certificate (the one at the top of the chain). 

Certificates in Your Output
Certificate 0: This is the server certificate (quay-enterprise), issued by registry.ocp-private.com. It is the direct certificate used for communication.
Certificate 1: This is the issuer's certificate (registry.ocp-private.com), which is the Root CA. This is the certificate you should include because it is responsible for verifying the chain of trust.

- The Root CA certificate is marked as:
```text
i:C = US, ST = VA, L = New York, O = Quay, OU = Division, CN = registry.ocp-private.com
```