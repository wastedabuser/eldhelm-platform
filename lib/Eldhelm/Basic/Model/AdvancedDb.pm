package Eldhelm::Basic::Model::AdvancedDb;

use strict;
use Data::Dumper;
use Eldhelm::Util::Tool;
use Eldhelm::Database::Template;

use base qw(Eldhelm::Basic::Model);

sub new {
	my ($class, %args) = @_;
	my $self = $class->SUPER::new(%args);
	bless $self, $class;

	return $self;
}

sub template {
	my ($self, $args) = @_;
	return Eldhelm::Database::Template->new(sql => $self->{dbPool}->getDb, %$args) if ref $args eq "HASH";
	return Eldhelm::Database::Template->new(
		sql          => $self->{dbPool}->getDb,
		stream       => $args,
		placeholders => $self->{defaultPlacehoders},
		filter       => $self->{defaultFilter}
	);
}

sub applyTemplate {
	my ($self, $template) = @_;
	return $template if ref $template =~ /^Eldhelm::Database::Template/;
	return $self->template($template);
}

sub getScalar {
	my ($self, $template, $args, @more) = @_;
	my $tpl = $self->applyTemplate($template);
	my $sql = $self->{dbPool}->getDb;
	return $sql->fetchScalar($tpl->compile($args), @more);
}

sub getRow {
	my ($self, $template, $args, @more) = @_;
	my $tpl = $self->applyTemplate($template);
	my $sql = $self->{dbPool}->getDb;
	return $sql->fetchRow($tpl->compile($args), @more);
}

sub getColumn {
	my ($self, $template, $args, @more) = @_;
	my $tpl = $self->applyTemplate($template);
	my $sql = $self->{dbPool}->getDb;
	return $sql->fetchColumn($tpl->compile($args), @more);
}

sub getArray {
	my ($self, $template, $args, @more) = @_;
	my $tpl = $self->applyTemplate($template);
	my $sql = $self->{dbPool}->getDb;
	return $sql->fetchArray($tpl->compile($args), @more);
}

sub getAssocArray {
	my ($self, $template, $args, @more) = @_;
	my $tpl = $self->applyTemplate($template);
	my $sql = $self->{dbPool}->getDb;
	return $sql->fetchAssocArray($tpl->compile($args), @more);
}

sub getArrayOfArrays {
	my ($self, $template, $args, @more) = @_;
	my $tpl = $self->applyTemplate($template);
	my $sql = $self->{dbPool}->getDb;
	return $sql->fetchArrayOfArrays($tpl->compile($args), @more);
}

sub getHash {
	my ($self, $template, $args, @more) = @_;
	my $tpl = $self->applyTemplate($template);
	my $sql = $self->{dbPool}->getDb;
	return $sql->fetchHash($tpl->compile($args), @more);
}

sub getKeyValue {
	my ($self, $template, $args, @more) = @_;
	my $tpl = $self->applyTemplate($template);
	my $sql = $self->{dbPool}->getDb;
	return $sql->fetchKeyValue($tpl->compile($args), @more);
}

1;
