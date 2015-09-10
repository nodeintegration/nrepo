package App::Nrepo::Plugin::Yum;

use Moo;
use Carp;
use IO::Zlib;
use File::Find qw(find);
use File::Basename qw(dirname);
use Params::Validate qw(:all);
use Data::Dumper qw(Dumper);
use XML::Twig;

with 'App::Nrepo::Plugin::Base';

sub get_metadata {
  my $self = shift;
  my $arch = shift;

  my $base_dir = File::Spec->catdir($self->dir(), $arch);
  my $packages;

  my @metadata_files = ({type => 'repomd', location => 'repodata/repomd.xml'});
  for my $m (@metadata_files) {
    my $type      = $m->{'type'};
    my $location  = $m->{'location'};
    my $m_url     = join('/', ($self->url, $location));
    $m_url        =~ s/%ARCH%/$arch/;
    my $dest_file = File::Spec->catfile($base_dir, $location);
    my $dest_dir  = dirname($dest_file);

    # Make sure dir exists
    $self->make_dir($dest_dir);

    # Grab the file
    $self->download_binary_file(url => $m_url, dest => $dest_file);

    # Parse the xml and retrieve the primary file location
    if ($type eq 'repomd') {
      my $data = $self->parse_repomd($dest_file);
      push @metadata_files, @{$data};
    }

    # Parse the primary metadata file
    if ($type eq 'primary') {
      my $contents = $self->get_gzip_contents($dest_file);
      $packages = $self->parse_primary($contents);
    }
  }
  return $packages;
}

sub read_metadata {
  my $self = shift;
  my $arch = shift;

  my $base_dir = File::Spec->catdir($self->dir(), $arch);
  my $files = {};

  my @metadata_files = ({type => 'repomd', location => 'repodata/repomd.xml'});
  for my $m (@metadata_files) {
    my $type      = $m->{'type'};
    my $location  = $m->{'location'};
    my $dest_file = File::Spec->catfile($base_dir, $location);
    my $dest_dir  = dirname($dest_file);

    $files->{$location}++;

    if (-f $dest_file) {
      # Parse the xml and retrieve the primary file location
      if ($type eq 'repomd') {
        my $data = $self->parse_repomd($dest_file);
        push @metadata_files, @{$data};
      }

      # Parse the primary metadata file
      if ($type eq 'primary') {
        my $contents = $self->get_gzip_contents($dest_file);
        for my $file (@{$self->parse_primary($contents)}) {
          $files->{$file->{'location'}}++;
        }
      }
    }
  }
  return $files;
}

sub parse_repomd {
  my $self = shift;
  my $file = shift;

  my $twig = XML::Twig->new(TwigRoots => {data => 1});
  $twig->parsefile($file);

  my $root = $twig->root;
  my @e = $root->children();
  my @files;
  for my $e (@e) {
    my $data = {};
    $data->{'type'} = $e->att('type');
    for my $c ($e->children()) {
      if ($c->name eq 'location') {
        $data->{'location'} = $c->att('href');
      }
      elsif ($c->name eq 'checksum') {
        $data->{'checksum'} = $c->att('type');
      }
      elsif ($c->name eq 'size'){
        $data->{'size'} = $c->text;
      }
    }
    $self->logger->log_and_croak(level => 'error', message => "repomd xml not valid: $file") unless $data->{'location'};
    push @files, $data;
  }

  return \@files;
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
sub get_packages {
  my $self = shift;
  my %o = validate(@_, {
    arch     => { type => SCALAR },
    packages => { type => ARRAYREF },
  });

  my $arch     = $o{'arch'};
  my $base_dir = File::Spec->catdir($self->dir(), $arch);

  for my $package (@{$o{'packages'}}) {
    my $name     = $package->{'name'};
    my $size     = $package->{'size'};
    my $location = $package->{'location'};
    my $checksum = $package->{'checksum'};

    my $p_url     = join('/', ($self->url, $location));
    $p_url        =~ s/%ARCH%/$arch/;
    my $dest_file = File::Spec->catfile($base_dir, $location);
    my $dest_dir  = dirname($dest_file);

    # Make sure dir exists
    $self->make_dir($dest_dir);

    # Check if we have the local file
    my $download;
    if ($self->force) {
      $download++;
    }
    elsif ($self->checksums) {
      $download++ unless $self->validate_file(filename => $dest_file, check => $checksum->{'type'}, value => $checksum->{'value'});
    }
    else {
      $download++ unless $self->validate_file(filename => $dest_file, check => 'size', value => $size);
    }

    # Grab the file
    if ($download) {
      $self->logger->notice(sprintf('get_packages: repo: %s arch: %s package: %s', $self->repo(), $arch, $name));
      $self->download_binary_file(url => $p_url, dest => $dest_file);
    }
    else {
      $self->logger->debug(sprintf('get_packages: repo: %s arch: %s package: %s skipping as its deemed up to date', $self->repo(), $arch, $name));
    }
  }
}
sub clean_files {
  my $self = shift;
  my %o = validate(@_, {
    arch  => { type => SCALAR },
    files => { type => HASHREF },
  });

  my $arch     = $o{'arch'};
  my $base_dir = File::Spec->catdir($self->dir(), $arch);

  find(
    sub {
      if (
        $_ !~ /^[\.]+$/
      ) {
        my $file = $_;
        if (-f $file) {
          my $rel = File::Spec->abs2rel($File::Find::name, $base_dir);
          unless ($o{'files'}->{$rel}) {
            $self->logger->info("clean_files: removing non referenced file: ${File::Find::name}");
            unlink $file or $self->logger->log_and_croak(level => 'error', message => "Failed to remove file: ${file}: $!");
          }
        }
      }
    },
    $base_dir,
  );
}
sub add_files {
  my $self = shift;
}
sub remove_files {
  my $self = shift;
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
  #my $self = shift;
  return 'Yum';
}

1;
