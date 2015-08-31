package App::Nrepo::Repo;

use Moo;
use Carp;
use Module::Pluggable::Object;
use Params::Validate qw(:all);
use Data::Dumper;

has logger   => ( is => 'ro' );
has repo     => ( is => 'ro' );
has dir      => ( is => 'ro' );
has type     => ( is => 'ro' );
has plugin   => ( is => 'lazy');

sub _build_plugin {
  my $self = shift;
  my $plugin;
  for my $p (Module::Pluggable::Object->new(instantiate => 'new', search_path => ['App::Nrepo::Repo::Plugin'])->plugins() ) {
    next unless $p->type() eq $self->type();
    return $p;
  }
  $self->logger->log_and_croak('level' => 'error', 'message' => sprintf 'repo: %s Cant find Plugin for type: %s', $self->repo(), $self->type()) unless $self->plugin();
}

sub mirror {
  my $self = shift;
  my %o = validate(@_, {
    url       => { type => SCALAR },
    checksums => { type => BOOLEAN, optional => 1, },
  });

  unless ($self->plugin()) {
    $self->_get_plugin();
  }

  $self->plugin->get_metadata();
  $self->plugin->get_packages();

}
sub init {
  my $self = shift;
  my %o = validate(@_, {
    type => { type => SCALAR, },
    repo => { type => SCALAR, },
    dir  => { type => SCALAR, },
    url  => { type => SCALAR, },
    checksums   => { type => BOOLEAN, optional => 1, },
    plugin => { type => SCALAR, },
  });

  #$plugin->init();
  print "Here\n";

}

sub get_packages {
  print "DEBUG: get_packages from App::Nrepo::Repo\n";
}

1;
