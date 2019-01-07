#!/usr/bin/perl
#
# zim-to-org converter
#
# Converts zim directory tree to orgmode tree file.
#
# Copyright (c) 2016 Vlad Lesin <vlad_lesin@mail.ru>
# License: http://www.gnu.org/licenses/gpl.html GPL version 3
#

use strict;

my $num_args = $#ARGV + 1;
if ($num_args != 1) {
  usage();
  exit 1;
}

zim_to_orgmode($ARGV[0]);
exit 0;

sub usage() {
  print STDERR
        "zim-to-org is a simple zim directory notes to emacs orgmode file converter.\n".
        "\n".
        "Usage: zim-to-org.pl <PATH>\n".
        "where <PATH> is the path to zim notes.\n".
        "Orgmode file will be printed to stdout.\n".
        "\n".
        "The converter supports only zim tree to orgmode tree conversion,\n".
        "it does support converting wiki-format to orgmode format, except headers,\n".
        "which are converted to org-mode headers of corresponding level,\n".
        "and zim page creation date.\n";
}

sub get_dir_entries {
  my $pwd = shift;
  my $flo = [];
  my %fluo;

  opendir(DIR,"$pwd") or die "Cannot open $pwd\n";
  my @files = readdir(DIR);
  closedir(DIR);

  foreach my $file (@files) {
    my $fp = "$pwd/$file";
    if (-d $fp) {
      next if ($file eq '.' || $file eq '..' || $file eq '.zim');
      my $entry = $fluo{$file};
      if (defined $entry) {
        $entry->{'name'} = $file;
        $entry->{'ctime'} = (stat($fp))[10];
      }
      else {
        $entry = {
          'name' => $file,
          'ctime' => (stat($fp))[10]
        };
        $fluo{$file} = $entry;
      }
      next;
    }
    next if ($file !~ /\.txt$/i);
    my $file_key = $file;
    $file_key =~ s/\.txt$//g;
    my $entry = $fluo{$file_key};
    if (defined $entry) {
      $entry->{'file'} = $file;
    }
    else {
      $entry =
      {
        'file' => $file,
        'ctime' => (stat($fp))[10]
      };
      $fluo{$file_key} = $entry;
    }
  }

  foreach my $n (sort { $fluo{$a}->{'ctime'} <=> $fluo{$b}->{'ctime'} } keys %fluo) {
    my $entry = $fluo{$n};
    push @$flo, $entry;
  }

  return $flo;
}

sub build_tree {
  my $root = shift;
  my @queue;
  push @queue, $root;

  my $current_level_size = 1;
  my $next_level_size = 0;
  my $level = 1;

  while (@queue) {
    my $node = shift @queue;
    my $pwd =
    $node->{'level'} ?
    "$node->{'pwd'}/$node->{'name'}" :
    $node->{'pwd'};
    my $dir_entries = get_dir_entries($pwd);
    my $node_children = $node->{'children'};

    foreach my $dir_entry (@$dir_entries) {
      my $node_child = {
        'level' => $level,
        'file' => "$dir_entry->{'file'}",
        'children' => []
      };
      if (! exists $dir_entry->{'name'} ) {
        $node_child->{'name'} = substr($dir_entry->{'file'}, 0, -4);
      }
      else {
        $node_child->{'name'} = $dir_entry->{'name'};
        push @queue, $node_child;
        ++$next_level_size;
      }
      $node_child->{'pwd'} = $pwd;
      push @$node_children, $node_child;
    }

    --$current_level_size;
    if (!$current_level_size) {
      $current_level_size = $next_level_size;
      $next_level_size = 0;
      ++$level;
    }
  }
}

sub out_node {
  my $node = shift;
  my $level = $node->{'level'};

  return if (!$level);

  print '*'x$level;
  print ' ';
  my $header_name = $node->{'name'};
  $header_name =~ s/_/ /g;
  print "$header_name\n";

  return if (!exists $node->{'file'});
  #
  # Show the contend of the node in a separate leaf
  # as it's quite comfortable to have ability
  # to fold node content and see it's childs.
  #
  print '*'x($level + 1);
  print " content\n";

  my $line_number = 0;
  my $first_header = 1;
  my $number_of_void_newlines = 0;

  my $fp = "$node->{'pwd'}/$node->{'file'}";
  open FILE, $fp;

  while (<FILE>) {
    ++$line_number;
    #
    # Skip
    #
    # Content-Type: text/x-zim-wiki
    # Wiki-Format: zim 0.4
    # 
    next if ($line_number < 3);
    #
    # Convert file creation date to orgmode format
    #
    if ($line_number == 3 &&
       /^Creation-Date: (\d{4}-\d{2}-\d{2})T(\d{2}:\d{2}:\d{2})/) {
      print "[$1 $2]\n";
      next;
    }
    #
    # Skip
    # Created ...
    # as created date has been already converted to orgmode
    #
    next if ($line_number == 6 && /^Created /);
    #
    # Skip file trailing newlines
    #
    chomp;
    if (!length) {
      ++$number_of_void_newlines;
      next;
    };
    if ($number_of_void_newlines) {
      print "\n"x$number_of_void_newlines;
      $number_of_void_newlines = 0;
    }
    #
    # Convert checkbixes to orgmode format
    #
    s/\[\*\]/\[X\]/g;
    #
    # Convert any starting '*' to '-' to save orgmode tree
    #
    s/^\*/-/g;
    #
    # Convert bold markers to orgmode format
    #
    s/^-\*([^\*]+)\*\*/\*$1\*/g;
    s/\*\*([^\*]+)\*\*/\*$1\*/g;
    #
    # Convert italic markers to orgmode format
    #
    s/\/\/([^\/]+)\/\//\/$1\//g;
    #
    # Convert underlined markers to orgmode format
    #
    s/__([^\_]+)__/_$1_/g;
    #
    # Convert strike-through markers to orgmode format
    #
    s/~~([^\~]+)~~/\+$1\+/g;
    #
    # Convert verbatim markers to orgmode format
    s/''([^\']+)''/=$1=/g;
    #
    # Convert zim headers to orgmode subtrees
    #
    if (/^={1,6} ([^\n]+) ={1,6}$/) {
      my $h = $1;
      my $number_of_eq = index($_, ' ') - 1;
      my $sublevel = 5 - ($number_of_eq - 1);
      #
      # Skip first header as it's usually the same as subtree's name
      #
      if ($first_header && $sublevel == 1 && $h eq $header_name) {
        $first_header = 0;
        next;
      }
      my $internal_level = $level + 1 + $sublevel ;
      print '*'x$internal_level." $h\n";
    }
    else {
      print "$_\n";
    }
  }
  close FILE;
}

sub out_tree {
  my $root = shift;
  my @stack;
  push @stack, $root;

  while(@stack) {
    my $node = pop @stack;
    my $level = $node->{'level'};
    my $children = $node->{'children'};

    foreach my $child (@$children) {
      push @stack, $child;
    }

    out_node($node);
  }
}

sub zim_to_orgmode {
  my $dir = shift;
  my $root = {
    'name' => 'root',
    'level' => 0,
    'pwd' => $dir,
    'file' => '',
    'children' => []
  };
  build_tree($root);
  out_tree($root);
}

