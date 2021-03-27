
#!/usr/bin/perl
#
# Copyright (c) 2021 jpz4085
# Copyright (c) 2016, 2019, 2020 Antoine Jacoutot <ajacoutot@openbsd.org>
# Copyright (c) 2013, 2014, 2015, 2016 M:tier Ltd.
#
# Permission to use, copy, modify, and distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
#
# Author: Antoine Jacoutot <antoine@mtier.org>

use strict;
use warnings;

use File::Path qw(make_path);
use Net::DBus;
use User::pwent qw(:FIELDS);

if ( $< != 0 ) {
	print "need root privileges\n";
	exit (1);
}

sub usage {
	print "usage: $0 attach|detach devclass device\n";
	exit (1);
}

if (@ARGV < 3) { usage (); }

my ($action, $devclass, $devname) = @ARGV;
my ($login, $uid, $gid, $display, $home) = get_active_user_info ();
my $dbus_session_bus_address = get_dbus_session_bus_address ();
my $mounttop = "/media/$login";
my $mountbase;
my $mountfuse;
my $devtype;
my $devmax;
my $pkrulebase = "/etc/polkit-1/rules.d/45-toad-$login";

sub broom_sweep {
	unlink glob "$pkrulebase-$devname?.rules";

	if ($devtype eq 'cd') {
		exec("/usr/local/libexec/hotplug-diskmount -d $mounttop cleanup $devname");
	}
}

sub create_pkrule {
	my($devname, $part, $mountbase) = @_;
	my $pkrule = "$pkrulebase-$devname$part.rules";

	unless(open PKRULE, '>'.$pkrule) {
		die "Unable to create $pkrule\n";
	}

	print PKRULE "polkit.addRule(function(action, subject) {\n";
	print PKRULE "  if (action.id == \"org.freedesktop.policykit.exec\" &&\n";
	print PKRULE "    action.lookup(\"program\") == \"/sbin/umount\" &&\n";
	print PKRULE "    action.lookup(\"command_line\") == \"/sbin/umount $mountbase\") {\n";
	print PKRULE "    if (subject.local && subject.active && subject.user == \"$login\") {\n";
	print PKRULE "      return polkit.Result.YES;\n";
	print PKRULE "    }\n";
	print PKRULE "  }\n";
	print PKRULE "});\n";

	if ($devtype eq 'cd') {
		print PKRULE "polkit.addRule(function(action, subject) {\n";
		print PKRULE "  if (action.id == \"org.freedesktop.policykit.exec\" &&\n";
		print PKRULE "    action.lookup(\"program\") == \"/bin/eject\" &&\n";
		print PKRULE "    action.lookup(\"command_line\") == \"/bin/eject /dev/$devname$part\") {\n";
		print PKRULE "    if (subject.local && subject.active && subject.user == \"$login\") {\n";
		print PKRULE "      return polkit.Result.YES;\n";
		print PKRULE "    }\n";
		print PKRULE "  }\n";
		print PKRULE "});\n";
	}

	close PKRULE;
}

sub gdbus_call {
	my($action, $args) = @_;
	my $cmd = "gdbus call -e";

	my $pid = fork ();
	if (!defined ($pid)) {
		die "could not fork: $!";
	} elsif ($pid) {
		if (waitpid ($pid, 0) > 0) {
			if ($? >> 8 ne 0) {
				return (1);
			}
		}
	} else {
		$( = $) = "$gid $gid";
		$< = $> = $uid;

		$ENV{"DISPLAY"} = $display;
		$ENV{"HOME"} = $home;
		$ENV{"DBUS_SESSION_BUS_ADDRESS"} = $dbus_session_bus_address;

		if ($action eq 'notify') {
			print ("$args\n");
			if (defined ($dbus_session_bus_address)) {
				$cmd .= " -d org.freedesktop.Notifications";
				$cmd .= " -o /org/freedesktop/Notifications";
				$cmd .= " -m org.freedesktop.Notifications.Notify";
				$cmd .= " toad 42 drive-harddisk-usb";
				$cmd .= " \"Toad\" \"$args\" [] {} 5000 >/dev/null";
				system($cmd);
			}
		} elsif ($action eq 'open-fm') {
			if (defined ($dbus_session_bus_address)) {
				$cmd .= " -d org.freedesktop.FileManager1";
				$cmd .= " -o /org/freedesktop/FileManager1";
				$cmd .= " -m org.freedesktop.FileManager1.ShowFolders";
				$cmd .= " '[\"file://$args\"]' \"\" >/dev/null";
				system($cmd);
			}
		}
		# exit the child
		exit (0);
	}
}

sub get_active_user_info {
	my $system_bus = Net::DBus->system;
	my $ck_service = $system_bus->get_service ('org.freedesktop.ConsoleKit');
	my $ck_manager = $ck_service->get_object ('/org/freedesktop/ConsoleKit/Manager');

	for my $session_id (@{$ck_manager->GetSessions ()}) {
		my $ck_session = $ck_service->get_object ($session_id);
		next unless $ck_session->IsActive ();

		my $uid = $ck_session->GetUnixUser ();
		getpwuid ($uid) || die "no $uid user: $!";
		next unless ($uid >= 1000 && $uid <= 60000);

		my $display = $ck_session->GetX11Display ();
		next unless length ($display);

		my $gid = $pw_gid;
		my $login = $pw_name;
		my $home = $pw_dir;

		return ($login, $uid, $gid, $display, $home);
	}
}

sub get_dbus_session_file {
	my $id;
	my $machine_id = "/etc/machine-id";

	if (open my $fh, "<", $machine_id) {
		read $fh, $id, -s $fh;
		close $fh;
	} else {
		print "Can't open file \"$machine_id\"\n";
		return;
	}

	$id =~ s/\R//g; # drop line break
	$display =~ s/^.{3}//;

	return "$home/.dbus/session-bus/$id-$display";
}

sub get_dbus_session_bus_address {
	my $dbus_session_file = get_dbus_session_file ();

	if (!defined ($dbus_session_file)) {
		return;
	}

	if (open my $fh, "<", $dbus_session_file) {
		while (<$fh>) {
			chomp;
			my ($l, $r) = split /=/, $_, 2;
			if ($l eq "DBUS_SESSION_BUS_ADDRESS") {
				$r =~ s/'//g;
				return ($r);
			}
		}
		close $fh;
	} else {
		print "Can't open file \"$dbus_session_file\"\n";
	}
}

sub get_mount_point {
	my($devname, $part) = @_;
	my $mntgrep;
	my $mntpath;
	my $i = 3;

	do {
		$mntgrep = `/sbin/mount | /usr/bin/grep $devname$part | /usr/bin/awk \'{print \$$i}\'`;
		chomp ($mntgrep);
		if ($mntgrep ne 'type') {
			if ($i >= 4) {
				$mntpath .= "\\ $mntgrep";
			} else {
				$mntpath = $mntgrep;
			}
		}
		$i++;
	} while ($mntgrep ne 'type');

	return ($mntpath);
}

sub get_ntfs_label {
	my($devname, $ntfspart) = @_;
	my $mntntfs;
	my $mntexfat;

	$mntntfs = `/usr/local/sbin/ntfslabel /dev/$devname$ntfspart 2>&1`;
	$mntexfat = `/usr/local/sbin/exfatlabel /dev/$devname$ntfspart 2>&1`;
	chomp ($mntntfs, $mntexfat);
	if (index($mntntfs, 'NTFS signature is missing.') != -1) {
		if ($mntexfat eq '') {
			$mntexfat = "NONAME";
		}
		$mntexfat =~ s/ /\\ /g;
		return ("$mounttop/$mntexfat");
	} else {
		if ($mntntfs eq '') {
			$mntntfs = "NONAME";
		}
		$mntntfs =~ s/ /\\ /g;
		return ("$mounttop/$mntntfs");
	}		
}

sub get_parts {
	my @allparts;
	my @ntfsparts;
	my @supportedfs = ('MSDOS', 'NTFS', '4.2BSD', 'ext2fs', 'ISO9660', 'UDF');

	foreach my $fs (@supportedfs) {
		my $fsmatch = `/sbin/disklabel $devname 2>/dev/null | /usr/bin/grep " $fs "`;
		while ($fsmatch =~ /([^\n]+)\n?/g) {
			my @part = split /:/, $1;
			$part[0] =~ s/ //g;
			push (@allparts, $part[0]);
			if ($fs eq 'NTFS') {
				push (@ntfsparts, $part[0]);
			}
		}
	}

	return (\@allparts, \@ntfsparts);
}

sub mount_device {
	my @parts;
	my @ntfsp;

	# XXX skip device on error (e.g. DIOCGDINFO) or softraid(4) attachment
	if (system ("set -o pipefail; /sbin/disklabel $devname 2>/dev/null | ! grep -qw RAID") != 0) {
		return (0);
	}

	if ($devtype eq 'cd') {
		@parts = 'a';
	} else {
		my ($allparts, $ntfsparts) = get_parts ();
		foreach my $part (@$allparts) {
			if ($part !~ 'c$') {
				push @parts, $part;
			}
		}
		foreach my $ntfs (@$ntfsparts) {
			if ($ntfs !~ 'c$') {
				push @ntfsp, $ntfs;
			}
		}
	}

	unless (@parts) {
		gdbus_call ("notify", "No supported partition found on device $devname");
		return (0);
	}

	if (@ntfsp) {
		foreach my $ntfs (@ntfsp) {
			$ntfs =~ s/^\s+//;
			$mountfuse = get_ntfs_label ($devname, $ntfs);
			create_pkrule ($devname, $ntfs, "$mountfuse");
		}
	}

	if (!-d $mounttop) {
		my $mountrw = system("/usr/local/libexec/hotplug-diskmount -d $mounttop init 2>&1");
		if ($mountrw != 0) {
			gdbus_call ("notify", "Cannot create mount folder $mounttop");
			exit (1);
		}
		sleep (1);
	}
	my $mountrw = system("/usr/local/libexec/hotplug-diskmount -d $mounttop attach -m 0700 -u $login $devname 2>&1");
	if ($mountrw != 0) {
		gdbus_call ("notify", "Cannot mount partitions on device $devname");
		exit (1);
	}
	my $pcount = @parts;
	sleep ($pcount);

	foreach my $part (@parts) {
		unless (grep $_ eq $part, @ntfsp) {
			$part =~ s/^\s+//;
			$mountbase = get_mount_point ($devname, $part);
			create_pkrule ($devname, $part, "$mountbase");
			gdbus_call ("open-fm", "$mountbase");
		} else {
			gdbus_call ("open-fm", "$mountfuse");
		}
	}
}

if ($devclass == 2) {
	$devtype = 'usb';
	$devmax = 10;
} elsif ($devclass == 9) {
	$devtype = 'cd';
	$devmax = 2;
} else {
	gdbus_call ("notify", "Device type not supported");
	exit (1);
}

if ($action eq 'attach') {
	if (!defined ($login) || !defined ($uid) || !defined ($gid)) {
		print "ConsoleKit: user does not own the active session\n";
		exit (1);
	}
	if ($devtype eq 'cd' || $devtype eq 'usb') { mount_device (); }
} elsif ($action eq 'detach') {
	if ($devtype eq 'cd' || $devtype eq 'usb') { broom_sweep (); }
} else { usage (); }
