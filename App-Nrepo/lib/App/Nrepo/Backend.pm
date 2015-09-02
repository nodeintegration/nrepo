package App::Nrepo::Backend;

use Carp;
use Data::Dumper;
use Digest::SHA;
use LWP::UserAgent;
use Moo::Role;
use Module::Path qw[ module_path ];
use Module::Runtime qw[ compose_module_name ];
use namespace::clean;
use Params::Validate qw(:all);
use Time::HiRes qw(gettimeofday tv_interval);
use XML::LibXML;

has logger    => ( is => 'ro', required => 1 );
has repo      => ( is => 'ro', required => 1 );
has dir       => ( is => 'ro', required => 1 );
has url       => ( is => 'ro', optional => 1 );
has checksums => ( is => 'ro', optional => 1 );
has force     => ( is => 'ro', optional => 1 );
has arch      => ( is => 'ro', required => 1 );
has ua        => ( is => 'lazy' );
has _backend  => (
    is        => 'rwp',
    predicate => 1,
    init_arg  => 'backend',
    trigger   => sub { $_[0]->_backend_compose($_[1]) },
);

sub backend {
  $_[0]->_set__backend( $_[1] ) if defined $_[1] && ! $_[0]->_has_backend;
}

# generic dynamic backend composition
sub _backend_compose {
    my ( $self, $req ) = @_;
    my $module = compose_module_name( 'App::Nrepo::Backend', $req );
    croak( "unknown backend ($module)\n" ) unless defined module_path( $module );
    Moo::Role->apply_roles_to_object( $self, $module );
    return;
}

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

  my $packages = $self->get_metadata();
  $self->get_packages(packages => $packages);

}

#XXX TODO
sub init {
  my $self = shift;
  #$plugin->init();
  print "Here\n";

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
