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

---

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

---

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

---

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

---

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
----

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

---

#### 6. Prepare the Installation Host

Use the RHEL host inside the disconnected environment from which we will create the Agent ISO.

Install the required packages:

  ```bash
  sudo dnf install -y \
      /usr/bin/nmstatectl \
      jq \
      bind-utils \
      podman
  ```

nmstatectl is explicitly required when using the preferred install-config.yaml + agent-config.yaml Agent workflow with NMState networking.

Verify:

  ```bash
  nmstatectl --version
  jq --version
  podman --version
  ```

Verify that oc is installed:

  ```bash
  oc version --client
  ```

---

#### 7. Create a Working Variables File

We will define the installation values once and use them everywhere.

Run:

  ```bash
  cat > $HOME/ocpcluster-vars.sh <<'EOF'
  # ----------------------------------------------------------------------
  # OCP
  # ----------------------------------------------------------------------
  export OCP_VERSION='4.21.26'
  export ARCHITECTURE='x86_64'

  export CLUSTER_NAME='ocpcluster'
  export BASE_DOMAIN='example.com'

  # ----------------------------------------------------------------------
  # NETWORK
  # ----------------------------------------------------------------------
  export MACHINE_NETWORK='192.168.50.0/24'
  export GATEWAY='192.168.50.1'
  export DNS_SERVER='192.168.50.10'
  export NTP_SERVER='192.168.50.11'
  export PREFIX_LENGTH='24'

  export API_VIP='192.168.50.20'
  export INGRESS_VIP='192.168.50.21'

  # ----------------------------------------------------------------------
  # NODES
  # ----------------------------------------------------------------------
  export MASTER0_IP='192.168.50.31'
  export MASTER1_IP='192.168.50.32'
  export MASTER2_IP='192.168.50.33'

  export WORKER0_IP='192.168.50.41'
  export WORKER1_IP='192.168.50.42'
  export WORKER2_IP='192.168.50.43'

  # ----------------------------------------------------------------------
  # PHYSICAL NIC
  # Change if the production servers use a different interface name
  # ----------------------------------------------------------------------
  export NODE_INTERFACE='eno1'

  # ----------------------------------------------------------------------
  # HOST MAC ADDRESSES
  # REPLACE THESE SIX VALUES
  # ----------------------------------------------------------------------
  export MASTER0_MAC='<MASTER0_MAC>'
  export MASTER1_MAC='<MASTER1_MAC>'
  export MASTER2_MAC='<MASTER2_MAC>'

  export WORKER0_MAC='<WORKER0_MAC>'
  export WORKER1_MAC='<WORKER1_MAC>'
  export WORKER2_MAC='<WORKER2_MAC>'

  # ----------------------------------------------------------------------
  # LOCAL OS DISK SERIAL NUMBERS
  # REPLACE THESE SIX VALUES
  # ----------------------------------------------------------------------
  export MASTER0_DISK_SERIAL='<MASTER0_DISK_SERIAL>'
  export MASTER1_DISK_SERIAL='<MASTER1_DISK_SERIAL>'
  export MASTER2_DISK_SERIAL='<MASTER2_DISK_SERIAL>'

  export WORKER0_DISK_SERIAL='<WORKER0_DISK_SERIAL>'
  export WORKER1_DISK_SERIAL='<WORKER1_DISK_SERIAL>'
  export WORKER2_DISK_SERIAL='<WORKER2_DISK_SERIAL>'

  # ----------------------------------------------------------------------
  # DISCONNECTED REGISTRY
  # REPLACE THESE VALUES WITH THE REAL MIRROR VALUES
  # ----------------------------------------------------------------------
  export MIRROR_REGISTRY='<REGISTRY_FQDN:PORT>'

  export MIRROR_OCP_RELEASE='<EXACT_MIRRORED_OCP_RELEASE_REPOSITORY>'
  export MIRROR_OCP_ART='<EXACT_MIRRORED_OCP_ART_REPOSITORY>'

  export RELEASE_IMAGE='<EXACT_MIRRORED_4.21.26_RELEASE_IMAGE>'

  # ----------------------------------------------------------------------
  # FILES
  # ----------------------------------------------------------------------
  export PULL_SECRET="$HOME/pull-secret.json"
  export MIRROR_CA="$HOME/mirror-registry-ca.crt"

  export OCMIRROR_WORKSPACE='<PATH_TO_OC_MIRROR_WORKSPACE>'

  export INSTALL_DIR="$HOME/ocpcluster-install"
  EOF
  ```

Load it:

  ```bash
  source $HOME/ocpcluster-vars.sh
  ```

---

#### 8. Collect the MAC Address and OS Disk of Every Server

Before creating agent-config.yaml, physically verify each host.

On each server, boot an existing Linux environment or suitable live environment and run:

  ```bash
  ip -br link
  ```

Example:

  ```text
  eno1    UP    00:11:22:33:44:01
  ```

Record the MAC.

Then:

  ```bash
  lsblk -d -o NAME,SIZE,MODEL,SERIAL,WWN,TRAN
  ```

Example:

  ```text
  NAME   SIZE MODEL                  SERIAL             WWN
  sda    447G PERC-H755             LOCALDISK0001
  sdb      4T IBM-SAN-LUN           6005076...
  ```

For the OCP boot disk, record the local physical/RAID disk serial.

Red Hat supports stable rootDeviceHints such as serialNumber and wwn; serialNumber must match exactly.

Use the local OS disk (not a SAN LUN)

Update:

  ```bash
  vi $HOME/ocpcluster-vars.sh
  ```

and replace:

  ```text
  <MASTER0_MAC>
  ...
  <WORKER2_MAC>

  <MASTER0_DISK_SERIAL>
  ...
  <WORKER2_DISK_SERIAL>
  ```

Then reload:

  ```text
  source $HOME/ocpcluster-vars.sh
  ```

Check:

  ```text
  env | grep -E '_(MAC|DISK_SERIAL)=' | sort
  ```

There should be no <...> values remaining for these variables.

---

#### 9. Identify the oc-mirror v2 Release Mappings

The actual mirroring is already done.

Now identify the exact OpenShift release mirror repositories generated by oc-mirror v2.

Look at:

```bash
ls -lah \
"${OCMIRROR_WORKSPACE}/working-dir/cluster-resources"
```

Search for the OpenShift release repositories:

```bash
grep -R -n -A6 -B2 \
'quay.io/openshift-release-dev/ocp-' \
"${OCMIRROR_WORKSPACE}/working-dir/cluster-resources"
```

We are looking specifically for these two source repositories:

```bash
quay.io/openshift-release-dev/ocp-release
```

and:

```bash
quay.io/openshift-release-dev/ocp-v4.0-art-dev
```

oc-mirror v2 creates ImageDigestMirrorSet/ImageTagMirrorSet and catalog resources under working-dir/cluster-resources; the Agent-based Installer still requires the relevant release repository mappings to be supplied through imageContentSources during installation.

For example, the generated mapping might conceptually look like:

  ```yaml
  - source: quay.io/openshift-release-dev/ocp-release
    mirrors:
    - registry.example.com:8443/openshift/release-images

  - source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
    mirrors:
    - registry.example.com:8443/openshift/release
  ```

Use your real values, not these examples.

Edit:

```bash
vi $HOME/ocpcluster-vars.sh
```

Set:

```text
export MIRROR_REGISTRY='registry.example.com:8443'
```

for example.

Then:

```text
export MIRROR_OCP_RELEASE='registry.example.com:8443/openshift/release-images'
export MIRROR_OCP_ART='registry.example.com:8443/openshift/release'
```

 Use your real values from oc-mirror v2 output says.

Reload:

```bash
source $HOME/ocpcluster-vars.sh
```

---

#### 10. Configure Trust for the Mirror Registry on the Installation Host

Confirm the CA exists:

  ```text
  ls -l "${MIRROR_CA}"
  ```

Inspect it:

  ```bash
  openssl x509 \
      -in "${MIRROR_CA}" \
      -noout \
      -subject \
      -issuer \
      -dates
  ```

Install it in the RHEL system trust:

  ```
  sudo cp "${MIRROR_CA}" \
      /etc/pki/ca-trust/source/anchors/mirror-registry-ca.crt
  ```

Run:

  ```bash
  sudo update-ca-trust
  ```

Test the registry:

  ```bash
  curl -sS \
      -o /dev/null \
      -w 'HTTP %{http_code}\n' \
      "https://${MIRROR_REGISTRY}/v2/"
  ```

Typical valid results are:

```text
HTTP 200 (successful request)

or:

HTTP 401 (means TLS/network connectivity works but authentication is required)
```

A certificate verification error is not acceptable.

---

#### 11. Verify the Pull Secret

Validate the JSON:

  ```bash
  jq . "${PULL_SECRET}" >/dev/null
  ```

Check return code:

  ```bash
  echo $?
  ```

Expected:

  ```text
  0
  ```

List registry entries:

  ```bash
  jq -r '.auths | keys[]' "${PULL_SECRET}"
  ```

Verify that the disconnected registry is present.

You can specifically test:

  ```bash
  jq -e \
      --arg registry "${MIRROR_REGISTRY}" \
      '.auths[$registry] != null' \
      "${PULL_SECRET}"
  ```

If that succeeds:

  ```bash
  echo $?
  ```

returns:

  ```text
  0
  ```

If the mirror credentials are not present, add them:

  ```bash
  podman login \
      --authfile "${PULL_SECRET}" \
      "${MIRROR_REGISTRY}"
  ```

Enter the mirror registry username/password when prompted.

Then verify again:

  ```bash
  jq -r '.auths | keys[]' "${PULL_SECRET}"
  ```

---

#### 12. Identify the Exact Mirrored 4.21.26 Release Image

We need the exact release-image reference for:

  ```text
  4.21.26
  x86_64
  ```

It will resemble:

  ```text
  registry.example.com:8443/openshift/release-images:4.21.26-x86_64
  ```

but **do not guess the path**.

Use the exact value resulting from your mirror.

Edit:

  ```bash
  vi $HOME/ocpcluster-vars.sh
  ```

Set:

  ```bash
  export RELEASE_IMAGE='registry.example.com:8443/openshift/release-images:4.21.26-x86_64'
  ```

using your actual registry/repository.

Reload:

  ```bash
  source $HOME/ocpcluster-vars.sh
  ```

Verify that it exists:

  ```bash
  oc adm release info \
      -a "${PULL_SECRET}" \
      "${RELEASE_IMAGE}"
  ```

Look at the beginning:

  ```bash
  oc adm release info \
      -a "${PULL_SECRET}" \
      "${RELEASE_IMAGE}" \
      | head -20
  ```

It must identify release:

  ```text
  4.21.26
  ```

**STOP if the release is not 4.21.26.**

---

#### 13. Extract the 4.21.26 Installer from the Mirrored Release

Create a tools directory:

  ```bash
  mkdir -p $HOME/ocp42126-tools
  ```

Enter it:

  ```bash
  cd $HOME/ocp42126-tools
  ```

Extract `openshift-install` directly from the mirrored 4.21.26 release:

  ```bash
  oc adm release extract \
      -a "${PULL_SECRET}" \
      --command=openshift-install \
      "${RELEASE_IMAGE}"
  ```

Red Hat explicitly recommends extracting the installation program from the mirrored release so the installer is pinned to the version that was mirrored.

Check:

  ```bash
  ls -lh openshift-install
  ```

Make executable:

  ```bash
  chmod 0755 openshift-install
  ```

Install:

  ```bash
  sudo install \
      -m 0755 \
      openshift-install \
      /usr/local/bin/openshift-install
  ```

Verify:

  ```bash
  openshift-install version
  ```

It must show:

  ```text
  openshift-install 4.21.26
  ```

Also inspect its release image:

  ```bash
  openshift-install version | grep -i 'release image'
  ```

It should correspond to the intended 4.21.26 payload.

**Do not continue with a 4.21.25, 4.21.27, 4.21.28, etc. installer.**

This procedure is intentionally pinned to:

  ```text
  4.21.26
  ```

---

#### 14. Create the SSH Key

Check whether one already exists:

  ```bash
  ls -l ~/.ssh/id_ed25519.pub
  ```

If not:

  ```bash
  ssh-keygen \
      -t ed25519 \
      -N '' \
      -f ~/.ssh/id_ed25519
  ```

Verify:

  ```bash
  cat ~/.ssh/id_ed25519.pub
  ```

This key gives us SSH access as `core` for troubleshooting.

---

#### 15. Create a Fresh Installation Directory

Set restrictive permissions for files created from this point:

  ```bash
  umask 077
  ```

Check whether the directory already exists:

  ```bash
  ls -ld "${INSTALL_DIR}" 2>/dev/null
  ```

If this is a **new installation**, it should not contain assets from a previous cluster attempt.

Create it:

  ```bash
  mkdir -p "${INSTALL_DIR}"
  ```

Check:

  ```bash
  ls -la "${INSTALL_DIR}"
  ```

It should be empty.

---

#### 16. Load the Pull Secret, SSH Key and Registry CA

Run:

  ```bash
  export PULL_SECRET_JSON="$(jq -c . "${PULL_SECRET}")"
  ```

Run:

  ```bash
  export SSH_PUBLIC_KEY="$(cat ~/.ssh/id_ed25519.pub)"
  ```

Check:

  ```bash
  echo "${SSH_PUBLIC_KEY}"
  ```

Do not print the pull secret unnecessarily.

---

#### 17. Create install-config.yaml

Run exactly:

  ```bash
  cat > "${INSTALL_DIR}/install-config.yaml" <<EOF
  apiVersion: v1

  baseDomain: ${BASE_DOMAIN}

  metadata:
    name: ${CLUSTER_NAME}

  compute:
  - architecture: amd64
    hyperthreading: Enabled
    name: worker
    replicas: 3

  controlPlane:
    architecture: amd64
    hyperthreading: Enabled
    name: master
    replicas: 3

  networking:
    clusterNetwork:
    - cidr: 10.128.0.0/14
      hostPrefix: 23

    machineNetwork:
    - cidr: ${MACHINE_NETWORK}

    networkType: OVNKubernetes

    serviceNetwork:
    - 172.30.0.0/16

  platform:
    baremetal:
      loadBalancer:
        type: OpenShiftManagedDefault

      apiVIPs:
      - ${API_VIP}

      ingressVIPs:
      - ${INGRESS_VIP}

  fips: false

  pullSecret: >-
    ${PULL_SECRET_JSON}

  sshKey: '${SSH_PUBLIC_KEY}'

  additionalTrustBundle: |
  $(sed 's/^/  /' "${MIRROR_CA}")

  imageContentSources:
  - mirrors:
    - ${MIRROR_OCP_RELEASE}
    source: quay.io/openshift-release-dev/ocp-release

  - mirrors:
    - ${MIRROR_OCP_ART}
    source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
  EOF
  ```

The important architecture section is now explicitly:

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

There is:

  ```text
  NO platform: none
  NO UserManaged
  NO external HAProxy
  NO external F5
  ```

Red Hat's 4.21 API definition describes `OpenShiftManagedDefault` as deploying the static components responsible for API and Ingress traffic load balancing, and it is the default bare-metal load-balancer mode.

For disconnected Agent installations, Red Hat requires the release mirror information in `imageContentSources` and the mirror registry certificate in `additionalTrustBundle`.

---

#### 18. Inspect install-config.yaml

Run:

  ```bash
  cat "${INSTALL_DIR}/install-config.yaml"
  ```

Check carefully:

  ```text
  baseDomain             example.com
  metadata.name          ocpcluster

  worker replicas        3
  master replicas        3

  machineNetwork         192.168.50.0/24
  clusterNetwork         10.128.0.0/14
  serviceNetwork         172.30.0.0/16

  platform               baremetal
  loadBalancer           OpenShiftManagedDefault

  apiVIP                 192.168.50.20
  ingressVIP             192.168.50.21

  mirror repositories    CORRECT
  CA                     CORRECT
  ```

---

#### 19. Create agent-config.yaml

The Agent configuration identifies the physical servers by MAC address and supplies their static network configuration.

`master-0` will be the rendezvous host:

  ```text
  master-0.ocpcluster.example.com
  192.168.50.31
  ```

The rendezvous IP must belong to a control-plane host.

Create the file:

  ```bash
  cat > "${INSTALL_DIR}/agent-config.yaml" <<EOF
  apiVersion: v1beta1
  kind: AgentConfig

  metadata:
    name: ${CLUSTER_NAME}

  rendezvousIP: ${MASTER0_IP}

  additionalNTPSources:
  - ${NTP_SERVER}

  hosts:

  # =====================================================================
  # MASTER 0 - RENDEZVOUS HOST
  # =====================================================================
  - hostname: master-0.ocpcluster.example.com
    role: master

    interfaces:
    - name: ${NODE_INTERFACE}
      macAddress: ${MASTER0_MAC}

    rootDeviceHints:
      serialNumber: "${MASTER0_DISK_SERIAL}"

    networkConfig:
      interfaces:
      - name: ${NODE_INTERFACE}
        type: ethernet
        state: up
        mac-address: ${MASTER0_MAC}
        ipv4:
          enabled: true
          address:
          - ip: ${MASTER0_IP}
            prefix-length: ${PREFIX_LENGTH}
          dhcp: false
        ipv6:
          enabled: false

      dns-resolver:
        config:
          server:
          - ${DNS_SERVER}

      routes:
        config:
        - destination: 0.0.0.0/0
          next-hop-address: ${GATEWAY}
          next-hop-interface: ${NODE_INTERFACE}
          table-id: 254


  # =====================================================================
  # MASTER 1
  # =====================================================================
  - hostname: master-1.ocpcluster.example.com
    role: master

    interfaces:
    - name: ${NODE_INTERFACE}
      macAddress: ${MASTER1_MAC}

    rootDeviceHints:
      serialNumber: "${MASTER1_DISK_SERIAL}"

    networkConfig:
      interfaces:
      - name: ${NODE_INTERFACE}
        type: ethernet
        state: up
        mac-address: ${MASTER1_MAC}
        ipv4:
          enabled: true
          address:
          - ip: ${MASTER1_IP}
            prefix-length: ${PREFIX_LENGTH}
          dhcp: false
        ipv6:
          enabled: false

      dns-resolver:
        config:
          server:
          - ${DNS_SERVER}

      routes:
        config:
        - destination: 0.0.0.0/0
          next-hop-address: ${GATEWAY}
          next-hop-interface: ${NODE_INTERFACE}
          table-id: 254


  # =====================================================================
  # MASTER 2
  # =====================================================================
  - hostname: master-2.ocpcluster.example.com
    role: master

    interfaces:
    - name: ${NODE_INTERFACE}
      macAddress: ${MASTER2_MAC}

    rootDeviceHints:
      serialNumber: "${MASTER2_DISK_SERIAL}"

    networkConfig:
      interfaces:
      - name: ${NODE_INTERFACE}
        type: ethernet
        state: up
        mac-address: ${MASTER2_MAC}
        ipv4:
          enabled: true
          address:
          - ip: ${MASTER2_IP}
            prefix-length: ${PREFIX_LENGTH}
          dhcp: false
        ipv6:
          enabled: false

      dns-resolver:
        config:
          server:
          - ${DNS_SERVER}

      routes:
        config:
        - destination: 0.0.0.0/0
          next-hop-address: ${GATEWAY}
          next-hop-interface: ${NODE_INTERFACE}
          table-id: 254


  # =====================================================================
  # WORKER 0
  # =====================================================================
  - hostname: worker-0.ocpcluster.example.com
    role: worker

    interfaces:
    - name: ${NODE_INTERFACE}
      macAddress: ${WORKER0_MAC}

    rootDeviceHints:
      serialNumber: "${WORKER0_DISK_SERIAL}"

    networkConfig:
      interfaces:
      - name: ${NODE_INTERFACE}
        type: ethernet
        state: up
        mac-address: ${WORKER0_MAC}
        ipv4:
          enabled: true
          address:
          - ip: ${WORKER0_IP}
            prefix-length: ${PREFIX_LENGTH}
          dhcp: false
        ipv6:
          enabled: false

      dns-resolver:
        config:
          server:
          - ${DNS_SERVER}

      routes:
        config:
        - destination: 0.0.0.0/0
          next-hop-address: ${GATEWAY}
          next-hop-interface: ${NODE_INTERFACE}
          table-id: 254


  # =====================================================================
  # WORKER 1
  # =====================================================================
  - hostname: worker-1.ocpcluster.example.com
    role: worker

    interfaces:
    - name: ${NODE_INTERFACE}
      macAddress: ${WORKER1_MAC}

    rootDeviceHints:
      serialNumber: "${WORKER1_DISK_SERIAL}"

    networkConfig:
      interfaces:
      - name: ${NODE_INTERFACE}
        type: ethernet
        state: up
        mac-address: ${WORKER1_MAC}
        ipv4:
          enabled: true
          address:
          - ip: ${WORKER1_IP}
            prefix-length: ${PREFIX_LENGTH}
          dhcp: false
        ipv6:
          enabled: false

      dns-resolver:
        config:
          server:
          - ${DNS_SERVER}

      routes:
        config:
        - destination: 0.0.0.0/0
          next-hop-address: ${GATEWAY}
          next-hop-interface: ${NODE_INTERFACE}
          table-id: 254


  # =====================================================================
  # WORKER 2
  # =====================================================================
  - hostname: worker-2.ocpcluster.example.com
    role: worker

    interfaces:
    - name: ${NODE_INTERFACE}
      macAddress: ${WORKER2_MAC}

    rootDeviceHints:
      serialNumber: "${WORKER2_DISK_SERIAL}"

    networkConfig:
      interfaces:
      - name: ${NODE_INTERFACE}
        type: ethernet
        state: up
        mac-address: ${WORKER2_MAC}
        ipv4:
          enabled: true
          address:
          - ip: ${WORKER2_IP}
            prefix-length: ${PREFIX_LENGTH}
          dhcp: false
        ipv6:
          enabled: false

      dns-resolver:
        config:
          server:
          - ${DNS_SERVER}

      routes:
        config:
        - destination: 0.0.0.0/0
          next-hop-address: ${GATEWAY}
          next-hop-interface: ${NODE_INTERFACE}
          table-id: 254
  EOF
  ```

This is NMState static networking. The Agent uses each configured MAC address to identify which physical host receives which configuration. Red Hat recommends explicitly assigning `master`/`worker` roles rather than allowing random role assignment.

---

#### 20. Review agent-config.yaml

Run:

```bash
cat "${INSTALL_DIR}/agent-config.yaml"
```

Check that each host has exactly the expected:

```text
hostname
role
MAC address
OS disk serial
static IP
prefix
DNS
gateway
interface
```

The most important mapping to check is:

```text
master-0 MAC -> 192.168.50.31 -> master-0 disk
master-1 MAC -> 192.168.50.32 -> master-1 disk
master-2 MAC -> 192.168.50.33 -> master-2 disk

worker-0 MAC -> 192.168.50.41 -> worker-0 disk
worker-1 MAC -> 192.168.50.42 -> worker-1 disk
worker-2 MAC -> 192.168.50.43 -> worker-2 disk
```

---

#### 21. Check for Forgotten Placeholders

This is mandatory.

Run:

```bash
grep -nE '<[^>]+>' \
    "${INSTALL_DIR}/install-config.yaml" \
    "${INSTALL_DIR}/agent-config.yaml"
```

Expected:

```text
NO OUTPUT
```

Also check our variable file:

```bash
grep -nE '<[^>]+>' \
    "$HOME/ocpcluster-vars.sh"
```

Expected:

```text
NO OUTPUT
```

If anything is returned, **STOP and correct it**.

---

#### 22. Verify That All MAC Addresses Are Unique

Run:

```bash
grep -i 'macAddress:' \
    "${INSTALL_DIR}/agent-config.yaml"
```

Then:

```bash
grep -i 'macAddress:' \
    "${INSTALL_DIR}/agent-config.yaml" \
    | awk '{print $2}' \
    | sort \
    | uniq -d
```

Expected:

```text
NO OUTPUT
```

Agent ISO validation requires the configured host interface MAC addresses to be unique.

---

#### 23. Make a Backup Before Generating the ISO

Create a backup directory **outside** the installer directory:

```bash
mkdir -p $HOME/ocpcluster-config-backup
```

Copy the files:

```bash
cp "${INSTALL_DIR}/install-config.yaml" \
   $HOME/ocpcluster-config-backup/
```

```bash
cp "${INSTALL_DIR}/agent-config.yaml" \
   $HOME/ocpcluster-config-backup/
```

Protect them:

```bash
chmod 600 \
    $HOME/ocpcluster-config-backup/install-config.yaml \
    $HOME/ocpcluster-config-backup/agent-config.yaml
```

This is important because the installation assets contain credentials.

---

#### 24. Final Pre-ISO DNS Test

Run:

```bash
for name in \
api.ocpcluster.example.com \
api-int.ocpcluster.example.com \
master-0.ocpcluster.example.com \
master-1.ocpcluster.example.com \
master-2.ocpcluster.example.com \
worker-0.ocpcluster.example.com \
worker-1.ocpcluster.example.com \
worker-2.ocpcluster.example.com \
test.apps.ocpcluster.example.com
do
    printf '%-50s ' "${name}"
    dig +short "${name}"
done
```

Expected:

```text
api.ocpcluster.example.com                        192.168.50.20
api-int.ocpcluster.example.com                    192.168.50.20
master-0.ocpcluster.example.com                   192.168.50.31
master-1.ocpcluster.example.com                   192.168.50.32
master-2.ocpcluster.example.com                   192.168.50.33
worker-0.ocpcluster.example.com                   192.168.50.41
worker-1.ocpcluster.example.com                   192.168.50.42
worker-2.ocpcluster.example.com                   192.168.50.43
test.apps.ocpcluster.example.com                  192.168.50.21
```

Do not proceed if this is wrong.

---

#### 25. Generate the Agent ISO

Now create the image:

```bash
openshift-install \
    --dir "${INSTALL_DIR}" \
    agent create image \
    --log-level=info
```

The Agent-based Installer validates the YAML before creating the ISO, including bare-metal VIP presence, host interfaces/MACs, and host roles.

If successful, check:

```bash
find "${INSTALL_DIR}" \
    -maxdepth 1 \
    -type f \
    -name 'agent*.iso' \
    -ls
```

For x86_64 we expect:

```text
agent.x86_64.iso
```

Check:

```bash
ls -lh "${INSTALL_DIR}/agent.x86_64.iso"
```

Generate a checksum:

```bash
sha256sum \
    "${INSTALL_DIR}/agent.x86_64.iso" \
    | tee "${INSTALL_DIR}/agent.x86_64.iso.sha256"
```

---

#### 26. Boot the Servers from the Agent ISO

Use:

```text
agent.x86_64.iso
```

on all six machines.

You can mount it through:

```text
BMC virtual media
Redfish virtual media
physical USB
other supported boot media
```

The **same ISO** is used for every host.

Boot:

```text
master-0
master-1
master-2
worker-0
worker-1
worker-2
```

The ISO identifies each physical machine using its configured MAC address and applies the corresponding static network configuration.

You do **not** manually configure:

```text
192.168.50.20
192.168.50.21
```

on any server.

---

#### 27. Recommended Boot Order

I recommend booting:

```text
1. master-0
2. master-1
3. master-2
4. worker-0
5. worker-1
6. worker-2
```

The critical point is that:

```text
master-0 = rendezvous node
master-0 = 192.168.50.31
```

All other nodes must be able to reach:

```text
192.168.50.31:8090/tcp
```

during discovery/bootstrap.

---

#### 28. Watch the Host Consoles During Initial Boot

On each host, verify that the Agent sees:

```text
Correct static IP
Correct gateway
Correct DNS
Correct hostname
Correct target disk
Release image reachable
Rendezvous host reachable
```

Particularly verify that each host can reach the **disconnected registry**.

If a host cannot pull the release image, do not ignore it.

Check:

```text
DNS
routing
gateway
registry certificate
pull-secret
mirror path
mirror mapping
firewall
```

---

#### 29. Monitor Bootstrap from the Installation Host

Run:

```bash
openshift-install \
    --dir "${INSTALL_DIR}" \
    agent wait-for bootstrap-complete \
    --log-level=info
```

This command is optional but very useful because it tells us when the rendezvous/bootstrap phase has completed. The Agent workflow uses the rendezvous control-plane host temporarily for bootstrap before that host itself joins the permanent cluster.

Successful output should eventually indicate bootstrap completion.

---

#### 30. Monitor the Full Installation

Run:

```bash
openshift-install \
    --dir "${INSTALL_DIR}" \
    agent wait-for install-complete \
    --log-level=info
```

This is the definitive Agent-based installation monitoring command.

Eventually we want:

```text
INFO Cluster is installed
INFO Install complete!
```

---

#### 31. Configure KUBECONFIG

After successful installation:

```bash
export KUBECONFIG="${INSTALL_DIR}/auth/kubeconfig"
```

Check:

```bash
oc whoami
```

Expected:

```text
system:admin
```

---

#### 32. Confirm We Installed Exactly 4.21.26

Run:

```bash
oc get clusterversion
```

Then:

```bash
oc get clusterversion version \
    -o jsonpath='{.status.desired.version}{"\n"}'
```

Expected:

```text
4.21.26
```

If the desired version is not `4.21.26`, investigate before continuing.

---

#### 33. Verify All Nodes

Run:

```bash
oc get nodes -o wide
```

We expect six nodes:

```text
master-0.ocpcluster.example.com
master-1.ocpcluster.example.com
master-2.ocpcluster.example.com

worker-0.ocpcluster.example.com
worker-1.ocpcluster.example.com
worker-2.ocpcluster.example.com
```

and eventually all should report:

```text
Ready
```

Check roles:

```bash
oc get nodes \
    -L node-role.kubernetes.io/master,node-role.kubernetes.io/worker
```

---

#### 34. Verify Cluster Operators

Run:

```bash
oc get clusteroperators
```

or:

```bash
oc get co
```

The target steady state for core operators is:

```text
AVAILABLE     True
PROGRESSING   False
DEGRADED      False
```

Some operators can legitimately take time to converge immediately after installation.

---

#### 35. Verify MachineConfigPools

Run:

```bash
oc get mcp
```

Eventually we want the master and worker pools to be stable:

```text
UPDATED      True
UPDATING     False
DEGRADED     False
```

---

#### 36. Check for Failed Pods

Run:

```bash
oc get pods -A \
    --field-selector=status.phase!=Running,status.phase!=Succeeded
```

Investigate unexpected:

```text
CrashLoopBackOff
ImagePullBackOff
ErrImagePull
Pending
Failed
```

Particularly watch for `ImagePullBackOff`, because in a disconnected deployment that frequently indicates an incomplete mirror configuration, registry trust problem or missing image.

---

#### 37. Verify the OpenShift-Managed API VIP

Check DNS:

```bash
dig +short api.ocpcluster.example.com
```

Expected:

```text
192.168.50.20
```

Test API access:

```bash
curl -k \
    https://api.ocpcluster.example.com:6443/version
```

A Kubernetes version JSON response is expected.

Also:

```bash
oc version
```

---

#### 38. Verify the OpenShift-Managed Ingress VIP

Check:

```bash
dig +short \
    console-openshift-console.apps.ocpcluster.example.com
```

Expected:

```text
192.168.50.21
```

Get the console route:

```bash
oc get route console \
    -n openshift-console
```

Expected host:

```text
console-openshift-console.apps.ocpcluster.example.com
```

Test:

```bash
curl -k -I \
    https://console-openshift-console.apps.ocpcluster.example.com
```

---

#### 39. Verify the Load Balancer Mode Actually Installed

This is a very useful sanity check.

Run:

```bash
oc get infrastructure cluster -o yaml
```

Look under the bare-metal platform status.

For easier inspection:

```bash
oc get infrastructure cluster \
    -o json \
    | jq '.status.platformStatus.baremetal'
```

We want the cluster to reflect the bare-metal OpenShift-managed load-balancer configuration.

The 4.21 Infrastructure API defines `OpenShiftManagedDefault` as the bare-metal mode where the static components responsible for API and Ingress load balancing are deployed by OpenShift.

---

#### 40. Obtain the kubeadmin Password

Run:

```bash
cat "${INSTALL_DIR}/auth/kubeadmin-password"
```

Store this securely.

Do not delete the installation directory.

---

#### 41. Apply the oc-mirror v2 Cluster Resources

The base cluster is now running.

Now apply the resources created by the **same oc-mirror v2 operation used to populate the disconnected registry**.

First inspect:

```bash
find \
"${OCMIRROR_WORKSPACE}/working-dir/cluster-resources" \
-maxdepth 1 \
-type f \
-print
```

You should see resources such as:

```text
ImageDigestMirrorSet
ImageTagMirrorSet
CatalogSource and/or ClusterCatalog
signature resources
other oc-mirror generated resources
```

oc-mirror v2 automatically generates IDMS/ITMS and catalog resources for use by the disconnected cluster.

Apply the generated resources:

```bash
oc apply -f \
"${OCMIRROR_WORKSPACE}/working-dir/cluster-resources"
```

Red Hat documents applying the oc-mirror v2 `working-dir/cluster-resources` directory after mirroring.

---

#### 42. Verify the ImageDigestMirrorSets

Run:

```bash
oc get imagedigestmirrorset
```

Detailed:

```bash
oc get imagedigestmirrorset -o yaml
```

Look for your disconnected registry.

---

#### 43. Verify ImageTagMirrorSets

Run:

```bash
oc get imagetagmirrorset
```

If oc-mirror generated ITMS resources, they should appear here.

---

#### 44. Verify Disconnected Catalog Resources

Check traditional catalog sources:

```bash
oc get catalogsource \
    -n openshift-marketplace
```

Also determine whether `ClusterCatalog` is available:

```bash
oc api-resources \
    | grep -i clustercatalog
```

If present:

```bash
oc get clustercatalog
```

---

#### 45. Disable Default Connected OperatorHub Sources

Because this cluster is fully disconnected, disable the normal connected catalog sources.

Run:

```bash
oc patch OperatorHub cluster \
    --type json \
    -p '[{"op":"add","path":"/spec/disableAllDefaultSources","value":true}]'
```

Red Hat requires the default catalogs to be disabled for restricted-network environments when local mirrored catalogs are used.

Verify:

```bash
oc get operatorhub cluster \
    -o jsonpath='{.spec.disableAllDefaultSources}{"\n"}'
```

Expected:

```text
true
```

---

#### 46. Final Disconnected Health Check

Run:

```bash
oc get clusterversion
```

Then:

```bash
oc get nodes
```

Then:

```bash
oc get co
```

Then:

```bash
oc get mcp
```

Then:

```bash
oc get imagedigestmirrorset
```

Then:

```bash
oc get imagetagmirrorset
```

Then:

```bash
oc get catalogsource -n openshift-marketplace
```

Then:

```bash
oc get pods -A \
    --field-selector=status.phase!=Running,status.phase!=Succeeded
```

---

#### 47. Acceptance Criteria

Do not start the major Day-2 components until the base cluster passes these checks.

- Version

```text
OCP = 4.21.26
```

- Nodes

```text
3 masters = Ready
3 workers = Ready
```

- Cluster operators

Core operators should normally settle to:

```text
Available=True
Progressing=False
Degraded=False
```

- MachineConfigPools

```text
Updated=True
Updating=False
Degraded=False
```

- API

```text
api.ocpcluster.example.com
        |
        +-- 192.168.50.20
        |
        +-- :6443 reachable
```

- Ingress

```text
*.apps.ocpcluster.example.com
        |
        +-- 192.168.50.21
        |
        +-- console route reachable
```

- Disconnected registry

```text
IDMS/ITMS point to local registry
local catalogs are visible
default connected catalogs disabled
no unexpected ImagePullBackOff
```

---

#### 48. If Bootstrap Fails

Do not rebuild immediately.

First run:

```bash
openshift-install \
    --dir "${INSTALL_DIR}" \
    agent wait-for bootstrap-complete \
    --log-level=debug
```

Collect the rendezvous host data:

```bash
ssh core@192.168.50.31 \
    agent-gather -O \
    > agent-gather.tar.xz
```

Check:

```bash
ls -lh agent-gather.tar.xz
```

Red Hat recommends `agent-gather` from the rendezvous host for failed Agent-based installations.

---

#### 49. If Installation Fails After Bootstrap

Run:

```bash
openshift-install \
    --dir "${INSTALL_DIR}" \
    agent wait-for install-complete \
    --log-level=debug
```

If the API is available:

```bash
export KUBECONFIG="${INSTALL_DIR}/auth/kubeconfig"
```

Then:

```bash
oc get nodes
```

```bash
oc get co
```

```bash
oc get pods -A
```

And collect:

```bash
oc adm must-gather
```

---

#### 50. Most Likely Things to Check if Installation Fails

Check them in this order:

  ```text
  1. Wrong MAC address
  2. Wrong OS-disk serial number
  3. Wrong static IP
  4. Duplicate IP
  5. Wrong gateway
  6. DNS failure
  7. Incorrect API/Ingress DNS
  8. VIP already in use
  9. TCP/8090 blocked to master-0
  10. Registry DNS failure
  11. Registry CA not trusted
  12. Pull secret does not contain registry credentials
  13. Incorrect imageContentSources
  14. Incorrect mirrored repository path
  15. 4.21.26 release image missing from mirror
  16. Host cannot reach disconnected registry
  ```

---

#### 51. What We Deliberately Do NOT Configure

There is **no external load balancer**.

Do not configure:

```text
F5
external HAProxy
A10
AVI
external API LB
external Ingress LB
```

There is no:

```yaml
platform:
  none: {}
```

There is no:

```yaml
loadBalancer:
  type: UserManaged
```

There is no BMC configuration in `install-config.yaml`.

There is no provisioning network configuration required for this manually booted Agent ISO workflow.

Our architecture is:

```text
                         OCP 4.21.26
                              |
                    Agent-based Installer
                              |
                    platform: baremetal
                              |
                 OpenShiftManagedDefault
                              |
             +----------------+----------------+
             |                                 |
         API VIP                           Ingress VIP
     192.168.50.20                       192.168.50.21
             |                                 |
       OpenShift manages                  OpenShift manages
       API balancing                     Ingress traffic
             |                                 |
     master-0/1/2                     Ingress Controller
```

---

#### 52. MetalLB Comes Later

**Do not install MetalLB as part of the base cluster installation.**

First make sure the cluster is completely healthy.

After that, MetalLB becomes a separate Day-2 activity.

For example:

```text
192.168.50.20       API VIP
192.168.50.21       Ingress VIP

192.168.50.31-33    Masters
192.168.50.41-43    Workers

192.168.50.100-150  MetalLB pool
```

Never include:

```text
192.168.50.20
192.168.50.21
```

inside the MetalLB address pool.

MetalLB runs inside the cluster and can function as a user-managed load balancer for Kubernetes services, but that is separate from the `OpenShiftManagedDefault` Day-0 mechanism being used here.

---

#### 53. Final Installation Sequence

The complete sequence is therefore:

  ```text
  1.  Mirror OCP 4.21.26                       DONE
  2.  Prepare disconnected registry            DONE
  3.  Configure DNS                            DONE
  4.  Reserve API VIP                          192.168.50.20
  5.  Reserve Ingress VIP                      192.168.50.21
  6.  Verify DNS
  7.  Verify VIPs are free
  8.  Verify TCP/8090 to rendezvous
  9.  Collect node MAC addresses
  10. Collect local OS-disk serial numbers
  11. Trust mirror registry CA
  12. Verify pull secret
  13. Find exact oc-mirror v2 mirror mappings
  14. Verify mirrored OCP 4.21.26 release
  15. Extract 4.21.26 openshift-install
  16. Generate SSH key
  17. Create install-config.yaml
  18. Create agent-config.yaml
  19. Validate all configuration
  20. Back up YAML files
  21. Generate agent.x86_64.iso
  22. Boot master-0 from ISO
  23. Boot master-1 and master-2
  24. Boot worker-0, worker-1 and worker-2
  25. Monitor bootstrap
  26. Monitor installation
  27. Export kubeconfig
  28. Verify OCP = 4.21.26
  29. Verify all six nodes
  30. Verify cluster operators
  31. Verify MCPs
  32. Verify API VIP
  33. Verify Ingress VIP
  34. Apply oc-mirror v2 cluster-resources
  35. Disable default OperatorHub sources
  36. Verify disconnected operation
  37. Declare base OCP installation healthy
  38. Only then start Day-2 configuration
  39. Install OpenShift Virtualization / required Operators
  40. Configure IBM Fusion Access for SAN
  41. Configure MetalLB using its own IP pool
  ```

✅ At **step 37**, the disconnected base OpenShift installation is complete.
