Looking Glass: tutorial for accelerated graphics in a KVM virtual machine using GVT-g (intel Core CPUs gen. 5-9)
=======================================================

## Introduction

This tutorial provides a step-by-step guide to setting up [Looking Glass (LG)](https://looking-glass.io/) with a Windows 10 virtual machine (VM) running on a Linux host.

Looking Glass enables hardware-accelerated graphics from the Windows VM to be displayed directly on the Linux desktop, eliminating the need for a separate monitor or switching between operating systems.

As described on the [Looking Glass website](https://looking-glass.io/):

> Looking Glass is an open source application that allows the use of a KVM (Kernel-based Virtual Machine) configured for VGA PCI Pass-through without an attached physical monitor, keyboard or mouse. This is the final step required to move away from dual booting with other operating systems for legacy programs that require high performance graphics.

## Intel GVT-g GPU Passthrough

This setup uses **Intel GVT-g**, a technology that enables mediated GPU passthrough on Intel Core processors (5th–9th generation). For technical details, see the [Arch Linux Wiki](https://wiki.archlinux.org/title/Intel_GVT-g).

In practical terms, Windows 10 running inside the VM sees a virtualized Intel GPU and uses the standard, unmodified Intel graphics driver. Looking Glass then transfers the rendered frames to the Linux host with extremely low latency.

The result is a Windows desktop with hardware-accelerated graphics running seamlessly alongside native Linux applications.

## Why GVT-g?

From an end-user perspective, GVT-g remains an attractive solution:

- **Cheap hardware:** especially on the second-hand market.
- **Adequate performance:** for many use cases.
- **Mature software support:** GVT-g is well supported on these older Intel Core CPUs.

Intel has discontinued GVT-g in favor of **SR-IOV (Single Root I/O Virtualization)**. However, official SR-IOV support for Intel integrated graphics remains somewhat fragmented.

Intel has announced SR-IOV capabilities for its upcoming Panther Lake processors with Xe3 integrated graphics. For further details, see [Phoronix: Intel SR-IOV Support](https://www.phoronix.com/news/Intel-SR-IOV-PTL-ARL-State). 

**Update**: Intel Nova Lake S & Nova Lake P To Support SR-IOV with Xe Graphics https://www.phoronix.com/news/Intel-Nova-Lake-SR-IOV-Xe

## About This Guide

This tutorial builds on the excellent work of **pavolelsig**, particularly the [Ubuntu GVT-g Helper](https://github.com/pavolelsig/Ubuntu_GVT-g_helper) project.

Since the original project is now approximately five years old, this guide provides an updated approach to setting up Intel GVT-g and Looking Glass on a Linux host.

## General

Tested on Ubuntu 25.04. The VM uses KVM, qemu, libvirt and virt-manager as a graphical frontend. The guest is Windows 10.

## Prerequisite

You already have a running virtual machine of Windows 10 with virt-manager as frontend for QEMU. How to prepare a Windows 10 VM in KVM/Virt-manager is not covered here, but there are many excellent guides  e.g. <https://gitlab.com/Luxuride/VFIO-Windows-install-walkthrough/-/blob/master/VmInstall.md>. As explained below, use the virtIO Windows drivers (<https://pve.proxmox.com/wiki/Windows_VirtIO_Drivers#Using_the_ISO>) to enable direct access to devices and peripherals, instead of slower, emulated ones.

Note: any 64-bit version of Windows 10 should work, but Windows 10 LTSC is recommended. Windows 10 LTSC is an interesting release as it does not require Secure Boot, offers more predictable updates, and has an extended support period. More information can be easily found on github.

## Configuration of the VM

Disable Secure Boot in the VM. After starting the VM, press F2 quickly to enter the UEFI. Under 'Device manager  / secure boot configuration' disable 'Attempt Secure Boot'.

* Install the spice-guest-tools <https://www.spice-space.org/download/windows/spice-guest-tools/spice-guest-tools-latest.exe>. The Windows SPICE Guest Tools contain some optional drivers and services  to improve SPICE performance and integration. This includes the qxl video driver and the SPICE guest agent (for copy and paste, automatic graphics resolution switching, ...).

The default VM configuration must be adjusted (see <https://looking-glass.io/docs/B7/install_libvirt/>) and is most easily done graphically in virt-manager. 

Open the details of the VM:

* Remove the Tablet device.

* Change Video QXL to VGA.

* Press add Hardware button and add VirtIO Keyboard.

* Add VirtIO mouse. This cannot be done graphically, and we need to edit the VM configuration manually. Type `virsh edit your_VM_name` and change the line `<input type='mouse' bus='ps2'/>` to virtio: `<input type='mouse' bus='virtio'>`

* and find the line `<memballoon>` set its type to none: `<memballoon model="none"/>`.

* Before proceeding with the installation of LG, it is a good idea to take a snapshot of the VM i.e. graphically in the virt-manager frontend. This allows an easy 'rollback'.

## Installation of Looking Glass on the Linux host

* Check if KVM is supported: `kvm-ok`

* In the BIOS settings of the Linux host VT-x, IOMMU have to be enabled. Most likely not all settings are available, but it is sufficient to have at least VT-x enabled. 

Check if your intel CPU if is gen 5-9: `cat /proc/cpuinfo`

* Add kernel boot parameters:
    * Edit `/etc/default/grub` and add the the parameters 				`intel_iommu=on i915.enable_gvt=1 kvm.ignore_msrs=1` to the line `GRUB_CMDLINE_LINUX_DEFAULT`. 
    Typically this looks like: `GRUB_CMDLINE_LINUX_DEFAULT="quiet splash intel_iommu=on i915.enable_gvt=1 kvm.ignore_msrs=1"`
    * After modifying the grub config, it is important run `update-grub` with no errors. 
    
* Loading of the kernel module `kvgt`. To load `kvgt` during the boot, create the file `/etc/modules-load.d/kvmgt.conf` and populate it with:
	```
		# KVMGT kernel module
		kvmgt
    ```
Note: `kvmgt` depends on `i915, vfio, kvm, mdev` and hence, these modules will be loaded automatically too.
* Update initramfs: `update-initramfs -u`
* Reboot.
* Check if the Kernel is started with the additional parameters: `cat /proc/cmdline` and whether the `kvmgt` kernel module is loaded: `lsmod | grep kvmgt`.

## Create the mediated virtual GPU

* Check whether the mediated virtual GPU devices (mdev) are available. Run `find /sys/devices/pci* -name 'mdev_supported_types'`. A typical output is: `/sys/devices/pci0000:00/0000:00:02.0/mdev_supported_types`. `cd` into this directory, and you'll see several directories: `i915-GVTg_V5_4  i915-GVTg_V5_8`. Each directory contains a `description`. For example `less /sys/devices/pci0000:00/0000:00:02.0/mdev_supported_types/i915-GVTg_V5_4/description` shows:
```
low_gm_size: 128MB
high_gm_size: 512MB
fence: 4
resolution: 1920x1200
weight: 4
```
Note: vGPUs with a higher weight value will get more physical GPU time slices.

To activate the mdev device, we write a unique identifier number (uuid) to the `create` file.

To simplify these steps, the script `init_VGPU.sh` is provided. This script finds the vGPU with the highest weight factor and initialises the mdev device at every startup by a service.
* Run the script `init_VGPU.sh` as root and reboot. 
* Check the output of `check_gpu.sh`. The output is the above-mentioned UUID identifier from the activated mdev device.

# Installation of Looking glass client on the Linux host

The installation of LG is well documented. For completeness, a brief overview.

* Download the LG client source for the Linux host: <https://looking-glass.io/>. In the time of writing B7. Go ahead with the compiling as described in  <https://looking-glass.io/docs/B7/build/>.

It is recommended to install the kernel module `kvmfr` for fast transfer of the frames from the VM to the host. See <https://looking-glass.io/docs/B7/module/#kernel-module>. A brief recap: 

* Installation of the kernel-headers: `apt-get install linux-headers-$(uname -r)` 

* Go into the module subdir and run `dkms install "."`. 
* Test to load the module: `modprobe kvmfr static_size_mb=32`
* Create the file `/etc/modprobe.d/kvmfr.conf` with:		
```
options kvmfr static_size_mb=32
```
and load the module during boot by creating a file `/etc/modules-load.d/kvmfr.conf` with:
	
```
 	# KVMFR Looking Glass module
kvmfr
```	

The kernel module uses `/dev/kvmfr0`, which needs to have permission for user access. This can be achieved permanently by creating a udev rule in `/etc/udev/rules.d/99-kvmfr.rules` with:

```
SUBSYSTEM=="kvmfr", OWNER="user", GROUP="kvm", MODE="0660"
```

 and change "user" to your user name given by `logname`. 

* Create `/etc/apparmor.d/local/abstractions/libvirt-qemu` and add the following:

```
# Looking Glass
/dev/kvmfr0 rw,
```

* Reboot and check if the kvmfr module is loaded: `lsmod | grep kvmfr` and check the permissions of the `ls -la /dev/kvmfr0` 

* Configuration of VM for the use of the kvmfr module. In one session of `virsh edit your_VM_name` change the first line from `<domain type='kvm'>` to 

```XML
<domain type='kvm' xmlns:qemu='http://libvirt.org/schemas/domain/qemu/1.0'>
``` 

and add 

```XML
<qemu:commandline>
  <qemu:arg value="-device"/>
  <qemu:arg value="ivshmem-plain,id=shmem0,memdev=looking-glass"/>
  <qemu:arg value="-object"/>
  <qemu:arg value="memory-backend-file,id=looking-glass,mem-path=/dev/kvmfr0,size=32M,share=yes"/>
</qemu:commandline>
```

at the end before `</domain>`.
## Final steps
In the VM configuration, we add the passthrough vGPU: 
* Add Hardware 'MDEV Host Device'.
![](images/vGPU.png)

* Start the VM and open the device manager. Update drivers by a right mouse click. 
![](images/update-driver.png)

* Windows will automatically install the Intel GPU driver, and finally the VM sees the vGPU. Note: I had to trigger this several times.
![](images/win10_vgpu.png)

* Download the LG windows host binary. Run the installer as admin and restart the VM. See <https://looking-glass.io/docs/B7/install_host/#for-windows>

* Start the win10 VM. Log in.

* On the Linux host, enter the directory of the looking-glass client and start it: `looking-glass-B7/client/build/looking-glass-client -f /dev/kvmfr0 -F`. You might want to explore the many options of LG: `looking-glass-client -h`

* By default, LG displays the secondary screen. For convenience, it is recommended to assign it to the primary screen. Further configure Windows for an automatic log-in without password. Such automatic login is convenient, as if there are any problems, you will always have a running desktop to which you can anytime connect using Spice, e.g. via the command 'virt-viewer'.

* It is handy to have a startup script like:
```
#!/bin/bash
virsh start your_VM_name
sleep 2s
<your path>/looking-glass-B7/client/build/looking-glass-client -f /dev/kvmfr0 -F -c
```
  

* Enjoy!  

The graphics performance is excellent - close to bare metal.
Many thanks to Geoffrey McRae and all the other contributors for their great work.
 



  



 


  
 


















 












 




 

 
