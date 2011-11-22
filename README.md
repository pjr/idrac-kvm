idrac-kvm.rb
============

This script makes it easy to access the Dell iDRAC KVM from the command line, without having to open a browser.

Requires the rest-client, net-ssh-gateway, and slop gems. Install with:

```
sudo gem install rest-client net-ssh-gateway slop
```

Usage
-----

```
Usage: ./idrac-kvm.rb [options]

options:

    -b, --bounce        Bounce server (optional)
    -l, --login         Your username on bounce server (optional; defaults to iota)
    -s, --server        Remote server IP (required)
    -u, --user          Remote username (optional; defaults to root)
    -p, --password      Remote password (required)
    -h, --help          Print this help message
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
