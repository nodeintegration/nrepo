use strict;
use warnings FATAL => 'all';

package App::Nrepo::Repo::Plugin::Yum;

use Moo;
use Carp;
use Module::Pluggable::Object;
use Params::Validate qw(:all);
use Data::Dumper;

with('App::Nrepo::Repo');

sub get_metadata {
  my $self = shift;
  print "DEBUG: get_metadata from App::Nrepo::Repo::Plugin::Yum\n";

}
sub type {
  my $self = shift;
  return 'Yum';
}

1;
