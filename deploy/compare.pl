use lib '../lib';

use strict;

use Data::Dumper;
use Digest::MD5;
use Date::Format;
use Eldhelm::Util::CommandLine;
use Eldhelm::Util::FileSystem qw(readFileList getFileContents);

my $cmd = Eldhelm::Util::CommandLine->new(
	argv    => \@ARGV,
	options => [
		[ 'h help', 'see this help' ],
		[ 't',      'test folder' ],
		[ 'p',      'production folder' ],
		[ 'n',      'print one file per line' ],
		[ 'q',      'return quoted paths' ],
		[ 'fp',     'return full paths' ]
	],
	examples => [ "perl $0 -t /home/eldhelm/deploy -p /home/eldhelm/server", ]
);

my %ops = $cmd->arguments;
if (!@ARGV || $ops{h} || $ops{help}) {
	print $cmd->usage;
	exit;
}

my ($test, $production) = ($ops{t}, $ops{p});
die "No test folder specified"       unless $test;
die "No production folder specified" unless $production;
die "$test folder invalid"           unless -d $test;
die "$production folder invalid"     unless -d $production;

my @tList = readFileList($test);
s/^$test// foreach @tList;
my @pList = readFileList($production);
s/^$production// foreach @pList;

sub getCheckum {
	my $md5  = Digest::MD5->new;
	my $data = getFileContents($_[0]);
	$data =~ s/\r\n/\n/g;
	$md5->add($data);
	return $md5->hexdigest;
}

sub getMeta {
	my ($path, $list) = @_;
	my $lookup = {};
	foreach my $f (@$list) {
		my $p = "$path/$f";
		my @s = stat($p);
		$lookup->{$f} = [ $s[7], $s[9], getCheckum($p) ];
	}
	return $lookup;
}

my $tMap = getMeta($test,       \@tList);
my $pMap = getMeta($production, \@pList);

my @manifest;
foreach my $f (keys %$tMap) {
	unless ($pMap->{$f}) {
		push @manifest, $f;
		next;
	}
	my $t = $tMap->{$f};
	my $p = $pMap->{$f};

	die "$f is 0b ... aborting!" unless $t->[0];

	if ($t->[2] ne $p->[2]) {
		warn "$f; $p->[2] -> $t->[2]; $p->[0]b -> $t->[0]b; "
			.time2str('%d.%m.%Y %T', $p->[1])." -> "
			.time2str('%d.%m.%Y %T', $t->[1]).";\n";
		push @manifest, $f;
		next;
	}
}

if ($ops{fp}) {
	$_ = $test.$_ foreach @manifest;
}

@manifest = sort { $a cmp $b } @manifest;
if ($ops{n}) {
	foreach (@manifest) {
		print "$_\n";
	}
} elsif ($ops{q}) {
	print join ' ', map { qq~"$_"~ } @manifest;
} else {
	print join ' ', @manifest;
}
