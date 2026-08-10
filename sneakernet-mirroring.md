# Sneakernet Mirroring

Red Hat specifically designed the oc-mirror tool to handle this exact scenario using a "mirror-to-disk" workflow. Instead of syncing images over a network to a registry, you pack the OpenShift release, operators, and required images into a massive archive file directly onto an intermediary storage device (like a high-capacity USB drive or external hard disk).Here is how that physical transfer workflow operates in practice:


1. Mirror to Disk (Connected Environment):Requires internet access.On a machine connected to the internet, you run **oc-mirror** targeting a local directory on your portable media (e.g., a mounted USB drive) instead of a registry URL.

```bash
# Note the file:// protocol instead of docker://
oc mirror --config imageset-config.yaml file:///mnt/usb-drive/mirror-archive
```

This downloads and packages all requested container images, along with the metadata, into a .tar archive on the drive.


2. The Physical Air-Gap Transfer:The Sneakernet.You safely unmount the USB drive, physically walk it across the facility—often passing it through security scanners or malware kiosks as required by the organization—and plug it into a Bastion host sitting entirely inside the restricted network.

3. Mirror to Registry (Disconnected Environment):No internet access.From the internal Bastion host, you run oc-mirror again. This time, you instruct it to unpack the archive from the USB drive and push the images into your internal, disconnected container registry (like Quay, Nexus, or the Red Hat Mirror Registry).


  ```bash
  oc mirror --from file:///mnt/usb-drive/mirror-archive docker://internal-registry.local:5000
  ```


Once that final step is complete, your internal registry is fully populated. You then point your Assisted Installer (and the resulting OpenShift cluster) at that internal registry, and the installation proceeds completely isolated from the outside world.