#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use IO::Async::Loop;
use Future;

use Net::Async::WebSearch;
use Net::Async::WebSearch::Provider;
use Net::Async::WebSearch::Result;

{
  package Test::WS::Prov;
  use parent 'Net::Async::WebSearch::Provider';
  sub _init { $_[0]->{hang} ||= 0 }
  sub search {
    my ( $self ) = @_;
    return $self->{hang_future} = Future->new if $self->{hang};
    return Future->done([
      Net::Async::WebSearch::Result->new(
        url => 'https://example.com/ok', title => 'ok',
        provider => $self->name, rank => 1,
      ),
    ]);
  }
}

my $loop = IO::Async::Loop->new;
my $good = Test::WS::Prov->new( name => 'good' );
my $hang = Test::WS::Prov->new( name => 'hang', hang => 1 );
my $ws = Net::Async::WebSearch->new( providers => [ $good, $hang ] );
$loop->add($ws);

# Guard: a regression must fail the test, not hang it.
sub guarded {
  my ($f) = @_;
  my $g = $loop->delay_future( after => 5 )
    ->then(sub { Future->fail('test guard: search hung') });
  return Future->wait_any( $f, $g )->get;
}

my $out = guarded( $ws->search( query => 'q', provider_timeout => 0.2 ) );
is( scalar @{ $out->{results} }, 1, 'results of the healthy provider survive' );
is( scalar @{ $out->{errors} }, 1, 'stalled provider reported in errors' );
is( $out->{errors}[0]{provider}, 'hang', 'error names the stalled provider' );
like( $out->{errors}[0]{error}, qr/timeout/, 'error says timeout' );
is( $out->{stats}{providers_error}, 1, 'stats count the timeout' );
ok( $hang->{hang_future}->is_cancelled, 'stalled provider future was cancelled' );

# Constructor value applies; per-call 0 disables the limit again.
$ws->provider_timeout(0.2);
my $out2 = guarded( $ws->search( query => 'q' ) );
is( $out2->{errors}[0]{provider}, 'hang', 'constructor timeout applies' );

my $off = $ws->search( query => 'q', provider_timeout => 0, only => ['hang'] );
$loop->delay_future( after => 0.5 )->get;
ok( !$off->is_ready, 'provider_timeout => 0 disables the limit' );
$off->cancel;

# Stream mode shares the dispatch path.
my @e;
guarded( $ws->search_stream( query => 'q', on_result => sub {},
  on_provider_error => sub { push @e, $_[0] }, provider_timeout => 0.2 ) );
is_deeply( \@e, ['hang'], 'stream mode reports the timeout' );

done_testing;
