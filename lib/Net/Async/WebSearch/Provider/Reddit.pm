package Net::Async::WebSearch::Provider::Reddit;
our $VERSION = '0.002';
# ABSTRACT: Reddit search provider (keyless JSON endpoint)
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
  $self->{endpoint}  ||= 'https://www.reddit.com';
  $self->{endpoint}    =~ s{/+$}{};
  $self->{name}      ||= 'reddit';
  $self->{subreddit} //= undef;
  $self->{sort}      ||= 'relevance';  # relevance | hot | top | new | comments
  $self->{time}      ||= 'all';        # hour | day | week | month | year | all
  $self->{link_base} ||= 'https://www.reddit.com';
}

sub endpoint  { $_[0]->{endpoint} }
sub subreddit { @_ > 1 ? ($_[0]->{subreddit} = $_[1]) : $_[0]->{subreddit} }
sub sort      { @_ > 1 ? ($_[0]->{sort}      = $_[1]) : $_[0]->{sort} }
sub time      { @_ > 1 ? ($_[0]->{time}      = $_[1]) : $_[0]->{time} }
sub link_base { $_[0]->{link_base} }

sub search {
  my ( $self, $http, $query, $opts ) = @_;
  $opts ||= {};
  my $limit = $opts->{limit} || 10;

  my $sub = defined $opts->{subreddit} ? $opts->{subreddit} : $self->subreddit;
  my $path = defined $sub && length $sub ? "/r/$sub/search.json" : "/search.json";

  my $uri = URI->new( $self->endpoint . $path );
  my %q = (
    q     => $query,
    limit => $limit,
    sort  => $opts->{sort} // $self->sort,
    t     => $opts->{time} // $self->time,
  );
  $q{restrict_sr}  = 1 if defined $sub && length $sub;
  $q{include_over_18} = $opts->{include_nsfw} ? 'on' : 'off';
  $uri->query_form(%q);

  my $req = GET( $uri->as_string );
  # Reddit is picky — generic UAs get rate-limited hard.
  $req->header( 'User-Agent' => $self->user_agent_string );
  $req->header( 'Accept'     => 'application/json' );

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
    return Future->done( $self->_parse_listing($data, $limit) );
  });
}

sub _parse_listing {
  my ( $self, $data, $limit ) = @_;
  my @out;
  my $rank = 0;
  for my $child ( @{ ($data->{data} || {})->{children} || [] } ) {
    my $d = $child->{data} or next;
    $rank++;
    my $permalink = $self->link_base . ( $d->{permalink} // '' );
    my $target    = $d->{url} // $permalink;
    my $iso;
    if ( defined $d->{created_utc} ) {
      my @t = gmtime( $d->{created_utc} );
      $iso = sprintf '%04d-%02d-%02dT%02d:%02d:%02dZ',
        $t[5]+1900, $t[4]+1, $t[3], $t[2], $t[1], $t[0];
    }
    push @out, Net::Async::WebSearch::Result->new(
      url          => $target,
      title        => $d->{title},
      snippet      => ( $d->{selftext} && length $d->{selftext}
                          ? substr( $d->{selftext}, 0, 400 )
                          : undef ),
      provider     => $self->name,
      rank         => $rank,
      published_at => $iso,
      nsfw         => ( $d->{over_18} ? 1 : 0 ),
      domain       => $d->{domain},
      raw          => $d,
      extra        => {
        permalink    => $permalink,
        subreddit    => $d->{subreddit},
        author       => $d->{author},
        reddit_score => $d->{score},
        num_comments => $d->{num_comments},
        ( defined $d->{created_utc} ? ( created_utc => $d->{created_utc} ) : () ),
      },
    );
    last if $rank >= $limit;
  }
  return \@out;
}

1;

=head1 SYNOPSIS

  my $r = Net::Async::WebSearch::Provider::Reddit->new;
  # or subreddit-scoped by default:
  my $r = Net::Async::WebSearch::Provider::Reddit->new(
    subreddit => 'perl',
    sort      => 'top',
    time      => 'year',
  );

=head1 DESCRIPTION

Keyless provider backed by Reddit's public JSON search endpoint
(C</search.json>, or C</r/SUB/search.json> when a subreddit is scoped).
Reddit requires a distinct User-Agent string; requests made with generic
UAs are rate-limited aggressively.

The returned C<url> is the post's target link (external URL on link posts,
permalink on self/text posts). The permalink is always available under
C<< $result->extra->{permalink} >>.

=attr endpoint

Base URL. Default C<https://www.reddit.com>. Switch to C<https://old.reddit.com>
or a private mirror (Teddit, Libreddit, etc.) if desired.

=attr subreddit

Default subreddit scope. Per-call C<subreddit> in C<%opts> overrides.
Leave undef for site-wide search.

=attr sort

Default ordering: C<relevance> (default), C<hot>, C<top>, C<new>, C<comments>.

=attr time

Default time window: C<all> (default), C<hour>, C<day>, C<week>, C<month>, C<year>.

=attr link_base

Base URL used to build absolute permalinks out of Reddit's relative paths.
Default C<https://www.reddit.com>.

=method search

Honours C<limit>, plus Reddit-specific C<subreddit>, C<sort>, C<time>,
C<include_nsfw>.

=seealso

L<https://www.reddit.com/dev/api/>, L<Net::Async::WebSearch>

=cut
