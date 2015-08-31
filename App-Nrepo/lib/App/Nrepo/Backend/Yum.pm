package App::Nrepo::Backend::Yum;

use Moo::Role;
use Carp;
use File::Path qw(make_path);
use Params::Validate qw(:all);
use Data::Dumper qw(Dumper);
use XML::Simple qw(XMLin);

#with('App::Nrepo::Backend');

sub get_metadata {
  my $self = shift;
  my %o = validate(@_, {
    url => { type => SCALAR },
  });

  print "DEBUG: get_metadata from App::Nrepo::Backend::Yum\n";
  my $metadata_dir = 'repodata';
  my $file_dir = File::Spec->catdir($self->dir(), $metadata_dir);
  my @metadata_files = qw(repomd.xml);
  for my $file (@metadata_files) {
    my $file_url = $o{url} . '/'. $file;
    unless (-d $file_dir) {
      my $err;
      make_path($file_dir, error => \$err);
      $self->logger->log_and_croak(level => 'error', message => "Failed to create path: ${file_dir} with error: ${err}") if $err;
    }
    my $dest_file = File::Spec->catfile($file_dir, $file);
    $self->download_binary_file(url => $file_url, dest => $dest_file);

    if ($file eq 'repomd.xml') {
      my $xml = XMLin($file, ForceArray => 1);
      print Dumper $xml;
    }
  }

}
sub parse_metadata {
  my $self = shift;
  print "DEBUG: parse_metadata from App::Nrepo::Backend::Yum\n";
}
sub get_packages {
  my $self = shift;
  print "DEBUG: get_packages from App::Nrepo::Backend::Yum\n";
}
sub add_files {
  my $self = shift;
  print "DEBUG: add_files from App::Nrepo::Backend::Yum\n";
}
sub remove_files {
  my $self = shift;
  print "DEBUG: remove_files from App::Nrepo::Backend::Yum\n";
}
sub init {
  my $self = shift;
  print "DEBUG: init from App::Nrepo::Backend::Yum\n";
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
