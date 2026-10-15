#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use IO::Async::Loop;
use IO::Async::Listener;
use IO::Async::Stream;
use Future;

use Net::Async::WebSearch;
use Net::Async::WebSearch::Result;

# Loopback server (no external network) that answers every request with an
# endless body. Without an abort on the client side the fetch never ends.
my $loop = IO::Async::Loop->new;
my $sent = 0;
my $closed;
my $listener = IO::Async::Listener->new(
  on_stream => sub {
    my ( undef, $stream ) = @_;
    $stream->configure(
      on_read => sub {
        my ( $s, $buf ) = @_;
        return 0 unless $$buf =~ s/\A.*?\r\n\r\n//s;
        $s->write("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\n");
        my $pump; $pump = sub {
          return unless $s->loop;
          $s->write( 'x' x 4096, on_flush => $pump );
          $sent += 4096;
        };
        $pump->();
        return 0;
      },
      on_closed => sub { $closed++ },
    );
    $loop->add($stream);
  },
);
$loop->add($listener);
$listener->listen(
  addr => { family => 'inet', socktype => 'stream', ip => '127.0.0.1', port => 0 },
)->get;
my $port = $listener->read_handle->sockport;

my $ws = Net::Async::WebSearch->new;
$loop->add($ws);

my $r = Net::Async::WebSearch::Result->new(
  url => "http://127.0.0.1:$port/endless", title => 't', provider => 'p', rank => 1,
);

my $guard = $loop->delay_future( after => 5 )
  ->then(sub { Future->fail('test guard: fetch never ended') });
Future->wait_any( $ws->_fetch_one( $r, max_bytes => 10_000 ), $guard )->get;

my $f = $r->fetched;
ok( $f && $f->{ok}, 'fetch of an endless body completes' );
is( length $f->{body}, 10_000, 'body is cut at max_bytes' );

$loop->delay_future( after => 0.3 )->get;
my $after = $sent;
$loop->delay_future( after => 0.3 )->get;
is( $sent, $after, 'transfer was aborted, server is no longer being read from' );

done_testing;
