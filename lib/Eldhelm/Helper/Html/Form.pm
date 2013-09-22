package Eldhelm::Helper::Html::Form;

use strict;
use Carp;
use Data::Dumper;

sub new {
	my ($class, %args) = @_;
	my $self = {
		items => $args{items} || [],
		action     => $args{action},
		method     => $args{method} || "post",
		formValues => $args{formValues} || {},
	};
	bless $self, $class;

	$self->addFields($args{fields}) if $args{fields};

	return $self;
}

sub enc {
	my ($self, $str) = @_;
	$str =~ s/&/&amp;/g;
	$str =~ s/"/&quot;/g;
	$str =~ s/</&lt;/g;
	$str =~ s/>/&gt;/g;
	return $str;
}

sub compile {
	my ($self) = @_;

	my $items = join "\n", map { "\t<p>$_</p>" } @{ $self->{items} };

	return qq~<form action="$self->{action}" method="$self->{method}">
$items
</form>~;
}

sub addFields {
	my ($self, $list) = @_;
	foreach (@$list) {
		confess "Unknown field type $_->{type}" unless $_->{type};
		my $fn = "create".ucfirst($_->{type});
		$self->add($self->$fn($_));
	}
}

sub add {
	my ($self, $field) = @_;
	push @{ $self->{items} }, $field;
	return $self;
}

sub createFieldProperties {
	my ($self, $args, $custom) = @_;
	$custom ||= [];

	# $args->{value} ||= $self->{formValues}{ $args->{name} } if $args->{name};
	return join " ", map { qq~$_="~.$self->enc($args->{$_}).'"' }
		grep { defined $args->{$_} } qw(type id name value class), @$custom;
}

sub createLabel {
	my ($self, $args) = @_;
	return if !$args->{label};
	return qq~<label for="$args->{id}">$args->{label}:</label>~;
}

sub createInput {
	my ($self, $args, $options) = @_;
	$options ||= {};
	$options->{tag} ||= "input";
	return
		 $self->createLabel($args)
		."<$options->{tag} "
		.$self->createFieldProperties($args, $options->{customAttributes})
		." >$options->{content}</$options->{tag}>";
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
	$args->{checkedValue} ||= 1;
	$args->{value}   = $self->createValue($args);
	$args->{checked} = ($args->{value} eq $args->{checkedValue}) || undef;
	$args->{value}   = $args->{checkedValue};
	return $self->createHidden({ staticValue => 0, name => $args->{name} })
		.$self->createInput($args, { customAttributes => ["checked"] });
}

sub createCombo {
	my ($self, $args, $items) = @_;
	$args  ||= {};
	$items ||= [];
	$args->{type}  = "select";
	$args->{value} = $self->createValue($args);
	my ($key, $value) = ($args->{itemKey} || "key", $args->{itemValue} || "value");
	my $cont = join "\n", map {
		     qq~\t\t<option value="$_->{$key}" ~
			.($args->{value} eq $_->{$key} ? "selected" : "")
			.qq~>$_->{$value}</option>~
	} @$items;
	delete $args->{value};
	return $self->createInput(
		$args,
		{   content => "\n$cont",
			tag     => "select",
		}
	);
}

sub createArea {
	my ($self, $args) = @_;
	$args ||= {};
	my $cont = $self->createValue($args);
	delete $args->{value};
	return $self->createInput(
		$args,
		{   tag     => "textarea",
			content => $self->enc($cont)
		}
	);
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
