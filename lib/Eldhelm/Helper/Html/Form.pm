package Eldhelm::Helper::Html::Form;

use strict;
use Carp;
use Data::Dumper;
use Eldhelm::Helper::Html::Node;

sub new {
	my ($class, %args) = @_;
	my $self = {
		id    => $args{id}    || "form".int(rand() * 100_000),
		items => $args{items} || [],
		action     => $args{action},
		method     => $args{method} || "post",
		formValues => $args{formValues} || {},
	};
	bless $self, $class;

	$self->addFields($args{fields}) if $args{fields};

	return $self;
}

sub compile {
	my ($self) = @_;

	my $items = join "\n", map { "\t<p>$_</p>" } @{ $self->{items} };

	return qq~<form action="$self->{action}" id="$self->{id}" method="$self->{method}">
$items
</form>~;
}

sub addFields {
	my ($self, $list) = @_;
	foreach (@$list) {
		confess "Unknown field type $_->{type}" unless $_->{type};
		my $fn = "create".ucfirst($_->{type});
		$self->add($self->$fn($_, $_->{_items}));
	}
}

sub add {
	my ($self, $field) = @_;
	push @{ $self->{items} }, $field;
	return $self;
}

sub createFieldProperties {
	my ($self, $args) = @_;
	return join " ", map { qq~$_="~.Eldhelm::Helper::Html::Node->enc($args->{$_}).'"' }
		grep { $_ !~ /^_/ && defined $args->{$_} } keys %$args;
}

sub createLabel {
	my ($self, $args) = @_;
	return if !$args->{label};
	return qq~<label for="$args->{id}">$args->{label}:</label>~;
}

sub createInput {
	my ($self, $args) = @_;
	$args->{_tag} ||= "input";
	$args->{id}   ||= "$self->{id}-$args->{name}" if $args->{name};
	return
		 $self->createLabel($args)
		."<$args->{_tag} "
		.$self->createFieldProperties($args)
		." >$args->{_content}</$args->{_tag}>";
}

sub createValue {
	my ($self, $args) = @_;
	my $name = $args->{name};
	return $args->{staticValue} if defined $args->{staticValue};
	return exists $self->{formValues}{$name} ? $self->{formValues}{$name} : $args->{value};
}

sub createHidden {
	my ($self, $args) = @_;
	$args ||= {};
	$args->{type}  = "hidden";
	$args->{value} = $self->createValue($args);
	return $self->createInput($args);
}

sub createText {
	my ($self, $args) = @_;
	$args ||= {};
	$args->{type}  = "text";
	$args->{value} = $self->createValue($args);
	return $self->createInput($args);
}

sub createCheckbox {
	my ($self, $args) = @_;
	$args ||= {};
	$args->{type} = "checkbox";
	$args->{_checkedValue} ||= 1;
	$args->{value}   = $self->createValue($args);
	$args->{checked} = ($args->{value} eq $args->{_checkedValue}) || undef;
	$args->{value}   = $args->{_checkedValue};
	return $self->createHidden({ staticValue => 0, name => $args->{name} }).$self->createInput($args);
}

sub createCombo {
	my ($self, $args, $items) = @_;
	$args  ||= {};
	$items ||= [];
	$args->{value} = $self->createValue($args);
	my ($key, $value) = ($args->{itemKey} || "key", $args->{itemValue} || "value");
	my $cont = join "\n", map {
		     qq~\t\t<option value="$_->{$key}" ~
			.($args->{value} eq $_->{$key} ? "selected" : "")
			.qq~>$_->{$value}</option>~
	} @$items;
	delete $args->{value};
	$args->{_content} = "\n$cont";
	$args->{_tag}     = "select";
	return $self->createInput($args);
}

sub createArea {
	my ($self, $args) = @_;
	$args ||= {};
	my $cont = $self->createValue($args);
	delete $args->{value};
	$args->{_content} = Eldhelm::Helper::Html::Node->enc($cont);
	$args->{_tag}     = "textarea";
	return $self->createInput($args);
}

sub createSubmit {
	my ($self, $args) = @_;
	$args ||= {};
	$args->{type} = "submit";
	return $self->createInput($args);
}

sub createReset {
	my ($self, $args) = @_;
	$args ||= {};
	$args->{type} = "reset";
	return $self->createInput($args);
}

1;
