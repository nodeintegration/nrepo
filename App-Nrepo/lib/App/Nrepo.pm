package App::Nrepo;

use strict;
use warnings FATAL => 'all';
use Moo;
use Carp;
use namespace::clean;
use Params::Validate qw(:all);
use Data::Dumper;

has config => ( is => 'ro' );
has logger => ( is => 'ro' );

sub go {
  my $self = shift;
  my $options = shift;

  $self->_validate_config();
  #$self->_validate_options($options);
  #if ($options->{'list'}) {


}
sub _validate_config {
  my $self = shift;

  $self->logger->log_and_croak(
    level   => 'error',
    message => sprintf "DataDir does not exist: %s", $self->config->{DataDir},
  ) unless -d $self->config->{DataDir};

  $self->logger->log_and_croak(
    level   => 'error',
    message => sprintf "Unknown TagStyle %s, must be TopDir or BottomDir\n", $self->config->{TagStyle},
  ) unless $self->config->{TagStyle} =~ m/^(?:Top|Bottom)Dir$/;
}

1;
__END__

# ABSTRACT: nrepo is a tool to manage linux repositories.

