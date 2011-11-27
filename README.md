idrac-kvm.rb
============

This script makes it easy to access the Dell iDRAC KVM from the command line, without having to open a browser.

Requires the rest-client, net-ssh-gateway, and slop gems. Install with:

```
sudo gem install rest-client net-ssh-gateway slop
```

You will also need a working copy of javaws, and it has been reported that the non-Sun/Oracle copy of javaws
included with some Linux distros don't work. You may want to test that you can actually get to the KVM viewer
manually before using this script.

Note that if you are running idrac-kvm.rb from a Linux machine, this script will automatically attempt to compile
the iDRAC Keycode hack from https://github.com/pjr/keycode-idrac. This hack is required to make the arrow keys work.

The script also tries to clean up after itself, even if the Java viewer crashes (which is often). The script will
automatically send the logout command to the server and close your session out cleanly so that you do not get locked
out of the iDRAC interface. If the logout command is not sent, you may find yourself getting an odd error when trying
to connect again - not a very good situation if your server is offline.

Usage
-----

```
Usage: ./idrac-kvm.rb [options]

options:

    --bounce        Bounce server (optional)
    --login         Your username on bounce server (optional; defaults to iota)
    --server        Remote server IP (required)
    --user          Remote username (optional; defaults to root)
    --password      Remote password (required)
    --help          Print this help message
```

Examples
--------

To log in via a SSH tunnel to an intermediate server:

```
./idrac-kvm.rb --bounce firewallserver.example.com --login youruser --server 192.168.0.1 --password calvin
```

To log in directly to an iDRAC host

```
./idrac-kvm.rb --server 192.168.0.1 --password calvin
```
