#!/usr/bin/perl -w

use strict;
use warnings;

my %nodes = ();
my %host_ids = ();

my $helpful_suggestions = 0;

## Prototypes
sub node_option($$@);

sub collect_osd_tree () {
    my ($root, $host, $id, $class, $weight, $type, $name, $status, $reweight, $pri_aff);

    die "Cannot start ceph osd tree: $!"
        unless open(OSD_TREE, "ceph osd tree |");
    while (<OSD_TREE>) {
        next if /ID   CLASS WEIGHT     TYPE NAME         STATUS REWEIGHT PRI-AFF/;
        if (($id, $class, $weight, $name, $status, $reweight, $pri_aff)
            = /^\s*(\d+)\s+(\S+)\s+([0-9.]+)\s+(\S+)\s+([a-z_]+)\s+([0-9.]+) ([0-9.]+)\s*$/) {
            warn "OSD $id: unknown host" unless defined $host;
            $nodes{$id} = {};
            $nodes{$id}->{id} = $id;
            $nodes{$id}->{class} = $class;
            $nodes{$id}->{name} = $name;
            $nodes{$id}->{host} = $host;
            $nodes{$id}->{parent} = $host_ids{$host};
            $nodes{$id}->{status} = $status;
            $nodes{$id}->{weight} = $weight;
            $nodes{$id}->{reweight} = $reweight;
        } elsif (($id, $weight, $name)
            = /^\s*(-?\d+)\s*([0-9.]+)\s*host\s+(\S+)\s*$/) {
            # warn "found host: $name\n";
            $host = $name;
            $nodes{$id} = {};
            $nodes{$id}->{id} = $id;
            $nodes{$id}->{name} = $name;
            $nodes{$id}->{host} = $name; # pointless loop, avoids trouble with sort cmp function
            $host_ids{$name} = $id;
            $nodes{$id}->{weight} = $weight;
        } elsif (($id, $weight, $name)
            = /^\s*(-?\d+)\s*([0-9.]+)\s*root\s+(\S+)\s*$/) {
            # warn "found root: $name\n";
            $root = $name;
        } else {
            warn "ceph osd tree: Cannot parse $_";
        }
    }
    close(OSD_TREE)
        or warn "Error closing pipe from ceph osd tree: $!";
    1;
}

sub collect_information_from_interesting_hosts () {
    my %interesting_hosts = ();
    my ($user, $pid, $pcpu, $pmem, $vsz, $rss, $tty, $stat, $start, $time, $command, $id);

    # Let's say all hosts with non-"up" OSDs are interesting.
    #
    foreach my $id (sort { $a <=> $b } keys %nodes) {
        next if $id < 0;        # Ignore hosts and root
        my $osd = $nodes{$id};
        next if $osd->{status} eq 'up';
        my $host = $osd->{host};
        $interesting_hosts{$host}++;
    }

    # SSH into the host, run "ps axwu", and try to find OSD-related jobs.
    #
    # If we find something, store it under the OSD's structure.  We do
    # this for all OSDs on the host, not just the ones that are down.
    #
    foreach my $host (sort { $a cmp $b } keys %interesting_hosts) {
        my ($mode, $sec);
        # warn "Trying to SSH to $host...";
        open(SSH, "ssh $host 'ps axwu; echo %%%SNIP%%%; cat /etc/ceph/ceph.conf'|");
        $mode = 0;
        while (<SSH>) {
            chomp;
            if (/^%%%SNIP%%%$/) {
                ++$mode;
            }
            if ($mode == 0) {   # ps axwu
                if (($user, $pid, $pcpu, $pmem, $vsz, $rss, $tty, $stat, $start, $time, $command)
                    = m@^(\S+)\s+(\d+)\s+([0-9.]+)\s+([0-9.]+)\s+(\d+)\s+(\d+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(.*)@) {
                    if (($id) = $command =~ m@(?:/usr\S+/)?ceph-osd.* --id (\d+)@) {
                        $nodes{$id}->{osd_pid} = $pid;
                        $nodes{$id}->{osd_start} = $start;
                        # printf("  OSD $id process is running on host $host (PID $pid)\n");
                    } elsif (($id) = $command =~ m@ceph-kvstore-tool bluestore-kv /var/lib/ceph/osd/ceph-(\d+) compact@) {
                        $nodes{$id}->{compact_pid} = $pid;
                        $nodes{$id}->{compact_start} = $start;
                        # printf("  OSD $id is being compacted offline on host $host (PID $pid).\n");
                    }
                }
            } elsif ($mode == 1) { # cat /etc/ceph/ceph.conf
                next if /^#/;
                if (/^\[(.*)\]/) {
                    $sec = $1;
                } elsif (/^(.*\S)\s*=\s*(.*)/) {
                    my ($option, $value) = ($1, $2);
                    #
                    # Options can be written with spaces or underscores.
                    # We use spaces as the canonical form.
                    #
                    $option =~ s/[ _]+/ /g;

                    if ($sec eq 'osd') {
                        my $node = $nodes{$host_ids{$host}};
                        $node->{conf_options} = {} unless exists $node->{conf_options};
                        $node->{conf_options}->{$option} = $value;
                        # warn "host-wide OSD option on $host: $option = $value";
                    } elsif ($sec =~ /osd\.(\d+)/) {
                        my ($id) = $1;
                        my $osd = $nodes{$id};
                        $osd->{conf_options} = {} unless exists $osd->{conf_options};
                        $osd->{conf_options}->{$option} = $value;
                        # warn "OSD-specific option for OSD $id on $host: $option = $value";
                    }
                }
            }
            # printf("  %s\n", $_);
        }
        close(SSH) or warn "Error closing SSH to $host: $!";
    }
}

sub node_option($$@) {
    my ($id, $option, $default, $inheritance_level) = @_;
    my ($node);

    $inheritance_level = 0 unless defined $inheritance_level;
    return ($default, 9) unless exists $nodes{$id};
    $node = $nodes{$id};
    if (exists $node->{conf_options} and exists $node->{conf_options}->{$option}) {
        return ($node->{conf_options}->{$option}, $inheritance_level);
    } elsif (exists $node->{parent}) {
        return node_option($node->{parent}, $option, $default, 1);
    }
    return ($default, 9);
}

sub pretty_inheritance_level($ ) {
    my ($level) = @_;
    return substr(".*???????@", $level, 1);
}

sub print_report() {
    print(scalar(localtime(time)),"\n\n");
    my ($id, $osd, $value, $inheritance, $host, $last_host, $host_head, $unhealthy_count);

    $unhealthy_count = 0;

    foreach $id (sort { $nodes{$a}->{host} cmp $nodes{$b}->{host} || $a <=> $b } keys %nodes) {
        next if $id < 0;        # Ignore hosts and root
        $osd = $nodes{$id};
        next if $osd->{status} eq 'up';
        next if $osd->{weight} == 0;
        next if $osd->{reweight} == 0;
        ++$unhealthy_count;
        $host = $osd->{host};
        $host_head = (defined $last_host and $last_host eq $host)
            ? ' ' x (length("host ")+length($host))
            : sprintf("host %s", $host);
        $last_host = $host;
        printf("%s osd %3d (%4.1f %s",
               $host_head, $id,
               $osd->{weight}, $osd->{class});

        foreach my $option (
            (
             {
                 name => 'bluestore allocator',
                 shortname => 'bsa',
                 default => 'bitmap',
                 prettifier => sub { return $_[0] }
             },
             {
                 name => 'bluefs max log runway',
                 shortname => 'rwy',
                 default => 4 << 20,
                 prettifier => sub { $_[0] % 1<<20 ? $_[0] : sprintf("%dMiB", $_[0] >> 20) }
             }
            )) {
            ($value, $inheritance) = node_option($id, $option->{name}, $option->{default});
            printf(" %s=%s%s",
                   $option->{shortname},
                   $option->{prettifier}($value),
                   pretty_inheritance_level($inheritance));
        }
        printf("): %s", $osd->{status});
        if (exists $osd->{osd_pid}) {
            printf(" - ceph-osd running since %s, pid %d",
                   $osd->{osd_start}, $osd->{osd_pid});
        }
        if (exists $osd->{compact_pid}) {
            printf(" - compaction running since %s, pid %d",
                   $osd->{compact_start}, $osd->{compact_pid});
        }
        if (! exists $osd->{compact_pid} and ! exists $osd->{osd_pid}) {
            printf(" - neither OSD nor compaction jobs found");
            if ($helpful_suggestions) {
                printf("\n  SUGGESTION:\n");
                printf("    ssh %s sudo systemctl start ceph-osd@%d",
                       $host, $id);
            }
        }
        printf("\n");
    }

    if ($unhealthy_count == 0) {
        printf("Congratulations, all OSDs seem to be up.\n");
    } else {
        print("\nFor explanation the output, see https://github.com/switch-ch/ceph-sitter\n");
    }
    1;
}

collect_osd_tree();
collect_information_from_interesting_hosts();
print_report();

1;
