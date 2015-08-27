use strict;
use warnings FATAL => 'all';

package App::Nrepo::Repo;

use Moo::Role;
use Carp;
use Module::Pluggable::Object;
use Params::Validate qw(:all);
use Data::Dumper;

sub mirror {
  my $self = shift;
  my %o = validate(@_, {
    type => { type => SCALAR, },
    repo => { type => SCALAR, },
    dir  => { type => SCALAR, },
    url  => { type => SCALAR, },
    checksums   => { type => BOOLEAN, optional => 1, },
  });

  my $plugin;
  for my $p (Module::Pluggable::Object->new(instantiate => 'new', search_path => ['App::Nrepo::Repo::Plugin'])->plugins() ) {
    next unless $p->type() eq $o{'type'};
    $plugin = $p;
  }

  $self->logger->log_and_croak('level' => 'error', 'message' => sprintf 'repo: %s Cant find Plugin for type: %s', $o{'repo'}, $o{'type'}) unless $plugin;

  $plugin->get_metadata();
  $plugin->get_packages();

}

sub get_packages {
  print "DEBUG: App::Nrepo::Repo\n";
}

1;
