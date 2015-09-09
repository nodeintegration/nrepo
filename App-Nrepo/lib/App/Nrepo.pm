package App::Nrepo;

use Moo;
use Carp;
use Cwd qw(getcwd);
use Data::Dumper;
use namespace::clean;
use Params::Validate qw(:all);
use Module::Pluggable::Object;
use File::Spec;

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
        $self->mirror(repo => $repo, checksums => $options->{'checksums'}, force => $options->{'force'});
      }
    }
    else {
      $self->mirror(repo => $options->{'repo'}, checksums => $options->{'checksums'}, force => $options->{'force'});
    }
  }
  elsif ($action eq 'clean') {
    if ($options->{'repo'} eq 'all') {
      for my $repo (keys %{$self->config->{'repo'}}) {
        $self->mirror(repo => $repo, force => $options->{'force'});
      }
    }
    else {
      $self->clean(repo => $options->{'repo'}, force => $options->{'force'});
    }
  }
  elsif ($action eq 'tag') {
    $self->tag(repo => $options->{'repo'}, dest_tag => $options->{'tag'}, softlink => $options->{'softlink'}, force => $options->{'force'});
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

  # If data_dir is relative, lets expand it based on cwd
  $self->config->{'data_dir'} = File::Spec->catdir(getcwd, $self->config->{data_dir});

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
    for my $param (qw/type local arch/) {
      $self->logger->log_and_croak(
        level   => 'error',
        message => sprintf "repo: %s missing param: %s", $repo, $param,
      ) unless $self->config->{repo}->{$repo}->{$param};
      # Data validation for specific type
      if ($param eq 'arch') {
        # We allow identical options which we use for arch, lets end up with an array regardless
        my $arch = $self->config->{'repo'}->{$repo}->{'arch'};
        my $arches = ref($arch) eq 'ARRAY' ? $arch : [$arch];
        $self->config->{'repo'}->{$repo}->{'arch'} = $arches;
      }
      elsif ($param eq 'type') {
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

sub _get_plugin {
  my $self    = shift;
  my %o = validate(@_, {
    type      => { type    => SCALAR, },
    options   => { options => HASHREF, },
  });

  my $plugin;
  for my $p (Module::Pluggable::Object->new(
    instantiate => 'new',
    search_path => ['App::Nrepo::Plugin'],
    except      => ['App::Nrepo::Plugin::Base'],
  )->plugins(%{$o{'options'}}) ) {
    $plugin = $p if $p->type() eq $o{'type'};
  }
  $self->logger->log_and_croak(level => 'error', message => "Failed to find a plugin for type: $o{'type'}") unless $plugin;
  return $plugin;
}

sub mirror {
  my $self = shift;
  my %o = validate(@_, {
    repo      => { type => SCALAR, },
    checksums => { type => BOOLEAN, optional => 1, },
    force     => { type => BOOLEAN, optional => 1, },
  });

  my $options = {
    logger    => $self->logger(),
    repo      => $o{'repo'},
    arches    => $self->config->{'repo'}->{$o{'repo'}}->{'arch'},
    url       => $self->config->{'repo'}->{$o{'repo'}}->{'url'},
    checksums => $o{'checksums'},
    backend   => $self->config->{'repo'}->{$o{'repo'}}->{'type'},
    dir       => $self->get_repo_dir(repo => $o{'repo'}),
    ssl_ca    => $self->config->{'repo'}->{$o{'repo'}}->{'ca'} || undef,
    ssl_cert  => $self->config->{'repo'}->{$o{'repo'}}->{'cert'} || undef,
    ssl_key   => $self->config->{'repo'}->{$o{'repo'}}->{'key'} || undef,
    force     => $o{'force'},
  };
  my $plugin = $self->_get_plugin(
    type    => $self->config->{'repo'}->{$o{'repo'}}->{'type'},
    options => $options
  );
  $plugin->mirror();
}

sub clean {
  my $self = shift;
  my %o = validate(@_, {
    repo      => { type => SCALAR, },
    force     => { type => BOOLEAN, optional => 1, },
  });

  my $options = {
    logger    => $self->logger(),
    repo      => $o{'repo'},
    arches    => $self->config->{'repo'}->{$o{'repo'}}->{'arch'},
    backend   => $self->config->{'repo'}->{$o{'repo'}}->{'type'},
    dir       => $self->get_repo_dir(repo => $o{'repo'}),
    force     => $o{'force'},
  };
  my $plugin = $self->_get_plugin(
    type    => $self->config->{'repo'}->{$o{'repo'}}->{'type'},
    options => $options,
  );

  $plugin->clean();
}

sub tag {
  my $self = shift;
  my %o = validate(@_, {
    repo      => { type => SCALAR, },
    src_tag   => { type => SCALAR, default => 'head' },
    dest_tag  => { type => SCALAR, },
    force     => { type => BOOLEAN, optional => 1, },
    softlink  => { type => BOOLEAN, optional => 1, },
  });

  my $options = {
    logger    => $self->logger(),
    repo      => $o{'repo'},
    arches    => $self->config->{'repo'}->{$o{'repo'}}->{'arch'},
    backend   => $self->config->{'repo'}->{$o{'repo'}}->{'type'},
    dir       => $self->get_repo_dir(repo => $o{'repo'}),
    force     => $o{'force'},
  };

  my $plugin = $self->_get_plugin(
    type    => $self->config->{'repo'}->{$o{'repo'}}->{'type'},
    options => $options,
  );

  $plugin->tag(
    src_dir  => $self->get_repo_dir(repo => $o{'repo'}, tag => $o{'src_tag'}),
    src_tag  => $o{'src_tag'},
    dest_dir => $self->get_repo_dir(repo => $o{'repo'}, tag => $o{'dest_tag'}),
    dest_tag => $o{'dest_tag'},
    softlink => $o{'softlink'},
  );
}


1;
__END__

# ABSTRACT: nrepo is a tool to manage linux repositories.

