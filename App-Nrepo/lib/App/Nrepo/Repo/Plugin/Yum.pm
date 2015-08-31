package App::Nrepo::Repo::Plugin::Yum;

use Moo;
use Carp;
use Module::Pluggable::Object;
use Params::Validate qw(:all);
use Data::Dumper;

extends('App::Nrepo::Repo');

sub get_metadata {
  my $self = shift;
  print "DEBUG: get_metadata from App::Nrepo::Repo::Plugin::Yum\n";

}
sub init {
  my $self = shift;
  #my $repodata_path = File::Spec->catdir($repo_dir, 'repodata');
  #$self->app->logger->debug("init: repodata_path: ${repodata_path}");
  #unless (-d $repodata_path) {
  #  $self->app->logger->debug("init: make_path: ${repodata_path}");
  #  my $make_path_error;
  #  #my $dirs = File::Path->make_path($repodata_path, { error => \$make_path_error },);
  #  #my $dirs = File::Path->make_path($repodata_path);
  #  unless (File::Path->make_path($repodata_path)) {
  #    $self->app->logger->log_and_croak(level => 'error', message => "init: unable to create path: ${repodata_path}");
  #  }
  #}
#
#  $self->_run_createrepo();
}

sub type {
  my $self = shift;
  return 'Yum';
}

1;
