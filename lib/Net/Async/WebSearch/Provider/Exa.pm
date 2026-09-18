package Net::Async::WebSearch::Provider::Exa;
our $VERSION = '0.003';
# ABSTRACT: Exa neural search API provider
use strict;
use warnings;
use parent 'Net::Async::WebSearch::Provider';

use Carp qw( croak );
use Future;
use JSON::MaybeXS qw( encode_json decode_json JSON );
use HTTP::Request ();
use Net::Async::WebSearch::Result;

sub _init {
  my ( $self ) = @_;
  croak "Exa provider requires 'api_key'" unless $self->{api_key};
  $self->{endpoint} ||= 'https://api.exa.ai/search';
  $self->{name}     ||= 'exa';
}

sub endpoint { $_[0]->{endpoint} }
sub api_key  { $_[0]->{api_key} }

sub search {
  my ( $self, $http, $query, $opts ) = @_;
  $opts ||= {};
  my $limit = $opts->{limit} || 10;

  # Exa has no native language/region/safesearch parameters, so those opts are
  # silently ignored. Snippet text only comes back when `contents.text` is
  # requested — without it every hit has an empty snippet.
  my %body = (
    query      => $query,
    numResults => $limit,
    contents   => { text => JSON->true },
  );

  my $req = HTTP::Request->new(
    POST => $self->endpoint,
    [
      'x-api-key'    => $self->api_key,
      'Content-Type' => 'application/json',
      'Accept'       => 'application/json',
      'User-Agent'   => $self->user_agent_string,
    ],
    encode_json(\%body),
  );

  return $http->do_request( request => $req )->then(sub {
    my ( $resp ) = @_;
    unless ( $resp->is_success ) {
      return Future->fail(
        $self->name.": HTTP ".$resp->status_line, 'websearch', $self->name,
      );
    }
    my $data = eval { decode_json( $resp->decoded_content ) };
    if ( my $e = $@ ) {
      return Future->fail( $self->name.": invalid JSON: $e", 'websearch', $self->name );
    }
    my @out;
    my $rank = 0;
    for my $r ( @{ $data->{results} || [] } ) {
      $rank++;
      push @out, Net::Async::WebSearch::Result->new(
        url          => $r->{url},
        title        => $r->{title},
        snippet      => $r->{text},
        provider     => $self->name,
        rank         => $rank,
        published_at => $r->{publishedDate},
        raw          => $r,
        extra        => {
          ( defined $r->{author} ? ( author => $r->{author} ) : () ),
          ( defined $r->{id}     ? ( id     => $r->{id} )     : () ),
          ( defined $r->{score}  ? ( score  => $r->{score} )  : () ),
        },
      );
      last if $rank >= $limit;
    }
    return Future->done(\@out);
  });
}

1;

=head1 SYNOPSIS

  my $exa = Net::Async::WebSearch::Provider::Exa->new(
    api_key => $ENV{EXA_API_KEY},
  );

=head1 DESCRIPTION

Provider for L<https://exa.ai>, a neural (embeddings-based) search API. Parses
the C<results> array from the JSON response. Snippet text is requested via
C<contents.text> in the POST body — without it Exa returns hits carrying no
passage text at all.

=head1 API KEY

Sign up at L<https://dashboard.exa.ai>. The API key is issued in the account
dashboard and sent as the C<x-api-key> request header.

=attr api_key

Required. Sent as C<x-api-key>.

=attr endpoint

Override the endpoint URL. Default C<https://api.exa.ai/search>.

=method search

Honours C<limit> (C<numResults>, 1-100). Exa has no native C<language>,
C<region> or C<safesearch> parameters, so those options are silently ignored.
Always requests C<contents.text> so results carry a snippet.

=seealso

L<https://exa.ai/>

=cut
