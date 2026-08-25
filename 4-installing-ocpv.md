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

For the first disconnected VM it is recommended using a local:

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

---

#### Troubleshoot

- 1. Confirm all three masters are schedulable
```bash
oc get scheduler cluster -o jsonpath='{.spec.mastersSchedulable}{"\n"}'
```

Expected:

```text
true
```

Also:

```bash
oc get nodes
```

It should shpw the three nodes as **Ready**.

Check taints:
```bash
oc get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints
```

If it shows, then workloads/VMs are not schedule.
```text
node-role.kubernetes.io/master:NoSchedule
node-role.kubernetes.io/control-plane:NoSchedule
```

then workloads/VMs might not schedule.

On a 3-node bare-metal cluster with no compute nodes, the control planes are normally schedulable.

- 2. Check the node labels

Run:
```bash
oc get nodes --show-labels
```

More readable:
```bash
oc get nodes \
  -L node-role.kubernetes.io/master,node-role.kubernetes.io/control-plane,node-role.kubernetes.io/worker
```

I would expect the nodes to be control-plane/master nodes. Do not worry if there is no worker label; the important part for this topology is that they are schedulable.

3. Verify KVM exists on all three physical servers

This is the big one for OpenShift Virtualization.

Run:
```bash
for node in $(oc get nodes -o name); do
  echo "===== ${node} ====="
  oc debug "${node}" -- chroot /host \
    sh -c 'ls -l /dev/kvm 2>/dev/null || echo "KVM MISSING"'
done
```

It is expected on every node:
```text
/dev/kvm
```

If it gives:
```text
KVM MISSING
```

check BIOS/UEFI for:
```text
Intel VT-x / Intel Virtualization Technology
```

or:

```text
AMD-V / SVM
```

Do not proceed with VM testing until **/dev/kvm** exists.

4. Check the CPU virtualization flags

For Intel:
```bash
for node in $(oc get nodes -o name); do
  echo "===== ${node} ====="
  oc debug "${node}" -- chroot /host \
    sh -c "grep -m1 -o 'vmx' /proc/cpuinfo || true"
done
```

For AMD:
```bash
for node in $(oc get nodes -o name); do
  echo "===== ${node} ====="
  oc debug "${node}" -- chroot /host \
    sh -c "grep -m1 -o 'svm' /proc/cpuinfo || true"
done
```

It needs either:
```text
vmx
```
or:
```text
svm
```
depending on CPU vendor.

5. Check resources — especially because control plane and VMs share the same machines

Run:
```bash
oc adm top nodes
```
And:
```bash
oc describe nodes | egrep -A8 'Name:|Capacity:|Allocatable:'
```

For a 3-node compact cluster, remember that each machine will be doing both:
```text
etcd
API server
controller-manager
scheduler
OpenShift Operators
Fusion Access components
OpenShift Virtualization
VM workloads
```
So I would be conservative with the first VM: maybe:
```text
2 vCPU
4 GiB RAM
```

rather than immediately creating something large.

6. Check that storage works on all three nodes

Since you're using IBM Fusion Access for SAN, first identify the StorageClass:
```bash
oc get sc
```

Then:
```bash
oc get storageprofile
```

For the intended VM StorageClass:
```bash
oc get storageprofile <FUSION_STORAGECLASS> -o yaml
```

Check especially:
```text
status:
  claimPropertySets:
```

It is expected that OpenShift Virtualization/CDI understands the supported:
```text
accessModes
volumeMode
```

Before doing a VM, please tets it by creating one simple PVC against Fusion, and ensure it becomes:
```text
Bound
```

7. Check whether your three masters can all access the SAN storage

This matters for live migration.

The VM disk must be accessible from whichever of the three nodes may host the VM.

After creating a test PVC:
```bash
oc get pvc
```

and:
```bash
oc get pv <PV_NAME> -o yaml
```

For SAN-backed shared storage, this should ultimately permit the disk to move between eligible virtualization nodes according to the CSI/storage capabilities.

8. After OpenShift Virtualization is installed, check virt-handler

One virt-handler should normally run on every virtualization-capable node:
```bash
oc get pods -n openshift-cnv -o wide | grep virt-handler
```

With the current topology it expects:
```text
virt-handler-xxxxx   Running   master-0
virt-handler-yyyyy   Running   master-1
virt-handler-zzzzz   Running   master-2
```

If only one or two appear, investigate node eligibility/taints/KVM.

9. After HCO is running, check the virtualization node labels

OpenShift Virtualization's node labeller discovers CPU capabilities and labels eligible nodes. Red Hat uses these labels when deciding where VMs can run and migrate.

Useful check:
```bash
oc get nodes --show-labels | grep -E 'kubevirt|cpu-model|cpu-feature'
```

More targeted:
```bash
oc get nodes \
  -o json | \
  jq -r '.items[] |
    .metadata.name as $n |
    .metadata.labels |
    to_entries[] |
    select(.key | contains("kubevirt.io")) |
    "\($n) \(.key)=\(.value)"'
```

10. Check KubeVirt resources advertised by kubelet

After OpenShift Virtualization is fully installed:
```bash
oc get nodes \
  -o custom-columns=NAME:.metadata.name,KVM:.status.allocatable.devices\\.kubevirt\\.io/kvm
```

Ideally each node shows KVM capacity rather than **<none>**.

Also:
```bash
oc describe node <NODE> | grep -A10 -B3 kubevirt
```

This is one of the most useful post-install checks.

11. Do not add a worker nodeSelector to HCO

This is particularly important for this topology (three scheduleable masters).

Do not configure something like:
```yaml
workloads:
  nodePlacement:
    nodeSelector:
      node-role.kubernetes.io/worker: ""
```

because you have no worker nodes.

Likewise don't configure VM manifests with:
```yaml
nodeSelector:
  node-role.kubernetes.io/worker: ""
```

unless you later add actual workers.

OpenShift Virtualization supports node placement rules, but a required node selector with no matching nodes makes the workload unschedulable.

For now I would leave HCO simply:
```text
spec: {}
```

and let the three schedulable control planes be eligible.

The short pre-flight I would actually run now
```bash
echo "=== SCHEDULER ==="
oc get scheduler cluster \
  -o jsonpath='{.spec.mastersSchedulable}{"\n"}'

echo
echo "=== NODES ==="
oc get nodes -o wide

echo
echo "=== TAINTS ==="
oc get nodes \
  -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints

echo
echo "=== KVM ==="
for node in $(oc get nodes -o name); do
  echo "--- ${node} ---"
  oc debug "${node}" -- chroot /host \
    sh -c 'test -c /dev/kvm && echo "KVM OK" || echo "KVM MISSING"'
done

echo
echo "=== NODE RESOURCES ==="
oc adm top nodes

echo
echo "=== STORAGE ==="
oc get sc
```

If those come back with:

mastersSchedulable = true         ✅
3 nodes Ready                     ✅
no blocking NoSchedule taints     ✅
/dev/kvm on all three             ✅
reasonable CPU/RAM headroom       ✅
Fusion SAN StorageClass           ✅