package Eldhelm::Helper::Html::Table;

use strict;

use Eldhelm::Util::Url;
use Eldhelm::Helper::Html::Form;
use Data::Dumper;

sub new {
	my ($class, %args) = @_;
	my $self = {
		columns       => $args{columns}       || [],
		filters       => $args{filters},
		data          => $args{data}          || [],
		model         => $args{model},
		filter        => $args{filter}        || {},
		currentParams => $args{currentParams} || {},
		currentUrl    => $args{currentUrl},
		addUrl        => $args{addUrl},
		editUrl       => $args{editUrl},
		removeUrl     => $args{removeUrl},
		pkFields      => $args{pkFields}      || ["id"],
		page          => $args{page}          || 1,
		pageSize      => $args{pageSize}      || 100,
	};
	bless $self, $class;

	$self->init;

	return $self;
}

sub init {
	my ($self) = @_;
	my $params = $self->{currentParams};

	$self->{page} = $params->{helper_html_table_page} if $params->{helper_html_table_page};
	$self->setDataCount(scalar @{ $self->{data} });

	my %moreFilters;
	foreach (keys %$params) {
		next unless /^helper_html_table_filter_(.+)$/;
		next unless $params->{$_};
		$moreFilters{$1} = $params->{$_};
	}
	%{ $self->{filter} } = (%{ $self->{filter} }, %moreFilters)
		if keys %moreFilters;
}

sub setDataCount {
	my ($self, $count) = @_;
	$self->{dataCount} = $count;
	if (!$count) {
		$self->{pageCount} = 0;
		return;
	}
	$self->{pageCount} = int($count / $self->{pageSize} + 1);
}

sub fetchModelData {
	my ($self) = @_;
	my $model = $self->{model};
	$model->setPage($self->{page}, $self->{pageSize}) if $self->{currentUrl};
	$self->{pkFields} = $model->{pkFields};
	$self->{data} = $self->{filter} ? $model->filter($self->{filter}) : $model->getAll;
	$self->setDataCount($self->{filter} ? $model->countByFilter($self->{filter}) : $model->countAll);
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

	my @body;
	my $i         = ($self->{page} - 1) * $self->{pageSize} + 1;
	my $editUrl   = Eldhelm::Util::Url->new(uri => $self->{editUrl});
	my $removeUrl = Eldhelm::Util::Url->new(uri => $self->{removeUrl});

	foreach my $d (@{ $self->{data} }) {
		my @more;
		push @more, qq~[<a href="${\($self->createControlLinks($editUrl, $d))}">edit</a>]~ if $self->{editUrl};
		push @more,
			qq~[<a href="${\($self->createControlLinks($removeUrl, $d))}" onclick="return confirm('Sure?');">del</a>]~
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
		my $class;
		$class = qq~ class="alt"~ unless $i % 2;
		push @body, qq~<tr${class}>~.join("", "<td>$i</td>", map("<td>$_</td>", @more, @fields))."</tr>\n";
		$i++;
	}

	my @controls = (qq~$self->{dataCount} records~);
	my $addUrl = $self->{addUrl} || $self->{editUrl};
	push @controls, qq~<a href="$addUrl">add new</a>~ if $addUrl;

	if ($self->{currentUrl}) {
		my $baseUrl = Eldhelm::Util::Url->new(uri => $self->{currentUrl});

		my $pp = $self->{page} - 1;
		if ($pp > 0) {
			my $furl = $baseUrl->compileWithParams({ helper_html_table_page => 1 });
			my $purl = $baseUrl->compileWithParams({ helper_html_table_page => $pp });
			push @controls, qq~<a href="$furl">first page</a>~;
			push @controls, qq~<a href="$purl">prev page</a>~;
		}
		my $pn = $self->{page} + 1;
		if ($pn <= $self->{pageCount}) {
			my $nurl = $baseUrl->compileWithParams({ helper_html_table_page => $pn });
			my $lurl = $baseUrl->compileWithParams({ helper_html_table_page => $self->{pageCount} });
			push @controls, qq~<a href="$nurl">next page</a>~;
			push @controls, qq~<a href="$lurl">last page</a>~;
		}
	}
	my $controls = join " | ", @controls;

	my $filter;
	if ($self->{filters} && $self->{currentUrl}) {
		my $list = $self->{filters};
		foreach (@$list) {
			$_->{label} ||= $_->{name};
			$_->{name} = "helper_html_table_filter_$_->{name}";
		}
		my $form = Eldhelm::Helper::Html::Form->new(
			action     => $self->{currentUrl},
			fields     => $list,
			formValues => $self->{currentParams},
		);
		$form->add($form->createSubmit({ value => "Filter" }).$form->createReset({ value => "Clear" }));
		$filter = $form->compile;
	}

	return qq~
	$controls
	$filter
	<table class="helper-table">
	<tr>
		$header
	</tr>
	@body</table>~;
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
	return qq~[<a href="$url" target="$target">$label</a>]~;
}

sub applyTpl {
	my ($self, $tpl, $args) = @_;
	return if !$tpl;
	$tpl =~ s/\{(.+?)\}/$args->{$1}/ge;
	return $tpl;
}

1;
