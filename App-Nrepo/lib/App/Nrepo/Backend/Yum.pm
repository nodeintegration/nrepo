package App::Nrepo::Backend::Yum;

use Moo::Role;
use Carp;
use IO::Zlib;
use File::Path qw(make_path);
use File::Basename qw(basename);
use Params::Validate qw(:all);
use Data::Dumper qw(Dumper);
#use XML::Simple qw(XMLin);
use XML::Twig;

#with('App::Nrepo::Backend');

sub get_metadata {
  my $self = shift;
  my %o = validate(@_, {
    url => { type => SCALAR },
  });

  print "DEBUG: get_metadata from App::Nrepo::Backend::Yum\n";
  my $arch     = $self->arch();
  my $base_dir = File::Spec->catdir($self->dir(), $arch);

  my $packages;

  my @metadata_files = ({type => 'repomd', location => 'repodata/repomd.xml'});
  for my $m (@metadata_files) {
    my $type      = $m->{'type'};
    my $location  = $m->{'location'};
    my $m_url     = join('/', ($o{url}, $arch, $location));
    my $dest_file = File::Spec->catfile($base_dir, $location);
    my $dest_dir  = basename($dest_file);
    # Setup the destination dir if needed
    unless (-d $dest_dir) {
      my $err;
      make_path($base_dir, $dest_dir, error => \$err);
      $self->logger->log_and_croak(level => 'error', message => "Failed to create path: ${dest_dir} with error: ${err}") if $err;
    }

    # Grab the file
    $self->download_binary_file(url => $m_url, dest => $dest_file);

    # Parse the xml and retrieve the primary file location
    if ($type eq 'repomd') {
      my $twig = XML::Twig->new(TwigRoots => {data => 1});
      $twig->parsefile($dest_file);
      my $root = $twig->root;
      my @e = $root->children();
      my $location;
      #my $checksum;
      #my $size;
      for my $e (@e) {
        my $data_type = $e->att('type');
        next unless $data_type eq 'primary';
        for my $c ($e->children()) {
          if ($c->name eq 'location') {
            $location = $c->att('href');
          }
          #elsif ($c->name eq 'checksum') {
          #  $checksum = $c->att('type');
          #}
          #elsif ($c->name eq 'size'){
          #  $size = $c->text;
          #}
        }
        last;
      }
      $self->logger->log_and_croak(level => 'error', message => "repomd.xml not valid: $dest_file") unless $location;
      push @metadata_files, {'type' => 'primary', location => $location};
    }

    # Parse the primary metadata file
    # XXX Add some exceptions
    if ($type eq 'primary') {
      print "DEBUG: HERE!!!\n";
      my $contents = $self->parse_xml_gzip_file($dest_file);
      print Dumper $contents;
      #$packages = $self->parse_primary(xml => XMLin($dest_file, ForceArray => 1));
      #$packages = $self->parse_primary(xml => $self->parse_xml($contents));
    }
  }
}
sub parse_primary {
  my $self = shift;
  my %o = validate(@_, {
    xml => { type => HASHREF },
  });
  print Dumper $o{'xml'};
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
