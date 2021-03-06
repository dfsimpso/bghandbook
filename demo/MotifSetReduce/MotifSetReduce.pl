#! /usr/bin/perl -w
#
# MotifSetReduce.pl
# Version of February 8, 2016.  Volker Brendel

use strict;
use Getopt::Std;
use Data::Dumper;

my $debug = 0;
my $CONS1 = 0.6;
my $CONS2 = 0.75;




my $USAGE="\nUsage: $0 -m motiffile [-v] [-d delta][-t mmthreshold]\n


** This script reads input from a DNA motif file (required option -m) which is meant to
   contain multiple related DNA motifs as frequency matrices.
   The script will reduce this set to non-redundant consensus motifs based on the parameters
   delta (default: 5) and mmthreshold (default: 0.09).

   delta refers to the minimum number of overlapping positions between motifs for a pairwise
   distance to be calculated.

   mmthreshold refers to the maximum distance for motifs to be candidates for merging.

   -v generates verbose output (for debugging, set the variable $debug to 1 in the code).
 
   \n";


my %args;
getopts('m:vd:t:', \%args);

my ($MFILE);
if (!defined($args{m})) {
  print "\n!!! No motif set file specified.\n\n";
  die $USAGE;
}
my $msfile = $args{m};
if (! -e $msfile) {
  print "\n!!! motif set file $msfile does not exist.\n\n";
  die $USAGE;
}

my $verbose = 0;
if ($args{v}) {
  $verbose = 1;
}

my $delta = 5;
if (defined($args{d})) {
  $delta = $args{d};
  if ($delta !~ /\d+/) {
    print "\n  Error: argument of -d option must be integer.\n\n";
    print $USAGE;
    exit;
  }
}

my $mmthreshold = 0.09;
if (defined($args{t})) {
  $mmthreshold = $args{t};
}


print "Now running MotifSetReduce.pl with arguments -m $msfile -d $delta -t $mmthreshold ...\n\n";

my $line;
my %motifset;
my ($motif1, $motif2);
my ($row1, $nbrows1, $row2, $nbrows2);
my $r;
my $label = "";
my %motifdst;
my ($mrgmtf1,$mrgmtf2,$mrgm12d,$mrgmtf1a,$mrgmtf2a);


if ($debug) {$verbose = 1;}

# Reading in the original motif file:
#
open (MFILE, "< $msfile");
while (defined($line = <MFILE>)) {
  if ( $line =~ /^MOTIF/ ) {
    ($motif1) = $line =~ /^MOTIF (\w+) /;
#   print $motif1, "\n";

# Setting up an empty hash for motif $motif1 in the data structure $motifset
#  (a hash with keys $motif1 and values being hashes with keys row01, row02,
#  ... and values arrays containing the nucleotide frequencies in each motif
#  position; this is the Perl way of representing a 3-dimensional array
#  consisting of motifs, rows, and frequency values):
#
    $motifset{$motif1} = {};
    $r = 0;
  }
  if ( $line =~ /^[0\1]/ ) {
    chomp($line);
    $r++;
    if ($r < 10) {
      $label = "row" . "0$r";
    } else {
      $label = "row" . "$r";
    }

# Here we are adding the frequencies on $line to the proper row key for
# motif $motif1:
#
    @{$motifset{$motif1}{$label}}= split(/\t/,$line);
  }
}

if ($debug) {print "\nDump of motif set as read into program:\n\n", Dumper(%motifset), "\n\n";}

# Iterative merging the two most similar motifs.
#

# First we determine the motif set pairwise distances and have the function
# mspwd() return for the closest motifs the two motif identifiers, the distance,
# and the alignment offsets that give the shortest distance:
#
($mrgmtf1,$mrgmtf2,$mrgm12d,$mrgmtf1a,$mrgmtf2a) = mspwd();

# We call the mergemotifs() function to merge the two closest motifs and reiterate
# the process as long as the motifset contains two motifs closer than the merging
# threshold $mmthreshold:
#
while ($mrgm12d < $mmthreshold) {
  if ($verbose) {
    printf "\nMerging motifs $mrgmtf1 and $mrgmtf2 (distance %6.3f at offsets $mrgmtf1a/$mrgmtf2a)\n", $mrgm12d;
  }
  mergemotifs($mrgmtf1,$mrgmtf2,$mrgmtf1a,$mrgmtf2a);
  ($mrgmtf1,$mrgmtf2,$mrgm12d,$mrgmtf1a,$mrgmtf2a) = mspwd();
}

displaymotifset();
  
#END main program



# Functions:
#
sub motifdistance {
  my $motif1 = $_[0];
  my $motif2 = $_[1];
  my ($s,$k,$l,$o);
  my $dst = 0.0;
  my (@tmpds1,@tmpd1s);
  my ($minvs1,$minxs1,$minv1s,$minx1s);

  my $width1 = keys %{$motifset{$motif1}};
  my $width2 = keys %{$motifset{$motif2}};
  if ($verbose) {
    print "\nComparing motif $motif1 ($width1 positions) versus motif $motif2 ($width2 positions):\n";
  }

  @tmpds1 = ();
  for ($s=$width1-$delta+1;$s>1;$s--) {
    if ($debug) {
      print "... calculating distance for offsets $s/1:\n";
    }
    $dst = 0.0;
    for ($k=1; $s-1+$k <= $width1 && $k <= $width2; $k++) {
      $l = $s-1+$k;
      if ($l < 10) {$row1 = "row" . "0$l";} else {$row1 = "row" . "$l";}
      if ($k < 10) {$row2 = "row" . "0$k";} else {$row2 = "row" . "$k";}
      if ($debug) {
        print "... adding $row1 @{$motifset{$motif1}{$row1}} versus $row2 @{$motifset{$motif2}{$row2}} dsqr() value\n";
      }
      $dst += dsqr(\@{$motifset{$motif1}{$row1}},\@{$motifset{$motif2}{$row2}});
    }
    $dst = $dst/($k-1);
    push (@tmpds1,$dst);
  }
  if ($#tmpds1 > 0) {
    ($minvs1,$minxs1) = argmin(@tmpds1);
  } else {
    ($minvs1,$minxs1) = (2*$mmthreshold,-1);
  }

  @tmpd1s = ();
  for ($s=1; $s<=$width2-$delta+1; $s++) {
    if ($debug) {
      print "... calculating distance for offsets 1/$s:\n";
    }
    $dst = 0.0;
    for ($k=1; $k <= $width1 && $s-1+$k <= $width2; $k++) {
      $l = $s-1+$k;
      if ($k < 10) {$row1 = "row" . "0$k";} else {$row1 = "row" . "$k";}
      if ($l < 10) {$row2 = "row" . "0$l";} else {$row2 = "row" . "$l";}
      if ($debug) {
        print "... adding $row1 @{$motifset{$motif1}{$row1}} versus $row2 @{$motifset{$motif2}{$row2}} dsqr() value\n";
      }
      $dst += dsqr(\@{$motifset{$motif1}{$row1}},\@{$motifset{$motif2}{$row2}});
    }
    $dst = $dst/($k-1);
    push (@tmpd1s,$dst);
  }
  if ($#tmpd1s > 0) {
    ($minv1s,$minx1s) = argmin(@tmpd1s);
  } else {
    ($minv1s,$minx1s) = (2*$mmthreshold,-1);
  }
 
  if ($minxs1 + $minx1s == -2) {
    if ($debug) {
      print "\n... no alignment with overlap >= $delta possible\n";
    }
    return (-1,-1,2*$mmthreshold);
  }
  else {
    if ($minv1s < $minvs1) {
      $o = $minx1s + 1;
      if ($debug) {
        print "\n... the best alignment occurs for offsets 1/$o with distance $minv1s\n";
      }
      return (1,$o,$minv1s);
    } else {
      $o = $width1-$delta+1 - $minxs1;
      if ($debug) {
        print "\n... the best alignment occurs for offsets $o/1 with distance $minvs1\n";
      }
      return ($o,1,$minvs1);
    }
  }

}


sub dsqr {
  my $d = 0.0;
  for (my $i=0; $i<=$#{$_[0]}; $i++) {
    $d += ($_[0][$i] - $_[1][$i]) * ($_[0][$i] - $_[1][$i]);
  }
  return ($d);
}


sub argmin {
  my @data = @_;
  my $i = $#data;
  my $min = $i;
  $min = $data[$i] < $data[$min] ? $i : $min while $i--;
  return ($data[$min],$min);
}


sub mspwd {

  if ($verbose) {
    print "\nDetermining pairwise distances for motif set:\n";
  }
  foreach $motif1 (sort keys (%motifset)) {
    $nbrows1 = keys %{$motifset{$motif1}};
    if ($verbose) {
      print "\nMotif1: $motif1 ($nbrows1 positions)\n";
      foreach $row1 (sort keys (%{$motifset{$motif1}})) {
        print "@{$motifset{$motif1}{$row1}}\n";
      }
    }
    foreach $motif2 (sort keys (%motifset)) {
      if ($motif2 gt $motif1) {
        $nbrows2 = keys %{$motifset{$motif2}};
        if ($verbose) {
          print "\n\tMotif2: $motif2 ($nbrows2 positions)\n";
          foreach $row2 (sort keys (%{$motifset{$motif2}})) {
            print "\t@{$motifset{$motif2}{$row2}}\n";
          }
        }
        my ($mo1,$mo2,$dst) = motifdistance($motif1,$motif2);
        if ($verbose) {
          printf "... distance $motif1 versus $motif2 is calculated as %6.3f at offsets $mo1/$mo2\n", $dst;
        }
        @{$motifdst{$motif1}{$motif2}} = ($mo1,$mo2,$dst);
      }
    }
  }
  
  if ($verbose) {print "\n\n";}
  my $mrgm12d = $mmthreshold;
  my ($mrgmtf1,$mrgmtf2,$mrgmtf1a,$mrgmtf2a);
  foreach $motif1 (sort keys (%motifset)) {
    foreach $motif2 (sort keys (%motifset)) {
      if ($motif2 gt $motif1) {
        if ($debug) {
          printf "Motif pair $motif1/$motif2 offsets and distance: ${$motifdst{$motif1}{$motif2}}[0]/${$motifdst{$motif1}{$motif2}}[1] %6.3f\n", ${$motifdst{$motif1}{$motif2}}[2];
        }
        if (${\@{$motifdst{$motif1}{$motif2}}}[2] < $mrgm12d) {
          $mrgmtf1  = $motif1;
          $mrgmtf2  = $motif2;
          $mrgm12d  = ${\@{$motifdst{$motif1}{$motif2}}}[2];
          $mrgmtf1a = ${\@{$motifdst{$motif1}{$motif2}}}[0];
          $mrgmtf2a = ${\@{$motifdst{$motif1}{$motif2}}}[1];
        }
      }
    }
  }
  return ($mrgmtf1,$mrgmtf2,$mrgm12d,$mrgmtf1a,$mrgmtf2a);
}


sub mergemotifs { 
  my ($mrgmtf1,$mrgmtf2,$mrgmtf1a,$mrgmtf2a) = @_;
  my ($k,$l,$label);
  my @tmprow = ();
  my $width1 = keys %{$motifset{$mrgmtf1}};
  my $width2 = keys %{$motifset{$mrgmtf2}};
  my $mergedmotif = $mrgmtf1 . "m";

  if ($debug) {
    print "\nBEFORE merging the motifset hash contains:\n", Dumper(%motifset), "\n";
  }

  if ($mrgmtf1a > 1) {
    if ($debug) {
      print "... motif offsets are $mrgmtf1a/1:\n";
    }
    for ($k=1; $mrgmtf1a-1+$k <= $width1 && $k <= $width2; $k++) {
      $l = $mrgmtf1a-1+$k;
      if ($l < 10) {$row1 = "row" . "0$l";} else {$row1 = "row" . "$l";}
      if ($k < 10) {$row2 = "row" . "0$k";} else {$row2 = "row" . "$k";}
      if ($debug) {
        print "... merging $row1 @{$motifset{$mrgmtf1}{$row1}} with $row2 @{$motifset{$mrgmtf2}{$row2}}\n";
      }
      @tmprow = ();
      for (my $i=0;$i<4;$i++) {
        my $x = 0.5 * ${\@{$motifset{$mrgmtf1}{$row1}}}[$i] + 0.5 * ${\@{$motifset{$mrgmtf2}{$row2}}}[$i];
        push(@tmprow,$x);
      }
      @{$motifset{$mergedmotif}{$row2}}= @tmprow; 
    }
  }
  else {
    if ($debug) {
      print "... motif offsets are 1/$mrgmtf2a:\n";
    }
    for ($k=1; $k <= $width1 && $mrgmtf2a-1+$k <= $width2; $k++) {
      $l = $mrgmtf2a-1+$k;
      if ($k < 10) {$row1 = "row" . "0$k";} else {$row1 = "row" . "$k";}
      if ($l < 10) {$row2 = "row" . "0$l";} else {$row2 = "row" . "$l";}
      if ($debug) {
        print "... merging $row1 @{$motifset{$mrgmtf1}{$row1}} with $row2 @{$motifset{$mrgmtf2}{$row2}}\n";
      }
      @tmprow = ();
      for (my $i=0;$i<4;$i++) {
        my $x = 0.5 * ${\@{$motifset{$mrgmtf1}{$row1}}}[$i] + 0.5 * ${\@{$motifset{$mrgmtf2}{$row2}}}[$i];
        push(@tmprow,$x);
      }
      @{$motifset{$mergedmotif}{$row1}}= @tmprow; 
    }
  }
  delete $motifset{$mrgmtf1};
  delete $motifset{$mrgmtf2};
  if ($debug) {
    print "\nAFTER  merging the motifset hash contains:\n", Dumper(%motifset), "\n";
  }
}
 

sub displaymotifset {
  my $i;
  my $sum;
  print "\n\nConsensus motifs at merging threshold $mmthreshold:\n";
  foreach $motif1 (sort keys (%motifset)) {
    $nbrows1 = keys %{$motifset{$motif1}};
    print "\nDE\t$motif1 ($nbrows1 positions)\n";
    foreach $row1 (sort keys (%{$motifset{$motif1}})) {
      for ($i=0;$i<$#{$motifset{$motif1}{$row1}};$i++) {
        printf "%5.3f\t", ${\@{$motifset{$motif1}{$row1}}}[$i];
      }
      printf "%5.3f\t%s\n", ${\@{$motifset{$motif1}{$row1}}}[$i], row2consensus(${\@{$motifset{$motif1}{$row1}}}[0],${\@{$motifset{$motif1}{$row1}}}[1],${\@{$motifset{$motif1}{$row1}}}[2],${\@{$motifset{$motif1}{$row1}}}[3]);
    }
    print "XX\n";
  }
}


#Adapted from STAMP formatMotifs.pl:
#
		
sub calcIC {
	my $sum = 0;
	my $total=0;
	for (my $ic=0; $ic<4; $ic++) {
		if($_[$ic]>0){
			$total+=$_[$ic];
		}
	}
	for (my $ic=0; $ic<4; $ic++){
		if($_[$ic]>0){
			$sum +=$_[$ic]/$total * (log($_[$ic]/$total)/log(2));
		}
	}
	return(2+$sum);
}


sub row2consensus{
	my @f=();
	$f[0] = $_[0];	
	$f[1] = $_[1];
	$f[2] = $_[2];
	$f[3] = $_[3];
	#Hard-coded consensus alphabet rules
	my @two_base_l = ("Y", "R", "W", "S", "K", "M");
	
	my $sum=0;
	for(my $g=0; $g<4; $g++){
		$sum+=$f[$g];
	}
	
	my @two_base_c =();	
	$two_base_c[0]=($f[1]+$f[3])/$sum;
	$two_base_c[1]=($f[0]+$f[2])/$sum;
	$two_base_c[2]=($f[0]+$f[3])/$sum;
	$two_base_c[3]=($f[1]+$f[2])/$sum;
	$two_base_c[4]=($f[2]+$f[3])/$sum;
	$two_base_c[5]=($f[0]+$f[1])/$sum;
	
        my $curr;
        my $p_max;

	if($f[0]/$sum>=$CONS1) {$curr="A";}
	elsif($f[1]/$sum>=$CONS1) {$curr="C";}
	elsif($f[2]/$sum>=$CONS1) {$curr="G";}
	elsif($f[3]/$sum>=$CONS1) {$curr="T";}
	else {
		$curr="N";
		$p_max=$CONS2;
		for(my $h=0;$h<6;$h++) {
			if($two_base_c[$h]>=$p_max) {
				$p_max=$two_base_c[$h];
				$curr=$two_base_l[$h];
			}
		}
	}
	
	return($curr);
}
