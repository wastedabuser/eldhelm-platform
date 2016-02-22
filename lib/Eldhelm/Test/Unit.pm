package Eldhelm::Test::Unit;

use strict;

use Eldhelm::Perl::SourceParser;

sub new {
	my ($class, %args) = @_;
	my $self = {%args};
	bless $self, $class;

	$self->{sourceParser} = Eldhelm::Perl::SourceParser->new;
	$self->unitForFile($args{file}) if $args{file};

	return $self;
}

sub unitForFile {
	my ($self, $file) = @_;

	my @chunks = split /[\/\\]+/, $file;
	my $path = '';
	my @files;
	foreach (@chunks) {
		$path .= "$_/";
		my $f = "${path}_.test";
		push @files, $f if -f $f;
	}

	my @tests;
	foreach (@files) {
		my $fileData = do $_;
		next unless ref $fileData;
		next unless $fileData->{utitTests};
		push @tests, @{ $fileData->{utitTests} };
	}

	my $data = $self->{sourceData} = $self->{sourceParser}->parseFile($file);
	return $self->{unitTests} = [ @tests, @{ $data->{unitTests} } ];
}

sub sourceData {
	my ($self) = @_;
	return $self->{sourceData};
}

sub unitTests {
	my ($self) = @_;
	return $self->{unitTests};
}

1;
