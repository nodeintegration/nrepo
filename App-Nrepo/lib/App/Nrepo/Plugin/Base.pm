package App::Nrepo::Plugin::Base;

use Carp;
use Data::Dumper;
use Digest::SHA;
use File::Path qw(make_path remove_tree);
use LWP::UserAgent;
use Moo::Role;
use Module::Path qw[ module_path ];
use Module::Runtime qw[ compose_module_name ];
use namespace::clean;
use Params::Validate qw(:all);
use Time::HiRes qw(gettimeofday tv_interval);

has logger    => ( is => 'ro', required => 1 );
has repo      => ( is => 'ro', required => 1 );
has dir       => ( is => 'ro', required => 1 );
has url       => ( is => 'ro', optional => 1 );
has checksums => ( is => 'ro', optional => 1 );
has force     => ( is => 'ro', optional => 1 );
has arches    => ( is => 'ro', required => 1 );
has ua        => ( is => 'lazy' );
has ssl_ca    => ( is => 'ro', optional => 1 );
has ssl_cert  => ( is => 'ro', optional => 1 );
has ssl_key   => ( is => 'ro', optional => 1 );

sub _build_ua {
  my $self = shift;

  my %o;
  $o{ssl_opts}->{'SSL_ca_file'}   = $self->ssl_ca()   if $self->can('ssl_ca');
  $o{ssl_opts}->{'SSL_cert_file'} = $self->ssl_cert() if $self->can('ssl_cert');
  $o{ssl_opts}->{'SSL_key_file'}  = $self->ssl_key()  if $self->can('ssl_key');

  return LWP::UserAgent->new(%o);
}

sub get_gzip_contents {
  my $self = shift;
  my $file = shift;

  if (-f $file) {
    {
        my $fh = IO::Zlib->new($file, 'rb');

        #XXX for some reason this does not work
        #local $/ = undef;
        #my $contents = <$fh>;
        #return $contents;

        my @contents = <$fh>;
        $fh->close;
        return join('', @contents);
    }
  }
}

sub make_dir {
  my $self = shift;
  my $dir  = shift;
  if (! -d $dir) {
    my $err;
    my $dirs = make_path($dir, error => \$err);
    $self->logger->log_and_croak(level => 'error', message => "Failed to create path: ${dir} with error: ${err}") if $err;
    $self->logger->debug("Created path: ${dir}");
    return 1;
  }
  return 0;
}
sub remove_dir {
  my $self = shift;
  my $dir  = shift;
  if (-d $dir) {
    my $err;
    my $dirs = remove_tree($dir, error => \$err);
    $self->logger->log_and_croak(level => 'error', message => "Failed to create path: ${dir} with error: ${err}") if $err;
    $self->logger->debug("removed path: ${dir}");
    return 1;
  }
  return 0;
}

sub validate_file {
  my $self = shift;
  my %o = validate(@_, {
    filename => { type => SCALAR },
    check    => { type => SCALAR },
    value    => { type => SCALAR },
  });

  return 0 unless -f $o{'filename'};

  if ($o{'check'} eq 'size') {
    return $self->_validate_file_size($o{'filename'}, $o{'value'});
  }
  elsif ($o{'check'} eq 'sha256') {
    return $self->_validate_file_sha256($o{'filename'}, $o{'value'});
  }
}

sub _validate_file_size {
  my $self = shift;
  my $file = shift;
  my $size = shift;

  my @stats     = stat($file);
  my $file_size = $stats[7];

  return $file_size eq $size ? 1 : undef;
}

sub _validate_file_sha256 {
  my $self     = shift;
  my $file     = shift;
  my $checksum = shift;

  my $sha = Digest::SHA->new('sha256');
  $sha->addfile($file);
  return $sha->hexdigest eq $checksum ? 1 : undef;
}

sub mirror {
  my $self = shift;

  $self->logger->debug(sprintf("mirror: starting repo: %s from url: %s to dir: %s", $self->repo, $self->url, $self->dir));

  for my $arch (@{$self->arches()}) {
    my $packages = $self->get_metadata($arch);
    $self->get_packages(arch => $arch, packages => $packages);
  }

}
sub clean {
  my $self = shift;

  $self->logger->debug(sprintf("clean: starting repo: %s in dir: %s", $self->repo, $self->dir));
  for my $arch (@{$self->arches()}) {
    my $files = $self->read_metadata($arch);
    $self->clean_files(arch => $arch, files => $files);
  }

}

sub init {
  my $self = shift;
  #$plugin->init();
  print "Here\n";

}

sub tag {
  my $self = shift;
  my %o = validate(@_, {
    src_tag   => { type => SCALAR },
    src_dir   => { type => SCALAR },
    dest_tag  => { type => SCALAR },
    dest_dir  => { type => SCALAR },
    hard_link => { type => BOOLEAN, default => 1 },
  });

  $self->logger->debug(sprintf('tag: repo: %s tagging: %s -> %s', $self->repo(), $o{'src_dir'}, $o{'dest_dir'}));
  # When src_dir does not exist do not continue
  $self->logger->log_and_die(
    level   => 'error',
    message => sprintf("tag: repo: %s src_dir: %s does not exist", $self->repo(), $o{'src_dir'}),
  ) unless -d $o{'src_dir'};

  # When dest_dir exists and force is not set do not continue
  if ( -l $o{'dest_dir'} ) {
    if ($self->force() ) {
      unlink $o{'dest_dir'};
    }
    else {
      $self->logger->log_and_die(
        level   => 'error',
        message => sprintf("tag: repo: %s dest_dir: %s exists and force not enabled.", $self->repo(), $o{'dest_dir'}),
      );
    }
  }
  elsif ( -d $o{'dest_dir'} ) {
    if ($self->force() ) {
      $self->logger->log_and_die(
        level   => 'error',
        message => sprintf("tag: repo: %s dest_dir: %s exists and force not enabled.", $self->repo(), $o{'dest_dir'}),
      );
    }
    else {
      $self->remove_dir($o{'dest_dir'});
    }
  }

  if ($o{'hard_link'}) {
    $self->make_dir($o{'dest_dir'});
    $self->logger->log_and_die(
        level   => 'error',
        message => 'XXX TODO',
    );
    # Find files in the source dir
    # Build a list
    # link files from source_dir to dest_dir
  }
  else {
    symlink $o{'src_dir'}, $o{'dest_dir'} || $self->logger->log_and_die(
        level   => 'error',
        message => sprintf("tag: repo: %s couldnt link src_dir: %s to dst_dir: %s: $!", $self->repo(), $o{'src_dir'}, $o{'dest_dir'}),
    );
  }
}

sub download_binary_file {
  my $self = shift;
  my %o = validate(@_, {
    url         => { type => SCALAR },
    dest        => { type => SCALAR },
    retry_limit => { type => SCALAR, default => 3 },
  });

  $self->logger->debug("download_binary_file: $o{url} -> $o{dest}");

  my $retry_count = 0;
  my $retry_limit = $o{retry_limit};
  my $success;

  while (!$success && $retry_count <= $retry_limit) {
    my $t0 = [gettimeofday];
    my $res = $self->ua->get($o{'url'}, ':content_file' => $o{'dest'});
    my $elapsed = tv_interval($t0);

    $self->logger->debug("download_binary_file: $o{url} took: ${elapsed}");

    if ($res->is_success) {
      return 1;
    }
    else {
      $self->logger->debug("download_binary_file: $o{url} failed with status: " . $res->status_line);
      $retry_count++;
      if ($retry_count <= $retry_limit) {
        $self->logger->debug("download_binary_file: $o{url} retrying") if $retry_count;
      }
      else {
        $self->logger->error("download_binary_file: $o{url} failed and exhausted all retries.");
        return undef;
      }
    }
  }
}

1;
