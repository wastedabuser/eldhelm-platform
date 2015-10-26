use strict;

use lib '../lib';

use Cwd 'abs_path';
use Eldhelm::Pod::DocCompiler;
use Eldhelm::Util::CommandLine;

my $cmd = Eldhelm::Util::CommandLine->new(
	argv    => \@ARGV,
	items   => [ [ 'files', 'folders' ], ],
	options => [
		[ 'h help', 'this help text' ],
		[ 'tpl',    'Template in dotted notation' ],
		[ 'ctpl',   'Contents template in dotted notation' ],
		[ 'o',      'Output folder' ],
		[ 'oc',     'Contents output file' ],
		[ 'off',    'File name format' ],
		[ 'oe',     'File name extension' ]
	]
);

my %args = $cmd->arguments;

if ($args{h} || $args{help}) {
	print $cmd->usage;
	exit;
}

my $path = abs_path($0);
$path =~ s/platform.script.pod2doc\.pl//g;

Eldhelm::Pod::DocCompiler->new(
	debug              => 1,
	files              => $args{list},
	tpl                => $args{tpl},
	contentsTpl        => $args{ctpl},
	outputFolder       => $args{o},
	contentsOutputFile => $args{oc},
	fileNameFormat     => $args{off},
	fileNameExtension  => $args{oe},
	rootPath           => $path,
);
