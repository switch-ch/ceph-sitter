# ceph-sitter

Scripts to help babysitting a flaky Ceph cluster

- check-osds.pl - generate concise report about down OSDs
- check-osds-loop.sh - run check-osds.pl in a loop
  - optionally saves reports and and exports them to Web server

The `check-osds` script collects information about non-up OSDs and
hosts in the cluster.  Some information comes from global Ceph cluster
state, i.e. ceph osd tree.  Some information is collected on the OSD
hosts, in particular possible processes related to those non-up OSDs,
as well as configuration information found in /etc/ceph/ceph.conf.

This information is condensed into a compact report intended to be helpful
for diagnosis and recovery/mitigation.

Here is an example report showing nine down OSDs on six servers:

```
Mon Jun  1 20:21:02 2020

host unil0005 osd 106 (class hdd, weight  3.7 bsa bitmap@): down - compaction running since 20:19, pid 3040105
host unil0017 osd 207 (class hdd, weight  3.6 bsa bitmap@): down - ceph-osd running since 19:52, pid 4022599
host unil0043 osd 389 (class hdd, weight  3.7 bsa bitmap@): down - ceph-osd running since 20:16, pid 2147385
host unil0047 osd  36 (class hdd, weight  3.6 bsa bitmap@): down - compaction running since 19:56, pid 3429281
host unil0081 osd  88 (class hdd, weight  7.3 bsa bitmap@): down - ceph-osd running since 19:49, pid 2424998
host unil0083 osd   8 (class hdd, weight  7.3 bsa stupid.): down - ceph-osd running since 20:15, pid 2714906
              osd  14 (class hdd, weight  7.3 bsa stupid.): down - ceph-osd running since 20:12, pid 2713035
              osd  35 (class hdd, weight  7.3 bsa stupid.): down - ceph-osd running since 20:12, pid 2713614
              osd  46 (class hdd, weight  7.3 bsa stupid.): down - ceph-osd running since 20:13, pid 2713709
```

Options found in /etc/ceph/ceph.conf (or not):

  bsa: bluestore allocator

Option values are decorated with a provenance indicator:
- `.` - specified in ceph.conf for a specific OSD (section [osd.ID])
- `*` - specified in ceph.conf for all OSDs on the host (section [osd])
- `@` - system default (not configured in ceph.conf)
