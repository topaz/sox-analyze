#!/usr/bin/perl -w
use strict;

use Math::FFT;
use IPC::Open2;

# configurable, but 8 is a good balance
my $windows_per_second = 8;

# hard-coded based on sox invocation
my $bits_per_sample = 16;
my $samples_per_second = 16384;
my $bytes_per_second = ($bits_per_sample * $samples_per_second) / 8;
my $bytes_per_window = $bytes_per_second / $windows_per_second;
my @freqs = map { $_ * $windows_per_second } 0..($samples_per_second / $windows_per_second - 1);

# frequency/key conversion
sub freq_keynum { 12 * log($_[0]/440)/log(2) + 49 }
my @keyname = map {sprintf("% -2s",$_)} qw(Ab A Bb B C Db D Eb E F Gb G);

# load up sox
open2(\*SOX_OUT, \*SOX_IN, 'sox -q -d -b 16 -c 1 -e signed-integer -r 16384 -t raw -L -');
close(SOX_IN);

my $data;
while (read(SOX_OUT, $data, $bytes_per_window)) {
  # convert incoming window to amplitudes
  my @rdft = @{Math::FFT->new([unpack("s<*", $data)])->rdft};
  my @freq_ampl = map {sqrt($rdft[$_*2]**2 + $rdft[$_*2+1]**2)} 0..$#rdft/2;
  my $keytop = freq_keynum($freqs[$#freq_ampl]);
  $keytop = 100 if $keytop > 100;

  # break per-frequency amplitudes into averages per piano key
  my (@keysum, @keyn);
  for my $i (1..$#freq_ampl) {
    my $keynum = freq_keynum($freqs[$i]);
    next unless $keynum >= 0;
    $keysum[$keynum] += $freq_ampl[$i];
    $keyn[$keynum]++;
  }
  my @keyval = map {$keyn[$_] ? $keysum[$_]/$keyn[$_]/1000 : 0} 0..$#keysum;

  # find key with highest average amplitude
  my ($maxv, $maxi) = (0, 0);
  for my $keynum (0..$keytop) {
    ($maxv, $maxi) = ($keyval[$keynum], $keynum) if $keyval[$keynum] > $maxv;
  }
  my $maxkey = $maxi;

  # print primary key (name and number), its amplitude, and frequency amplitude
  # graph; highlight the primary tone in bright green
  printf("%s\t%d\t%d\t[", $keyname[$maxkey % @keyname].int($maxkey / @keyname), $maxkey, $maxv);
  for my $keynum (0..$keytop) {
    my $v = $keyval[$keynum];
    print "\e[1;32m" if $keynum == $maxkey;
    print
      $v > 100 ? "#"
    : $v >  50 ? "="
    : $v >  20 ? "-"
    : $v >  10 ? "_"
    : ".";
    print "\e[0m" if $keynum == $maxkey;
  }
  print "]\n";
}
