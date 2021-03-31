# toad

device automounter for OpenBSD hotplugd(8)

toad (Toad Opens All Devices) is a utility meant to be started from the
hotplugd(8) attach and detach scripts.  It will attempt to mount all
supported partitions found on the device under /media/${USER}/device. Where
${USER} is the active user login name and device is either the partition
volume label or the disk label description followed by a partition number
(ex. Sandisk Cruzer-p1). Mounting uses the hotplug-diskmount(8) command
and follows the udev hierarchy in Linux which allows interaction with
GLib/GIO's GUnixMount.

Detection of the currently active user is done using ConsoleKit and DBus,
toad will not do anything unless these are properly setup and running.
Obviously, hotplugd(8) must be running as well.

toadd(8) is an optical medium detection daemon that works in conjunction
with the toad(8) automounter.  It will detect the insertion of a medium
in the optical drives of the machine (maximum 2) by periodically reading
their disklabel(8).

See toad(8) for more information about how to create the hotplugd(8) attach and
detach scripts. A sample script that can be used as both an attach and a detach
script is provided: hotplug-scripts.

Installing
----------
    $ make
    $ doas make install
    
Create hotplug scripts:

    $ doas cp /usr/local/share/examples/toad/hotplug-scripts /etc/hotplug/attach
    $ doas cp /usr/local/share/examples/toad/hotplug-scripts /etc/hotplug/detach

Uninstalling
------------
    $ doas make uninstall

Remove hotplug scripts:

    $ doas rm /etc/hotplug/attach
    $ doas rm /etc/hotplug/detach

Runtime dependencies
--------------------
toad(8):
- Net::DBus			required
- ConsoleKit			required
- Polkit			required (for eject(1)/umount(8))
- GLib (OpenBSD package)	required (patched for umount(8) with pkexec(1))
- hotplug-diskmount(8)		required (replacement for mount(8) subroutines)

toadd(8):
- toad(8)			required

Changes
-------
- mount operations performed by enhanced hotplug-diskmount(8)
- removed mount point management code which is not required
- works with fuse FS drivers such as ntfs3g and exfat-fuse
- fixed dbus session file name issue affecting gdbus_call
