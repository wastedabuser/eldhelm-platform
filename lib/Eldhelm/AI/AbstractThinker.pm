package Eldhelm::AI::AbstractThinker;

use strict;

use Carp qw(confess longmess);
use Data::Dumper;
use Date::Format;
use Eldhelm::Util::FileSystem;

sub new {
	my ($class, %args) = @_;
	my $self = {%args};
	bless $self, $class;
	
	return $self;
}

sub getPath {
	my ($self, $name) = @_;
	return "$self->{rootPath}Eldhelm/Application/AI/Definition/".join('/', split(/\./, $name)).'.pl';
}

sub loadFile {
	my ($self, $name) = @_;
	my $path = $self->getPath($name || $self->{name});
	unless (-f $path) {
		$self->log(longmess "Can not load path '$path'");
		return;
	}
	$self->log("Loading path '$path'");
	my $ret = do $path;
	$self->log($@) if $@;
	return $ret;
}

sub log {
	my ($self, $msg) = @_;
	return unless $self->{logEnabled};

	my $path = $self->{logPath};
	if ($path) {
		Eldhelm::Util::FileSystem->appendFileContents($path, $msg, "\n");
	} else {
		print "$msg\n";
	}
}

sub logStart {
	my ($self) = @_;
	$self->log(time2str('%d.%m.%Y %T', time).': ===========================================');
}

1;