#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

# Every built-in provider endpoint is https; Net::Async::HTTP loads
# IO::Async::SSL lazily and does not depend on it itself.
open my $fh, '<', 'cpanfile' or plan skip_all => 'no cpanfile';
my $cpanfile = do { local $/; <$fh> };

for my $mod (qw( IO::Async::SSL HTTP::Request )) {
  like( $cpanfile, qr/^requires\s+'\Q$mod\E'/m, "cpanfile requires $mod" );
}

done_testing;
