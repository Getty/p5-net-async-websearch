package Net::Async::WebSearch::Provider::Marginalia;
our $VERSION = '0.003';
# ABSTRACT: Marginalia Search API provider
use strict;
use warnings;
use parent 'Net::Async::WebSearch::Provider';

use Future;
use JSON::MaybeXS qw( decode_json );
use URI;
use HTTP::Request::Common qw( GET );
use Net::Async::WebSearch::Result;

sub _init {
  my ( $self ) = @_;
  # Marginalia ships a public test key, so — unlike the paid providers — an
  # api_key is not required; fall back to it when none was supplied.
  $self->{api_key} = 'public' unless defined $self->{api_key};
  $self->{endpoint} ||= 'https://api2.marginalia-search.com/search';
  $self->{name}     ||= 'marginalia';
}

sub endpoint { $_[0]->{endpoint} }
sub api_key  { $_[0]->{api_key} }

sub search {
  my ( $self, $http, $query, $opts ) = @_;
  $opts ||= {};
  my $limit = $opts->{limit} || 10;

  my $uri = URI->new( $self->endpoint );
  my %q = ( query => $query, count => $limit );
  # Marginalia has no language/region knobs — those opts are silently ignored.
  # safesearch maps to the nsfw filter: safesearch on → nsfw suppressed (0),
  # safesearch off → nsfw allowed (1).
  $q{nsfw} = $opts->{safesearch} ? 0 : 1 if defined $opts->{safesearch};
  $uri->query_form(%q);

  my $req = GET( $uri->as_string );
  $req->header( 'User-Agent' => $self->user_agent_string );
  $req->header( 'Accept'     => 'application/json' );
  $req->header( 'API-Key'    => $self->api_key );

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
    # The corpus license (CC-BY-NC-SA) is a top-level field; record it per hit.
    my $license = $data->{license};
    my @out;
    my $rank = 0;
    for my $r ( @{ $data->{results} || [] } ) {
      $rank++;
      push @out, Net::Async::WebSearch::Result->new(
        url      => $r->{url},
        title    => $r->{title},
        snippet  => $r->{description},
        provider => $self->name,
        rank     => $rank,
        raw      => $r,
        extra    => {
          ( defined $license ? ( license => $license ) : () ),
        },
      );
      last if $rank >= $limit;
    }
    return Future->done(\@out);
  });
}

1;

=head1 SYNOPSIS

  my $marginalia = Net::Async::WebSearch::Provider::Marginalia->new;

  # or with your own key
  my $marginalia = Net::Async::WebSearch::Provider::Marginalia->new(
    api_key => $ENV{MARGINALIA_API_KEY},
  );

=head1 DESCRIPTION

Provider for L<https://marginalia-search.com>, an independent small-web search
index that favours text-heavy, non-commercial pages. Sends a C<GET> to the
public JSON API and parses the C<results> array from the response.

=head1 API KEY

Marginalia exposes a shared B<public> key (C<"public">) that works without
signup, so this provider needs no configuration — it defaults C<api_key> to
C<"public"> and fits alongside the other keyless free providers. A private key
(requested from the operator) raises the rate limit; pass it as C<api_key> and
it is sent unchanged.

=attr api_key

Optional. Sent as the C<API-Key> header. Defaults to the public shared key
C<"public">.

=attr endpoint

Override the endpoint URL. Default C<https://api2.marginalia-search.com/search>.

=method search

Honours C<limit> (C<count>) and C<safesearch> (mapped to the C<nsfw> filter).
Marginalia has no language/region controls, so C<language>/C<region> are
silently ignored.

=seealso

L<https://marginalia-search.com/>

=cut
