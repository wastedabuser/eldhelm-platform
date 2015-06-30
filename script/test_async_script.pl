use strict;
use lib "../lib";

use Data::Dumper;
use Eldhelm::Util::AsyncScript;

my $configPath = shift @ARGV;
my ($data) = Eldhelm::Util::AsyncScript->argv(@ARGV);

warn "# $configPath";
warn "# $data->{some_data_here}{deeply}";
