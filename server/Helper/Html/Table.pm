package Eldhelm::Helper::Html::Table;

use strict;

use Eldhelm::Util::Url;
use Data::Dumper;

sub new {
	my ($class, %args) = @_;
	my $self = {
		columns => $args{columns} || [],
		data    => $args{data}    || [],
		model   => $args{model},
		filter  => $args{filter},
		addUrl  => $args{addUrl},
		editUrl => $args{editUrl},
		removeUrl => $args{removeUrl},
		pkFields  => $args{pkFields} || ["id"],
	};
	bless $self, $class;

	return $self;
}

sub fetchModelData {
	my ($self) = @_;
	my $model = $self->{model};
	$self->{pkFields} = $model->{pkFields};
	$self->{data} = $self->{filter} ? $model->filter($self->{filter}) : $model->getAll;
}

sub fetchRelatedColumns {
	my ($self) = @_;
	my @models = grep { $_->{model} } @{ $self->{columns} };
	return if !@models;

	my $data = $self->{data};
	my $model = $self->{model} || Eldhelm::Basic::Model->new;
	my (%hModels, %oModels, %rData);
	foreach (@models) {
		my $k = "$_->{model}-$_->{dataIndex}";
		$hModels{$k} = {
			key       => $k,
			model     => $_->{model},
			dataIndex => $_->{dataIndex},
			fields    => [],
			}
			if !$hModels{$k};
		push @{ $hModels{$k}{fields} }, $_->{field};
	}

	foreach my $m (values %hModels) {
		my $mod = $oModels{ $m->{model} } ||= $model->getModel($m->{model});
		my @ids = grep { $_ } map { $_->{ $m->{dataIndex} } } @$data;
		$rData{ $m->{key} } = $mod->getHashByIds(\@ids, "id", [ "id", @{ $m->{fields} } ])
			if @ids;
	}

	foreach my $d (@$data) {
		foreach my $m (@models) {
			my $k     = "$m->{model}-$m->{dataIndex}";
			my $mData = $rData{$k};
			next if !$mData;
			my $id = $d->{ $m->{dataIndex} };
			if ($id) {
				$d->{"$m->{dataIndex}-$m->{field}"} = $mData->{$id}{ $m->{field} };
			}
		}
	}
}

sub compile {
	my ($self) = @_;

	$self->fetchModelData if $self->{model};
	$self->fetchRelatedColumns;

	my @more = ($self->{editUrl} ? {} : (), $self->{removeUrl} ? {} : (),);
	my $header = join "", "<th>No</th>", map { "<th>$_->{header}</th>" } @more, @{ $self->{columns} };
	my $controls;
	my @body;
	my $i         = 1;
	my $editUrl   = Eldhelm::Util::Url->new(uri => $self->{editUrl});
	my $removeUrl = Eldhelm::Util::Url->new(uri => $self->{removeUrl});

	foreach my $d (@{ $self->{data} }) {
		my @more;
		push @more, qq~<a href="${\($self->createControlLinks($editUrl, $d))}">edit</a>~ if $self->{editUrl};
		push @more,
			qq~<a href="${\($self->createControlLinks($removeUrl, $d))}" onclick="return confirm('Sure?');">del</a>~
			if $self->{removeUrl};
		my @fields;
		foreach (@{ $self->{columns} }) {
			if ($_->{dataIndex} && $_->{field}) {
				push @fields, $d->{"$_->{dataIndex}-$_->{field}"};
			} elsif ($_->{dataIndex}) {
				push @fields, $d->{ $_->{dataIndex} };
			} else {
				push @fields, $self->createField($_, $d);
			}
		}
		push @body, "<tr>".join("", "<td>$i</td>", map("<td>$_</td>", @more, @fields))."</tr>";
		$i++;
	}
	my $addUrl = $self->{addUrl} || $self->{editUrl};
	$controls = qq~<a href="$addUrl">add new</a>~ if $addUrl;
	return qq~
	$controls
	<table>
	<tr>
		$header
	</tr>
	@body
</table>~;
}

sub createControlLinks {
	my ($self, $urlObj, $d) = @_;
	return $urlObj->compileWithParams({ map { +$_ => $d->{$_} } @{ $self->{pkFields} } });
}

sub createField {
	my ($self, $col, $data) = @_;
	my $url   = $self->applyTpl($col->{urlTpl},   $data);
	my $label = $self->applyTpl($col->{labelTpl}, $data);
	my $target = $col->{target} || "_self";
	$url   ||= $col->{url};
	$label ||= $col->{label};
	return qq~<a href="$url" target="$target">$label</a>~;
}

sub applyTpl {
	my ($self, $tpl, $args) = @_;
	return if !$tpl;
	$tpl =~ s/\{(.+?)\}/$args->{$1}/ge;
	return $tpl;
}

1;
