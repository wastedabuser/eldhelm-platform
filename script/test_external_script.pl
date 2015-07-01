use strict;

use lib "../lib";
use lib "../../lib";

use Data::Dumper;
use Eldhelm::Util::ExternalScript;

my $configPath = shift @ARGV;
my ($data) = Eldhelm::Util::ExternalScript->argv(@ARGV);

warn "# $configPath\n";
warn "# $data->{some_data_here}{deeply}\n";