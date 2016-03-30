package Eldhelm::AI::BehaviourTree;

use strict;

use Carp qw(confess longmess);
use Data::Dumper;
use Date::Format;
use Eldhelm::Util::Factory;
use Eldhelm::Util::FileSystem;

sub new {
	my ($class, %args) = @_;
	my $self = {%args};
	bless $self, $class;

	$self->loadDefinition($args{name}) if $args{name};

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

sub loadDefinition {
	my ($self, $name) = @_;
	$self->{definition} = $self->loadFile($name);
}

sub getNodeObject {
	my ($self, $def, %args) = @_;
	my $class = $def->{class};
	%args = (%$def, %args, bTree => $self);
	return Eldhelm::Util::Factory->instanceFromNotation("Eldhelm::Application::AI::BehaviourTree::$class", %args)
		if $class;

	my $type = $def->{type};
	unless ($type) {
		$self->log(longmess 'Can not determine node type for: '.Dumper($def));
		die;
	}
	return Eldhelm::Util::Factory->instance("Eldhelm::AI::BehaviourTree::$type", %args);
}

sub traverse {
	my ($self) = @_;
	$self->log(time2str('%d.%m.%Y %T', time).': ===========================================');
	$self->log('Starting tree traversal');
	my $status = $self->{status} = $self->getNodeObject($self->{definition})->update;
	$self->log("Done tree traversal: $status");
}

sub evaluateProperty {
	my ($self, $value) = @_;
	return $value if ref $value || $value !~ /\$/;

	my $params  = $self->{params};
	my $context = $self->{context};
	$value =~ s/\$(\w+)/exists $params->{$1} ? "\$params->{$1}" : "\$context->$1()"/ge;
	my $ret = eval($value);
	$self->log(longmess $@) if $@;
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

1;
