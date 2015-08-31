package App::Nrepo;

use Moo;
use Carp;
use namespace::clean;
use Params::Validate qw(:all);
use Data::Dumper;
use File::Spec;
use App::Nrepo::Repo;

has config => ( is => 'ro' );
has logger => ( is => 'ro' );

sub go {
  my $self = shift;
  my $options = shift;

  $self->_validate_config();
  my $action = $options->{'action'};
  if ($action eq 'list' ) {
    $self->list();
  }
  elsif ($action eq 'mirror') {
    if ($options->{'repo'} eq 'all') {
      for my $repo (keys %{$self->config->{'repo'}}) {
        $self->mirror(repo => $repo, checksums => $options->{'checksums'}, );
      }
    }
    else {
      $self->mirror(repo => $options->{'repo'}, checksums => $options->{'checksums'}, );
    }
  }
  else {
    $self->logger->log_and_croak(
      'level'   => 'error',
      'message' => "ERROR: action: ${action} not implemented",
    );
  }
  exit(0);
}
sub _validate_config {
  my $self = shift;

  $self->logger->log_and_croak(
    level   => 'error',
    message => sprintf "datadir does not exist: %s", $self->config->{data_dir},
  ) unless -d $self->config->{data_dir};

  $self->logger->log_and_croak(
    level   => 'error',
    message => sprintf "Unknown tag_style %s, must be topdir or bottomdir\n", $self->config->{tag_style},
  ) unless $self->config->{tag_style} =~ m/^(?:top|bottom)dir$/;

  # required params for repos
  for my $repo (sort keys %{$self->config->{'repo'}}) {
    for my $param (qw/type local/) {
      $self->logger->log_and_croak(
        level   => 'error',
        message => sprintf "repo: %s missing param: %s", $repo, $param,
      ) unless $self->config->{repo}->{$repo}->{$param};
      # Data validation for specific type
      if ($param eq 'type') {
        unless (
          $self->config->{repo}->{$repo}->{$param} eq 'Yum' ||
          $self->config->{repo}->{$repo}->{$param} eq 'Apt' ||
          $self->config->{repo}->{$repo}->{$param} eq 'Plain',
        ) {
          $self->logger->log_and_croak(
            level   => 'error',
            message => sprintf "repo: %s param: %s value: %s is not supported", $repo, $param, $self->config->{repo}->{$repo}->{$param},
          );
        }
      }
    }
  }
}


sub get_repo_dir {
  my $self = shift;
  my %o = validate(@_, {
    repo => { type => SCALAR },
    tag =>  { type => SCALAR, default => 'head', },
  });

  my $data_dir  = $self->config->{data_dir};
  my $tag_style = $self->config->{tag_style};
  my $repo      = $o{'repo'};
  my $tag       = $o{'tag'};
  my $local     = $self->config->{'repo'}->{$repo}->{'local'};

  if ($tag_style eq 'topdir') {
    return File::Spec->catdir($data_dir, $tag, $local);
  }
  elsif ($tag_style eq 'bottomdir') {
    return File::Spec->catdir($data_dir, $local, $tag);
  }
  else {
    $self->logger->log_and_croak(level => 'error', message => 'get_repo_dir: Unknown tag_style: '.$tag_style);
  }
}

sub list {
  my $self = shift;
  print "Repository list:\n";
  print sprintf "|%8s|%8s|%50s|\n", 'Type', 'Mirrored', 'Name';
  for my $repo (sort keys %{$self->config->{repo}}) {
    my $type     = $self->config->{repo}->{$repo}->{type};
    my $mirrored = $self->config->{repo}->{$repo}->{url} ? 'Yes' : 'No';
    print sprintf "|%8s|%8s|%50s|\n", $type, $mirrored, $repo;
  }
}

sub mirror {
  my $self = shift;
  my %o = validate(@_, {
    repo      => { type => SCALAR, },
    checksums => { type => BOOLEAN, optional => 1, },
  });

  my $r = App::Nrepo::Repo->new(
    logger  => $self->logger(),
    repo    => $o{'repo'},
    arch    => $self->config->{'repo'}->{$o{'repo'}}->{'arch'},
    backend => $self->config->{'repo'}->{$o{'repo'}}->{'type'},
    dir     => $self->get_repo_dir(repo => $o{'repo'}),
  );

  $r->mirror(
    url        => $self->config->{'repo'}->{$o{'repo'}}->{'url'},
    checksums  => $o{'checksums'},
  );
}



1;
__END__

# ABSTRACT: nrepo is a tool to manage linux repositories.

