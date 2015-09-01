package App::Nrepo::Backend::Yum;

use Moo::Role;
use Carp;
use IO::Zlib;
use File::Path qw(make_path);
use File::Basename qw(basename);
use Params::Validate qw(:all);
use Data::Dumper qw(Dumper);
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

    # XXX Separate this
    # Parse the xml and retrieve the primary file location
    if ($type eq 'repomd') {
      my $twig = XML::Twig->new(TwigRoots => {data => 1});
      $twig->parsefile($dest_file);
      my $root = $twig->root;
      my @e = $root->children();
      for my $e (@e) {
        my $location;
        #my $checksum;
        #my $size;
        my $data_type = $e->att('type');
        #next unless $data_type eq 'primary';
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
        push @metadata_files, {'type' => $data_type, location => $location};
      }
      #$self->logger->log_and_croak(level => 'error', message => "repomd.xml not valid: $dest_file") unless $location;
    }

    # Parse the primary metadata file
    # XXX Add some exceptions
    if ($type eq 'primary') {
      my $contents = $self->get_gzip_contents($dest_file);
      $packages = $self->parse_primary($contents);
      for my $package (@{$packages}) {
        print "DEBUG: need to get package: " . $package->{'name'} . $/;
      }
    }
  }
  return $packages;
}
sub parse_primary {
  my $self = shift;
  my $xml  = shift;

  my $packages = [];
  my $twig = XML::Twig->new(TwigRoots => {package => 1});
  $twig->parse($xml);
  my $root = $twig->root;
  my @e = $root->children();
  for my $e (@e) {
    my $data = {};
    for my $c ($e->children()) {
      if ($c->name eq 'location') {
        $data->{'location'} = $c->att('href');
      }
      elsif ($c->name eq 'name') {
        $data->{'name'} = $c->text;
      }
      elsif ($c->name eq 'checksum') {
        $data->{'checksum'}->{'type'} = $c->att('type');
        $data->{'checksum'}->{'value'} = $c->text;
      }
      elsif ($c->name eq 'size'){
        $data->{'size'} = $c->att('package');
      }
    }
    push @{$packages}, $data;
  }
  return $packages;
}
sub parse_metadata {
  my $self = shift;
  print "DEBUG: parse_metadata from App::Nrepo::Backend::Yum\n";
}
sub get_packages {
  my $self = shift;
  my %o = validate(@_, {
    url      => { type => SCALAR },
    packages => { type => ARRAYREF },
  });

  print "DEBUG: get_packages from App::Nrepo::Backend::Yum\n";
  my $arch     = $self->arch();
  my $base_dir = File::Spec->catdir($self->dir(), $arch);

  for my $package (@{$o{'packages'}}) {
    #XXX
    my $name      = $package->{'name'};
    my $size      = $package->{'size'};
    my $location  = $package->{'location'};
    my $p_url     = join('/', ($o{'url'}, $arch, $location));
    my $dest_file = File::Spec->catfile($base_dir, $location);
    my $dest_dir  = basename($dest_file);
    # Setup the destination dir if needed
    unless (-d $dest_dir) {
      my $err;
      make_path($base_dir, $dest_dir, error => \$err);
      $self->logger->log_and_croak(level => 'error', message => "Failed to create path: ${dest_dir} with error: ${err}") if $err;
    }
    # Grab the file
    $self->download_binary_file(url => $p_url, dest => $dest_file);
  }
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
