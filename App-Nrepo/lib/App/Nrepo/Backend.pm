package App::Nrepo::Backend;

use Carp;
use Data::Dumper;
use LWP::UserAgent;
use Moo::Role;
use Module::Path qw[ module_path ];
use Module::Runtime qw[ compose_module_name ];
use namespace::clean;
use Params::Validate qw(:all);
use Time::HiRes qw(gettimeofday tv_interval);

has logger   => ( is => 'ro', required => 1 );
has repo     => ( is => 'ro', required => 1 );
has dir      => ( is => 'ro', required => 1 );
has arch     => ( is => 'ro', required => 1 );
has ua       => ( is => 'lazy' );
has _backend => (
    is        => 'rwp',
    predicate => 1,
    init_arg  => 'backend',
    trigger   => sub { $_[0]->_backend_compose($_[1]) },
);

# generic dynamic backend composition
sub _backend_compose {
    my ( $self, $req ) = @_;
    my $module = compose_module_name( "App::Nrepo::Backend", $req );
    croak( "unknown backend ($module)\n" )
      unless defined module_path( $module );
    Moo::Role->apply_roles_to_object( $self, $module );
    return;
}

sub backend {
  $_[0]->_set__backend( $_[1] ) if defined $_[1] && ! $_[0]->_has_backend
}

sub _build_ua {
  my $self = shift;

  my %o;
  $o{ssl_opts}->{'SSL_ca_file'}   = $self->ssl_ca()   if $self->can('ssl_ca');
  $o{ssl_opts}->{'SSL_cert_file'} = $self->ssl_cert() if $self->can('ssl_cert');
  $o{ssl_opts}->{'SSL_key_file'}  = $self->ssl_key()  if $self->can('ssl_key');
  return LWP::UserAgent->new(%o);
}

sub mirror {
  my $self = shift;
  my %o = validate(@_, {
    url       => { type => SCALAR },
    checksums => { type => BOOLEAN, optional => 1, },
  });

  print "DEBUG: url: $o{url} dir: " . $self->dir() . "\n";
  $self->get_metadata(url => $o{url});
  $self->get_packages(url => $o{url});

}
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
    #cert        => { type => SCALAR, optional => 1 }, #XXX TODO
    #ca          => { type => SCALAR, optional => 1 }, #XXX TODO
    #key         => { type => SCALAR, optional => 1 }, #XXX TODO
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
sub get_packages {
  print "DEBUG: get_packages from App::Nrepo::Repo\n";
}

1;
