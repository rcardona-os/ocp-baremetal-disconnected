#### 1. Verify OpenShift Virtualization is visible in the local catalog

```bash
oc get packagemanifest \
  kubevirt-hyperconverged \
  -n openshift-marketplace
```

If it returns the package, get the local CatalogSource:

```bash
export VIRT_CATALOG=$(oc get packagemanifest \
  kubevirt-hyperconverged \
  -n openshift-marketplace \
  -o jsonpath='{.status.catalogSource}')
```

Check it:

```bash
echo "${VIRT_CATALOG}"
```

In our disconnected environment it should be the **local mirrored Red Hat catalog**, not a connected source.

Verify the catalog is READY:

```bash
oc get catalogsource "${VIRT_CATALOG}" \
  -n openshift-marketplace \
  -o jsonpath='{.status.connectionState.lastObservedState}{"\n"}'
```

Expected:

```text
READY
```

---

#### 2. Verify the stable OpenShift Virtualization version

List channels:

```bash
oc get packagemanifest \
  kubevirt-hyperconverged \
  -n openshift-marketplace \
  -o jsonpath='{range .status.channels[*]}{.name}{" -> "}{.currentCSV}{"\n"}{end}'
```

Get the current CSV from `stable`:

```bash
export VIRT_CSV=$(oc get packagemanifest \
  kubevirt-hyperconverged \
  -n openshift-marketplace \
  -o json | \
  jq -r '.status.channels[] | select(.name=="stable") | .currentCSV')
```

Check:

```bash
echo "${VIRT_CSV}"
```

It should resemble:

```text
kubevirt-hyperconverged-operator.v4.21.x
```

---

#### 3. Verify hardware virtualization on the worker nodes

List workers:

```bash
oc get nodes -l node-role.kubernetes.io/worker
```

For each worker:

```bash
for node in $(oc get nodes \
  -l node-role.kubernetes.io/worker \
  -o jsonpath='{.items[*].metadata.name}')
do
  echo "===== ${node} ====="

  oc debug node/"${node}" -- \
    chroot /host sh -c \
    'test -c /dev/kvm && echo "KVM: OK" || echo "KVM: MISSING"'
done
```

Expected:

```text
KVM: OK
```

on every node intended to run VMs.

If `/dev/kvm` is missing, check BIOS/UEFI virtualization before going further.

---

#### 4. Install the OpenShift Virtualization Operator

Create:

```bash
cat > ocp-virtualization-subscription.yaml <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-cnv
  labels:
    openshift.io/cluster-monitoring: "true"
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: kubevirt-hyperconverged-group
  namespace: openshift-cnv
spec:
  targetNamespaces:
  - openshift-cnv
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: hco-operatorhub
  namespace: openshift-cnv
spec:
  source: ${VIRT_CATALOG}
  sourceNamespace: openshift-marketplace
  name: kubevirt-hyperconverged
  channel: stable
  startingCSV: ${VIRT_CSV}
  installPlanApproval: Automatic
EOF
```

Review it:

```bash
cat ocp-virtualization-subscription.yaml
```

Apply:

```bash
oc apply -f ocp-virtualization-subscription.yaml
```

---

#### 5. Watch the Operator installation

```bash
watch oc get csv -n openshift-cnv
```

Expected:

```text
OpenShift Virtualization    ...    Succeeded
```

Exit with:

```text
Ctrl-C
```

Check:

```bash
oc get subscription -n openshift-cnv
```

and:

```bash
oc get installplan -n openshift-cnv
```

---

#### 6. Check for disconnected image-pull problems

Before creating the HCO:

```bash
oc get pods -n openshift-cnv
```

Look specifically for:

```text
ImagePullBackOff
ErrImagePull
CrashLoopBackOff
```

Also:

```bash
oc get events -n openshift-cnv \
  --sort-by='.lastTimestamp' | tail -30
```

If any image tries to reach:

```text
registry.redhat.io
quay.io
```

directly and fails, stop and fix the corresponding mirror rule/image first.

---

#### 7. Create the HyperConverged instance

This actually deploys OpenShift Virtualization.

```bash
cat > hyperconverged.yaml <<'EOF'
apiVersion: hco.kubevirt.io/v1beta1
kind: HyperConverged
metadata:
  name: kubevirt-hyperconverged
  namespace: openshift-cnv
spec: {}
EOF
```

Apply:

```bash
oc apply -f hyperconverged.yaml
```

---

#### 8. Wait for OpenShift Virtualization to become healthy

Watch:

```bash
watch oc get hco,pods -n openshift-cnv
```

Eventually the HCO should be deployed and the virtualization pods should be Running.

Exit:

```text
Ctrl-C
```

Check the HCO conditions:

```bash
oc get hco kubevirt-hyperconverged \
  -n openshift-cnv \
  -o json | \
  jq -r '.status.conditions[] | {type,status}'
```

Expected:

```text
Available       True
Progressing     False
Degraded        False
ReconcileComplete True
```

Check version:

```bash
oc get hco kubevirt-hyperconverged \
  -n openshift-cnv \
  -o json | jq '.status.versions'
```

---

#### 9. Verify all virtualization components

```bash
oc get pods -n openshift-cnv -o wide
```

Check particularly:

```text
virt-api
virt-controller
virt-handler
cdi-apiserver
cdi-deployment
cdi-uploadproxy
ssp-operator
cluster-network-addons-operator
hyperconverged-cluster-operator
```

They should settle to Running.

Also:

```bash
oc get kubevirt -n openshift-cnv
```

and:

```bash
oc get cdi -n openshift-cnv
```

---

#### 10. Verify the VM storage

In this case it uses **IBM Fusion Access for SAN**, not a separate virtualization storage stack.

List StorageClasses:

```bash
oc get storageclass
```

Then list CDI StorageProfiles:

```bash
oc get storageprofile
```

Identify the IBM Fusion Access for SAN StorageClass and set:

```bash
export VM_SC='<IBM_FUSION_ACCESS_SAN_STORAGECLASS>'
```

Check it:

```bash
oc get storageclass "${VM_SC}" -o yaml
```

Then:

```bash
oc get storageprofile "${VM_SC}" -o yaml
```

Pay attention to:

```yaml
claimPropertySets:
```

The StorageProfile should describe a valid:

```text
accessMode
volumeMode
```

for this storage.

Do not guess these values if the StorageProfile is incomplete.

---

#### 11. Perform a simple storage provisioning test

Create a project:

```bash
oc new-project vm-test
```

Create a test PVC:

```bash
cat > fusion-vm-storage-test.yaml <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: fusion-vm-storage-test
  namespace: vm-test
spec:
  storageClassName: ${VM_SC}
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
EOF
```

Apply:

```bash
oc apply -f fusion-vm-storage-test.yaml
```

Check:

```bash
oc get pvc -n vm-test
```

Expected:

```text
Bound
```

Delete the test PVC:

```bash
oc delete pvc fusion-vm-storage-test -n vm-test
```

If the IBM StorageProfile specifies a different access mode, use that instead.

---

#### 12. Install `virtctl`

After HCO deployment, OpenShift Virtualization exposes the client download.

Check:

```bash
oc get ConsoleCLIDownload \
  virtctl-clidownloads-kubevirt-hyperconverged \
  -o yaml
```

Also check the internal download route:

```bash
oc get route \
  hyperconverged-cluster-cli-download \
  -n openshift-cnv
```

For our x86_64 client:

```bash
export VIRTCTL_HOST=$(oc get route \
  hyperconverged-cluster-cli-download \
  -n openshift-cnv \
  -o jsonpath='{.spec.host}')
```

Download:

```bash
curl -k -L \
  "https://${VIRTCTL_HOST}/amd64/linux/virtctl.tar.gz" \
  -o /tmp/virtctl.tar.gz
```

Extract:

```bash
mkdir -p /tmp/virtctl
tar -xzf /tmp/virtctl.tar.gz -C /tmp/virtctl
```

Find it:

```bash
find /tmp/virtctl -type f -name virtctl -ls
```

Install:

```bash
install -m 0755 \
  $(find /tmp/virtctl -type f -name virtctl | head -1) \
  /usr/local/bin/virtctl
```

Verify:

```bash
virtctl version
```

---

#### 13. Prepare a local VM image

For the first disconnected VM I recommend using a local:

```text
QCOW2
```

rather than depending on any external boot-source URL.

For example:

```text
/app/images/rhel-9.qcow2
```

Check it:

```bash
ls -lh /app/images/rhel-9.qcow2
```

Optional:

```bash
qemu-img info /app/images/rhel-9.qcow2
```

---

#### 14. Create a DataVolume for the VM boot disk

Create:

```bash
cat > rhel9-rootdisk.yaml <<EOF
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataVolume
metadata:
  name: rhel9-rootdisk
  namespace: vm-test
spec:
  source:
    upload: {}
  storage:
    storageClassName: ${VM_SC}
    resources:
      requests:
        storage: 40Gi
EOF
```

Apply:

```bash
oc apply -f rhel9-rootdisk.yaml
```

Check:

```bash
oc get dv,pvc -n vm-test
```

---

#### 15. Upload the QCOW2 image

Run:

```bash
virtctl image-upload dv rhel9-rootdisk \
  -n vm-test \
  --image-path=/app/images/rhel-9.qcow2 \
  --no-create
```

If the workstation does not trust the OpenShift router certificate, temporarily use:

```bash
virtctl image-upload dv rhel9-rootdisk \
  -n vm-test \
  --image-path=/app/images/rhel-9.qcow2 \
  --no-create \
  --insecure
```

Wait until it completes.

Check:

```bash
oc get dv -n vm-test
```

Expected:

```text
Succeeded
```

Check PVC:

```bash
oc get pvc -n vm-test
```

It should be:

```text
Bound
```

---

#### 16. Create the first VM

Create:

```bash
cat > rhel9-test-vm.yaml <<'EOF'
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: rhel9-test
  namespace: vm-test
spec:
  runStrategy: Manual

  template:
    metadata:
      labels:
        kubevirt.io/domain: rhel9-test

    spec:
      domain:
        cpu:
          cores: 2

        resources:
          requests:
            memory: 4Gi

        devices:
          disks:
          - name: rootdisk
            disk:
              bus: virtio

          interfaces:
          - name: default
            masquerade: {}

      networks:
      - name: default
        pod: {}

      volumes:
      - name: rootdisk
        dataVolume:
          name: rhel9-rootdisk
EOF
```

Apply:

```bash
oc apply -f rhel9-test-vm.yaml
```

Check:

```bash
oc get vm -n vm-test
```

---

#### 17. Start the VM

```bash
virtctl start rhel9-test -n vm-test
```

Watch:

```bash
watch oc get vm,vmi,pod -n vm-test
```

Eventually:

```text
VM      Running
VMI     Running
```

Exit:

```text
Ctrl-C
```

---

#### 18. Connect to the VM console

```bash
virtctl console rhel9-test -n vm-test
```

To leave the serial console:

```text
Ctrl + ]
```

You can also use VNC:

```bash
virtctl vnc rhel9-test -n vm-test
```

---

#### 19. Check the VM IP

```bash
oc get vmi rhel9-test \
  -n vm-test \
  -o jsonpath='{.status.interfaces[*].ipAddress}{"\n"}'
```

The first test VM uses:

```text
OVN-Kubernetes pod network
+
masquerade
```

This is deliberately the simplest networking configuration.

---

#### 20. Verify that the VM disk really uses Fusion Access for SAN

Check:

```bash
oc get pvc rhel9-rootdisk \
  -n vm-test \
  -o wide
```

Then:

```bash
oc get pvc rhel9-rootdisk \
  -n vm-test \
  -o jsonpath='{.spec.storageClassName}{"\n"}'
```

Expected:

```text
<IBM_FUSION_ACCESS_SAN_STORAGECLASS>
```

Get the PV:

```bash
PV=$(oc get pvc rhel9-rootdisk \
  -n vm-test \
  -o jsonpath='{.spec.volumeName}')
```

Then:

```bash
oc get pv "${PV}" -o yaml
```

This confirms the boot disk was dynamically provisioned through the IBM storage class.

---

#### 21. Check the VM and VMI health

```bash
oc get vm rhel9-test -n vm-test -o yaml
```

```bash
oc get vmi rhel9-test -n vm-test -o wide
```

Find the launcher pod:

```bash
oc get pods -n vm-test \
  -l kubevirt.io=virt-launcher \
  -o wide
```

---

#### 22. Optional — expose SSH through MetalLB

Only do this once the VM has:

```text
sshd running
port 22 open
working guest networking
```

If MetalLB is already configured:

```bash
virtctl expose vm rhel9-test \
  -n vm-test \
  --name rhel9-test-ssh \
  --type LoadBalancer \
  --port 22
```

Check:

```bash
oc get svc rhel9-test-ssh -n vm-test
```

MetalLB should eventually allocate:

```text
EXTERNAL-IP
```

from its configured pool.

---

#### 23. Final acceptance check

#### OpenShift Virtualization

```bash
oc get hco kubevirt-hyperconverged \
  -n openshift-cnv
```

Healthy.

- Virtualization pods

```bash
oc get pods -n openshift-cnv
```

No unexpected failures.

- VM

```bash
oc get vm,vmi -n vm-test
```

Expected:

```text
rhel9-test    Running
```

- Storage

```bash
oc get dv,pvc -n vm-test
```

Expected:

```text
DataVolume    Succeeded
PVC           Bound
```

- VM disk

```bash
oc get pvc rhel9-rootdisk \
  -n vm-test \
  -o jsonpath='{.spec.storageClassName}{"\n"}'
```

Must show the IBM Fusion Access for SAN StorageClass.

At this point:

```text
OpenShift Virtualization   ✅
KVM workers                ✅
HCO                        ✅
Disconnected images        ✅
Fusion Access for SAN      ✅
DataVolume                 ✅
VM                         ✅
VM running                 ✅
```

The first disconnected VM is successfully provisioned.
