#!/usr/bin/env perl

# Create test comparison data using a different UTF-8 implementation.

# The generation utf8.dat file must have the following MD5 sum:
#       cff03b039d850f370a7362f3313e5268

use strict;
use warnings;
use FileHandle;

# 0xD800 - 0xDFFF are used to encode supplementary codepoints
# 0x10000 - 0x10FFFF are supplementary codepoints
my (@codepoints) = (0 .. 0xD7FF, 0xE000 .. 0x10FFFF);

my ($utf8);
{
    # Hide "Unicode character X is illegal" warnings.
    # We want all the codes to test the UTF-8 escape decoder.
    no warnings;
    $utf8 = pack("U*", @codepoints);
}
defined($utf8) or die "Unable create UTF-8 string\n";

my $fh = FileHandle->new();
$fh->open("utf8.dat", ">:utf8")
    or die "Unable to open utf8.dat: $!\n";
$fh->write($utf8)
    or die "Unable to write utf8.dat\n";
$fh->close();

# vi:ai et sw=4 ts=4:
