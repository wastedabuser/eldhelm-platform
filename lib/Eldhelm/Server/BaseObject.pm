package Eldhelm::Server::BaseObject;

use Eldhelm::Server::Child;
use Eldhelm::Server::Main;
use Eldhelm::Util::Factory;
use strict;
use threads::shared;
use Eldhelm::Util::Tool;

sub worker {
	my ($self) = @_;
	return Eldhelm::Server::Child->instance || Eldhelm::Server::Main->instance;
}

sub compose {
	my ($self, $data, $options) = @_;
	my $composer = $self->get("composer");
	if ($composer) {
		Eldhelm::Util::Factory->usePackage($composer);
		my $composed;
		eval { $composed = $composer->compose($data, $options) };
		$self->worker->error("Error while encoding data: $@") if $@;
		return $composed;
	} else {
		return $data;
	}
}

sub getRefByNotation {
	my ($self, $key) = @_;
	return ($self, $key) if $key !~ /\./;
	my @chunks = split /\./, $key;
	my $name = pop @chunks;
	return ($self, $name) unless @chunks;
	my $var = $self;
	$var = $var->{$_} ||= shared_clone({}) foreach @chunks;
	return ($var, $name);
}

sub set {
	my ($self, $key, $value) = @_;
	lock($self);

	my ($var, $key) = $self->getRefByNotation($key);
	if (ref $value) {
		$var->{$key} = shared_clone($value);
	} else {
		$var->{$key} = $value;
	}
	return $self;
}

sub setHash {
	my ($self, %values) = @_;
	lock($self);

	$self->set($_, $values{$_}) foreach keys %values;
	return $self;
}

sub get {
	my ($self, $key) = @_;
	lock($self);

	my ($var, $key) = $self->getRefByNotation($key);
	return $var->{$key};
}

sub getList {
	my ($self, @list) = @_;
	lock($self);

	return map { $self->get($_) } @list;
}

sub getPureList {
	my ($self, @list) = @_;
	lock($self);

	return map { ref $self->{$_} eq "ARRAY" ? @{ $self->{$_} } : $self->{$_} || () } @list;
}

sub getHash {
	my ($self, @list) = @_;
	lock($self);

	return map { +$_ => $self->get($_) } @list;
}

sub getDefinedAsHash {
	my ($self, @list) = @_;
	lock($self);

	return map { +$_ => $self->{$_} } grep { defined $self->{$_} } @list;
}

sub remove {
	my ($self, $key) = @_;
	lock($self);

	my ($var, $key) = $self->getRefByNotation($key);
	return delete $var->{$key};
}

sub removeList {
	my ($self, @list) = @_;
	lock($self);

	my @deleted;
	push @deleted, delete $self->{$_} foreach @list;

	return @deleted;
}

sub inc {
	my ($self, $key, $amount) = @_;
	lock($self);

	my ($var, $key) = $self->getRefByNotation($key);
	return $var->{$key} += $amount || 1;
}

sub dec {
	my ($self, $key, $amount) = @_;
	lock($self);

	my ($var, $key) = $self->getRefByNotation($key);
	return $var->{$key} -= $amount || 1;
}

sub pushItem {
	my ($self, $key, $item) = @_;
	lock($self);

	my ($var, $key) = $self->getRefByNotation($key);
	return unless ref $var;

	$var->{$key} ||= [];
	return push @{ $var->{$key} }, shared_clone($item);
}

sub grepArrayref {
	my ($self, $key, $fn, @options) = @_;
	lock($self);

	my ($var, $key) = $self->getRefByNotation($key);
	return unless ref $var && ref $var->{$key} eq "ARRAY";

	my $list = $var->{$key};
	@$list = grep { $fn->($_, @options) } @$list;

	return $list;
}

sub clearArrayref {
	my ($self, $key) = @_;
	lock($self);

	my ($var, $key) = $self->getRefByNotation($key);
	return $self unless ref $var;

	if (ref $var->{$key} eq "ARRAY") {
		@{ $var->{$key} } = ();
	} else {
		$var->{$key} = shared_clone([]);
	}

	return $self;
}

sub scalarArrayref {
	my ($self, $key) = @_;
	lock($self);

	my ($var, $key) = $self->getRefByNotation($key);
	return unless ref $var && ref $var->{$key} eq "ARRAY";

	return scalar @{ $var->{$key} };
}

sub getHashrefHash {
	my ($self, $key) = @_;
	lock($self);

	my ($var, $key) = $self->getRefByNotation($key);
	my $ref = $var->{$key};
	return () if ref $ref ne "HASH";

	return %$ref;
}

sub getHashrefKeys {
	my ($self, $key) = @_;
	lock($self);

	my ($var, $key) = $self->getRefByNotation($key);
	my $ref = $var->{$key};
	return () if ref $ref ne "HASH";

	return keys %$ref;
}

sub getHashrefValues {
	my ($self, $key, $keysList) = @_;
	lock($self);

	my ($var, $key) = $self->getRefByNotation($key);
	my $ref = $var->{$key};
	return () if ref $ref ne "HASH";

	if (ref $keysList eq "ARRAY") {
		return map { $ref->{$_} } grep { exists $ref->{$_} } @$keysList;
	}

	return values %$ref;
}

sub clone {
	my ($self, $key) = @_;
	lock($self);
	
	my ($var, $key) = $self->getRefByNotation($key);
	my $ref = $var->{$key};

	return Eldhelm::Util::Tool::cloneStructure($ref);
}

sub doFn {
	my ($self, $fn, @options) = @_;
	lock($self);
	
	return $fn->($self, @options);
}

1;
