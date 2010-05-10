#!/usr/bin/perl

use strict;
use warnings;
use Data::Dumper;

sub parse {
    my $text= join "", @_;
    return map {/^\s*(.+) \: (.+?)\s*$/; lc $1, $2;} grep {/ \: /} split "\n", $text;
}

my %uids= ();
for my $disc (glob '/dev/[hs]d?[1-9]*') {
    my %attributes= parse `mdadm --examine "$disc" 2>/dev/null`;
    next unless %attributes;
    my $uid= $attributes{'array uuid'};
    my $num_devices= $attributes{'raid devices'};
    my $name= $attributes{name};
    $uids{$uid}= {
        devices => [],
        num_devices => $num_devices,
        name => $name,
        failed => 0,
    } unless $uids{$uid};
    push @{$uids{$uid}{devices}}, $disc;
    $uids{$uid}{failed}= 1 unless $uids{$uid}{num_devices} == $num_devices || $uids{$uid}{name} == $name;
}

my @md_devices= ();
for my $uid (keys %uids) {
    $uids{$uid}{failed}= 1 unless $uids{$uid}{num_devices} == scalar @{$uids{$uid}{devices}};
    if ($uids{$uid}{failed}) {
        print 'Device /dev/md/', $uids{$uid}{name}, ' is incomplete (UUID: ', $uid , ")\n",
            'Found ', scalar(@{$uids{$uid}{devices}}), ' of ', $uids{$uid}{num_devices}, ' devices (', join(", ", sort @{$uids{$uid}{devices}}), ")\n";
        next;
    }
    my $device= '/dev/md/' . $uids{$uid}{name};
    my %attributes= parse `mdadm --detail "$device" 2>/dev/null`;
    my @states= split /, */, $attributes{state} || '';
    if (grep {/^active$/} @states) {
        print "$device: active (" . join(', ', @states) . ")\n";
    }
    else {
        my $name= $uids{$uid}{name};
        print `mdadm --assemble --uuid="$uid" --name="$name"`;
    }
}

__END__

for dev in /dev/[hs]d[1-9]*
do
    mdadm --examine --brief "$dev"
done | perl -e '
    use strict;
    my %uid= ();
    while (<>) {
        if (/num\-devices\=(\d+) UUID\=(\S+)\s/) {
            $uid{$2}= {num => $1, count => 0,} unless defined $uid{$2};
            $uid{$2}{count}++;
        }
    }
    my $failed= 0;
    for my $uid (keys %uid) {
        if ($uid{$uid}{num} == $uid{$uid}{count}) {
            print "UID $uid is complete\n";
        }
        else {
            print "UID $uid is not complete!\nFound only $uid{$uid}{count} of $uid{$uid}{num} devices\n";
            $failed= 1;
        }
    }
    exit $failed;
'

if [ "$?" -ne "0" ]; then
    echo "device failed!"
else
    if grep "md0 : active" /proc/mdstat > /dev/null; then
        echo "/dev/md0 already startet"
    else
        mdadm --assemble --scan
        sleep 2
    fi
    if grep "/mnt/vandusen" /proc/mounts > /dev/null; then
        echo "already mounted"
    else
        mount /mnt/vandusen
    fi

    sleep 2

    watch -d "cat /proc/mdstat ; echo ; mdadm --detail /dev/md? 2>/dev/null"
fi
