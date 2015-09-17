#!/bin/false
package App::Nrepo;

use Moo;
use strictures 2;
use namespace::clean;
use Carp;
use Cwd qw(getcwd);
use Data::Dumper;
use Params::Validate qw(:all);
use Module::Pluggable::Object;
use File::Spec;
use App::Nrepo::Logger;



# VERSION


has config => ( is => 'ro' );
has logger => ( is => 'ro', default => sub {App::Nrepo::Logger->new()} );

=head1 DESCRIPTION

App::Nrepo - An application to handle management of various software repositories
This module is purely to designed to be used with the accompanying script bin/nrepo
Please look at its pod for instantiating of this Module

=head2 SYNOPSIS

  my $o = App::Nrepo->new(
    config => $hashref,
    logger => Log::Dispatch->new()
  );

  $o->go($action, %options);

=head2 METHODS

=over 4

=cut

=item B<go()>

Perform the supplied action with options

Valid actions:

=over 4

=item B<add-file>

Used to add file/s to a local repository see  L</"add_file()">

=item B<del-file>

Used to delete file/s from a local repository see L</"del_file()">

=item B<clean>

Used to clean a repository of no longer referenced files eg: no longer reference package versions or manifest files see L</"clean()"> 

=item B<init>

Used to initialise manifests for a local repository see L<"init()">

=item B<list>

Used to list configured repositories see L<"list()">

=item B<mirror>

Used to update a repository from its configured mirror see L<"mirror()">

=item B<tag>

Tag a repository state see L<"tag()">

=back

=cut

sub go {
  my ($self, $action, @args) = @_;
  $self->_validate_config();

  my $dispatch = {
    'add-file' => \&add_file,
    'del-file' => \&del_file,
    'clean'    => \&clean,
    'init'     => \&init,
    'list'     => \&list,
    'mirror'   => \&mirror,
    'tag'      => \&tag,
  };

  exists $dispatch->{$action} ||
    $self->logger->log_and_croak(level => 'error', message => "ERROR: ${action} not supported.");

  $dispatch->{$action}->($self, @args);

  exit(0);
}

sub _validate_config {
  my $self = shift;

  # If data_dir is relative, lets expand it based on cwd
  $self->config->{'data_dir'} = File::Spec->rel2abs($self->config->{data_dir});

  # Make sure data_dir exists
  $self->logger->log_and_croak(
    level   => 'error',
    message => sprintf "datadir does not exist: %s", $self->config->{data_dir},
  ) unless -d $self->config->{data_dir};

  # Ensure tag style option is valid
  $self->logger->log_and_croak(
    level   => 'error',
    message => sprintf "Unknown tag_style %s, must be topdir or bottomdir\n", $self->config->{tag_style},
  ) unless $self->config->{tag_style} =~ m/^(?:top|bottom)dir$/;

  # required params for each repo config
  for my $repo (sort keys %{$self->config->{'repo'}}) {

    #type local and arch are required params for ALL repos
    for my $param (qw/type local arch/) {
      $self->logger->log_and_croak(
        level   => 'error',
        message => sprintf "repo: %s missing param: %s", $repo, $param,
      ) unless $self->config->{repo}->{$repo}->{$param};

      # Data validation for specific types

      # Unfortunately Config::General does not allow us to make sure an option is always an array, so force it to an array
      if ($param eq 'arch') {
        # We allow identical options which we use for arch, lets end up with an array regardless
        my $arch = $self->config->{'repo'}->{$repo}->{'arch'};
        my $arches = ref($arch) eq 'ARRAY' ? $arch : [$arch];
        $self->config->{'repo'}->{$repo}->{'arch'} = $arches;
      }

      # Allowed types
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

sub _get_repo_dir {
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
    $self->logger->log_and_croak(level => 'error', message => '_get_repo_dir: Unknown tag_style: '.$tag_style);
  }
}

=item B<add_file()>

Action: add-file

Description: Adds a file to a local repository and updates the related metadata

Options:

=over 4

=item repo

The name of the repository as reflected in the config

=item arch

The arch this package should be added to as reflected in the config

=item file

The path of the file to be added to the repository

=item force

Boolean to enable force overwriting an existing file in the repository

=back

=cut

sub add_file {
  my $self = shift;
  my %o = validate(
    @_,
    {
      'repo'      => { type => SCALAR },
      'arch'      => { type => SCALAR },
      'file'      => { type => SCALAR | ARRAYREF },
      'force'     => { type => BOOLEAN, default => 0 },
    },
  );
  my $options = {
    repo      => $o{'repo'},
    arches    => $self->config->{'repo'}->{$o{'repo'}}->{'arch'},
    backend   => $self->config->{'repo'}->{$o{'repo'}}->{'type'},
    dir       => $self->_get_repo_dir(repo => $o{'repo'}),
    force     => $o{'force'},
  };
  my $plugin = $self->_get_plugin(
    type    => $self->config->{'repo'}->{$o{'repo'}}->{'type'},
    options => $options,
  );

  $plugin->add_file($o{'arch'}, $o{'file'});
}

=item B<del_file()>

Action: del-file

Description: Removes a file to a local repository and updates the related metadata

Options:

=over 4

=item repo

The name of the repository as reflected in the config

=item arch

The arch this package should be removed from as reflected in the config

=item file

The filename to be removed to the repository

=back

=cut

sub del_file {
  my $self = shift;
  my %o = validate(
    @_,
    {
      'repo'      => { type => SCALAR },
      'arch'      => { type => SCALAR },
      'file'      => { type => SCALAR | ARRAYREF },
    },
  );
  my $options = {
    repo      => $o{'repo'},
    arches    => $self->config->{'repo'}->{$o{'repo'}}->{'arch'},
    backend   => $self->config->{'repo'}->{$o{'repo'}}->{'type'},
    dir       => $self->_get_repo_dir(repo => $o{'repo'}),
    force     => $o{'force'},
  };
  my $plugin = $self->_get_plugin(
    type    => $self->config->{'repo'}->{$o{'repo'}}->{'type'},
    options => $options,
  );

  $plugin->del_file($o{'arch'}, $o{'file'});
}

=item B<clean()>

Action: clean

Description: Removes files from a repository that are not referenced in the metadata

Options:

=over 4

=item repo

The name of the repository as reflected in the config
If 'all' is supplied it will perform this action on all repositories in config

=item regex

If this boolean is enabled then use the repo parameter as a regex to match repositories against

=back

=cut

sub clean {
  my $self = shift;
  my %o = validate(@_, {
    repo  => { type => SCALAR, },
    arch  => { type => SCALAR, optional => 1 },
    regex => { type => BOOLEAN, optional => 1 },
    force => { type => BOOLEAN, optional => 1, },
  });

  if ($o{'repo'} eq 'all') {
    my %options = %o;
    for my $repo (keys %{$self->config->{'repo'}}) {
      $options{'repo'} = $repo;
      $self->_clean(%options);
    }
  }
  elsif ($o{'regex'}) {
    my %options = %o;
    for my $repo (keys %{$self->config->{'repo'}}) {
      if ($repo =~ m#$o{'repo'}#) {
        $options{'repo'} = $repo;
        $self->_clean(%options);
      }
    }
  }
  else {
    $self->_clean(%o);
  }
}

sub _clean {
  my ($self, %o) = @_;

  my $options = {
    repo      => $o{'repo'},
    arches    => $self->config->{'repo'}->{$o{'repo'}}->{'arch'},
    backend   => $self->config->{'repo'}->{$o{'repo'}}->{'type'},
    dir       => $self->_get_repo_dir(repo => $o{'repo'}),
    force     => $o{'force'},
  };
  my $plugin = $self->_get_plugin(
    type    => $self->config->{'repo'}->{$o{'repo'}}->{'type'},
    options => $options,
  );

  $plugin->clean();
}

=item B<init()>

Action: init

Description: Initialises a custom repository by generating the appropriate metadata files

Options:

=over 4

=item repo

The name of the repository as reflected in the config

=item arch

Rather than initialising all arches configured, just do this one

=back

=cut

sub init {
  my $self = shift;
  my %o = validate(@_, {
    repo => { type => SCALAR, },
    arch => { type => SCALAR, optional => 1 },
  });

  my $repo_config = $self->config->{'repo'}->{$o{'repo'}};

  # Initialising a mirrored repo will result in different manifests to what the mirror has
  if ($repo_config->{'url'}) {
    $self->logger->log_and_croak(
      level => 'error',
      message => 'init: this is action is only valid for local repositories...this repo has a url specified',
    );
  }

  my $options = {
    repo      => $o{'repo'},
    arches    => $repo_config->{'arch'},
    backend   => $repo_config->{'type'},
    dir       => $self->_get_repo_dir(repo => $o{'repo'}),
  };

  my $plugin = $self->_get_plugin(
    type    => $repo_config->{'type'},
    options => $options,
  );

  $plugin->init($o{'arch'});
}

=item B<list()>

Action: list

Description: Lists the repositories as reflected in the config

=cut

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

=item B<mirror()>

Action: mirror

Description: Mirrors repository from upstream provider into the head tag

Options:

=over 4

=item repo

The name of the repository as reflected in the config
If 'all' is supplied it will perform this action on all repositories in config

=item checksums

By default we just use the manifests information about size of packages to determine if the local file
is valid. If you want to have checksums used enable this boolean flag.
With this enabled updating a mirror can take quite a long time

=item regex

If this boolean is enabled then use the repo parameter as a regex to match repositories against

=back

=cut

sub mirror {
  my $self = shift;
  my %o = validate(@_, {
    'repo'      => { type => SCALAR },
    'force'     => { type => BOOLEAN, default => 0 },
    'arch'      => { type => SCALAR, optional => 1 },
    'checksums' => { type => SCALAR, optional => 1 },
    'regex'     => { type => BOOLEAN, optional => 1 },
  });

  if ($o{'repo'} eq 'all') {
    my %options = %o;
    for my $repo (keys %{$self->config->{'repo'}}) {
      $options{'repo'} = $repo;
      $self->_mirror(%options);
    }
  }
  elsif ($o{'regex'}) {
    my %options = %o;
    for my $repo (keys %{$self->config->{'repo'}}) {
      if ($repo =~ m#$o{'repo'}#) {
        $options{'repo'} = $repo;
        $self->_mirror(%options);
      }
    }
  }
  else {
    $self->_mirror(%o);
  }
}

sub _mirror {
  my ($self, %o) = @_;

  my $options = {
    repo      => $o{'repo'},
    arches    => $self->config->{'repo'}->{$o{'repo'}}->{'arch'},
    url       => $self->config->{'repo'}->{$o{'repo'}}->{'url'},
    checksums => $o{'checksums'},
    backend   => $self->config->{'repo'}->{$o{'repo'}}->{'type'},
    dir       => $self->_get_repo_dir(repo => $o{'repo'}),
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

=item B<tag()>

Action: tag

Description: Tags a repository at a particular state

Options:

=over 4

=item repo

The name of the repository as reflected in the config

=item src-tag

The source tag to use for this operation, by default this is 'head'
The source tag must pre exist.

=item dest-tag

The destination tag to use for this operation.

=item symlink

This will make the link operation use a symlink instead of hardlinking
For example you may tag every time you update from upstream but you move a production tag around...provides easy roll back
for your clients package configuration

=item force

Force will overwrite a pre existing dest-tag location

=back

=cut

sub tag {
  my $self = shift;
  my %o = validate(
    @_,
    {
      'repo'    => { type => SCALAR },
      'tag'     => { type => SCALAR },
      'src-tag' => { type => SCALAR,  default => 'head' },
      'symlink' => { type => BOOLEAN, default => 0 },
      'force'   => { type => BOOLEAN, default => 0 },
    },
  );

  my $options = {
    repo      => $o{'repo'},
    arches    => $self->config->{'repo'}->{$o{'repo'}}->{'arch'},
    backend   => $self->config->{'repo'}->{$o{'repo'}}->{'type'},
    dir       => $self->_get_repo_dir(repo => $o{'repo'}),
    force     => $o{'force'},
  };

  my $plugin = $self->_get_plugin(
    type    => $self->config->{'repo'}->{$o{'repo'}}->{'type'},
    options => $options,
  );

  $plugin->tag(
    src_dir        => $self->_get_repo_dir(repo => $o{'repo'}, tag => $o{'src-tag'}),
    src_tag        => $o{'src-tag'},
    dest_dir       => $self->_get_repo_dir(repo => $o{'repo'}, tag => $o{'tag'}),
    dest_tag       => $o{'tag'},
    symlink        => $o{'symlink'},
    hard_tag_regex => $self->config->{'repo'}->{'hard_tag_regex'} || $self->config->{'hard_tag_regex'},
  );
}

1;

=back

=cut

__END__

# ABSTRACT: nrepo is a tool to manage linux repositories.

