#!/usr/bin/perl
#
# barchart.pl - a simple gnuplot front-end for generating bar charts
#
# Copyright (C) Emilio G. Cota <cota@braap.org>
# License: GPL v2 or later, see LICENSE.

use warnings;
use strict;
use Data::Dumper;
use Getopt::Long;
use Text::Wrap;
binmode STDOUT, ":utf8";

my $man_name = "    barchart.pl - a simple gnuplot (>= 5.0) front-end for generating bar charts\n";
my $man_synopsis = "    barchart.pl [options] [file]\n\n";
$man_synopsis .= "    File: path to input file, or read input from STDIN.\n";
$man_synopsis .= "    Options:\n";
$man_synopsis .= "      --extra: extra arguments to pass to the script.\n";
$man_synopsis .= "               Multiple --extra=foo arguments are supported.\n";
$man_synopsis .= "      --extra-gnuplot: extra arguments to pass straight to gnuplot.\n";
$man_synopsis .= "               Multiple --extra-gnuplot=foo arguments are supported.\n";
$man_synopsis .= "      -h|--help: show this help message.\n";
$man_synopsis .= "      --man: show full documentation (markdown format).\n";
$man_synopsis .= "\n";

my @extra_args;
my @extra_gnuplot_args;
my $file;

my $bargap = 1;
my $boxwidth = 1;
my $column;
my @colorset;
my $fill_style = 'solid 1.0';
my $gridy = 1;
my $key_invert = 0;
my $legend = 1;
my $noupperright = 0;
my $mmlabelshift;
my $pattern_init = 2;
my $patterns;
my $xlabels = 1;
my $xtics_rotate = 90;
my $ymin = '';
my $ymax = '';
my @plot_default_lines;
my $data;
my @histograms;
my $data_mode = 'multi'; # default because =multi comes *after* the first set

my $bool_opts = {
    'patterns' => {
	func => sub { $patterns = 1; $fill_style = "pattern $pattern_init" },
	init => 1,
	doc => 'Specifies that pattern fills rather than solid colors should be used to fill the bars',
    },
    'gridx' => {
	str => sub { return "set grid xtics\n" },
	doc => 'Enables printing of the grid lines for the X axis',
    },
    'nogridy' => {
	func => sub { $gridy = 0 },
	init => 1,
	doc => 'Disables printing of grid lines for the Y axis',
    },
    'nolegend' => {
	func => sub { $legend = 0 },
	init => 1,
	doc => 'Disables the chart\'s legend',
    },
    'norotate' => {
	func => sub { $xtics_rotate = 0 },
	init => 1,
	doc => 'Disables rotation of x tic mark labels. By default, they are vertical',
    },
    'noupperright' => {
	str => sub {
	    my $str = "set xtics nomirror\n";
	    $str   .= "set ytics nomirror\n";
	    $str   .= "set border 0x3";
	    return $str;
	},
	doc => 'Disables the top and right borders of the chart',
    },
    'noxlabels' => {
	func => sub { $xlabels = 0 },
	init => 1,
	doc => 'Disables labels for the X-axis\' tics',
    },
};

my $opts = {
    'barwidth' => {
	func => sub { $boxwidth = $_[0] },
	init => 1,
	doc => 'Sets the width of each bar. The default value is 1',
    },
    'colorset' => {
	str => sub {
	    push @colorset, split(',', $_[0]);
	    for (my $i = 0; $i < @colorset; $i++) {
		my $j = $i + 1;
		print "set linetype $j lc rgb \"$colorset[$i]\"\n";
	    }
	    # we could use 'linetype cycle' here, but it doesn't
	    # seem to work in gnuplot 5.0 for bars.
	},
	doc => 'Sets the colors to use via RGB hex values. Colors should be separated by commas and listed in order. If there are less colors than datasets, colors from the colorset are repeated',
    },
    'column' => {
	func => sub { $column = $_[0] },
	doc => 'Specifies which column contains the numbers of interest, thereby ignoring values in other columns. The column numbers begin at 1, which is assumed to always be the benchmark name. The special token \'last\' can be used here to indicate the final column',
    },
    'intra_space_mul' => {
	func => sub {
	    $bargap *= $_[0];
	    if ($bargap && !($bargap % 2)) {
		$bargap += 1;
	    }
	},
	init => 1,
	doc => 'Controls the amount of space between bars or clusters of bars for a clustered chart. Note that this parameter does not apply to the spacing between stacked clusters, i.e. those defined with `=stackcluster`',
    },
    'logscaley' => {
	str => sub { return "set logscale y $_[0]" },
	doc => 'Sets a logarithmic scale for the y axis, with the specified base',
    },
    'min' => {
	func => sub { $ymin = $_[0] },
	init => 1,
	doc => 'Sets the minimum y value displayed',
    },
    'max' => {
	func => sub { $ymax = $_[0] },
	init => 1,
	doc => 'Sets the maximum y value displayed',
    },
    'rotateby' => {
	func => sub { $xtics_rotate = abs($_[0]) },
	init => 1,
	doc => 'Sets the rotation angle (in degrees) of the X-axis\' labels',
	},
    'multimulti' => {
	parse => sub {
	    if (@histograms) {
		push @{ $data->{$data_mode} }, '=multimulti';
	    }
	    push @histograms, defined($_[0]) ? $_[0] : '';
	},
    },
    'multimultilabelshift' => {
	func => sub { $mmlabelshift = $_[0]; },
	init => 1,
	doc => 'Sets the offset of the `multimulti=` cluster titles. Passed straight to gnuplot',
    },
    'title' => {
	str => sub {
	    my $quoted_str = quote_user_str($_[0]);
	    return "set title $quoted_str";
	},
	doc => 'Sets the title of the chart',
    },
    'xlabel' => {
	str => sub {
	    my $quoted_str = quote_user_str($_[0]);
	    return "set xlabel $quoted_str";
	},
	doc => 'Sets the X-axis\' label',
    },
    'xlabelshift' => {
	str => sub { return "set xlabel offset $_[0]" },
	doc => 'Passed straight to gnuplot',
    },
    'yformat' => {
	str => sub { return "set format y '$_[0]'" },
	doc => 'Specifies the printf-like format for the y tic mark labels',
    },
    'ylabel' => {
	str => sub {
	    my $quoted_str = quote_user_str($_[0]);
	    return "set ylabel $quoted_str";
	},
	doc => 'Sets the Y-axis\' label',
    },
    'ylabelshift' => {
	str => sub { return "set ylabel offset $_[0]" },
	doc => 'Passed straight to gnuplot',
    },
};

my $arr_opts = {
    'extraops' => {
	str => sub { return join("\n", @{ $_[0] }) },
	doc => 'Specifies a command to pass straight to gnuplot. See also the -e command-line argument',
    },
    'horizline' => {
	func => sub {
	    my @arr = map { "f(x)=$_,f(x) notitle dt 1" } @{ $_[0] };
	    push @plot_default_lines, @arr;
	},
	doc => 'Draws a horizontal line at the specified y value',
    },
};

my $unk_opts; # hash of arrays
my $unk_bool_opts; # hash of 1's

my $gr_types = {
    'cluster' => {
	str => sub {
	    return defined($data->{yerrorbars}) ? 'errorbars lw 1' : 'cluster';
	},
    },
    'stackcluster' => {
	str => sub {
	    $key_invert = 1;
	    my $offset = '';
	    if (defined($mmlabelshift)) {
		$offset = "title offset $mmlabelshift";
	    }
	    return "rowstacked $offset";
	},
    },
    'stacked' => {
	str => sub { $key_invert = 1; return 'rowstacked' },
    },
};

my $gr_opts = {
    'type' => undef,
    'titles' => undef,
};

my $data_types = {
    'yerrorbars' => undef,
    'table' => undef,
    'multi' => {
	'func' => sub { push @{ $data->{multi} }, '=multi' },
    },
};

sub parse_input {
    my $in;

    if (defined($file)) {
	open $in, '<:encoding(UTF-8)', $file
	    or die "Could not open '$file' for reading $!";
    } else {
	open $in, '<-' or die "Could not open STDIN for reading: $!";
    }
    while (<$in>) {
	parse_line($_);
    }
    close $in or die "Cannot close '$file': $!";

    foreach my $line (@extra_args) {
	parse_line($line);
    }

    if (!defined($gr_opts->{type})) {
	$gr_opts->{type} = 'cluster';
    }
}

sub parse_line {
    my ($line) = @_;

    chomp $line;

    $line =~ s/^\s*//;
    $line =~ s/\s*$//;

    if ($line =~ /^#/ or $line =~ /^\s*$/) {
	return;
    } elsif ($line =~ /^([_A-Za-z]+)=(.*)$/) {
	my $k = $1;
	my $v = $2;
	if (exists $opts->{$k}) {
	    # if it needs to be parsed right now, call it.
	    # Otherwise, just save the value for later processing.
	    if ($opts->{$k}->{parse}) {
		$opts->{$k}->{parse}->($v);
	    } else {
		$opts->{$k}->{val} = $v;
	    }
	} elsif (exists $arr_opts->{$k}) {
	    push @{ $arr_opts->{$k}->{val} }, $v;
	} else {
	    push @{ $unk_opts->{$k}->{val} }, $v;
	}
    } elsif ($line =~ /^=(.*)$/) {
	my $k = $1;
	my $gr_regex = mk_regex($gr_types);
	my $data_regex = mk_regex($data_types);
	if ($k =~ /^$gr_regex(.)(.*)/) {
	    $gr_opts->{type} = $1;
	    my $sep = $2;
	    $gr_opts->{titles} = [ split($sep, $3) ];
	} elsif (exists($bool_opts->{$k})) {
	    $bool_opts->{$k}->{val} = 1;
	} elsif ($k =~ /^$data_regex$/) {
	    if ($data_types->{$1}->{func}) {
		$data_types->{$1}->{func}->();
	    }
	    $data_mode = $1;
	} else {
	    $unk_bool_opts->{$k} = 1;
	}
    } else {
	my ($label, @rest) = parse_data_line($_);
	push @{ $data->{$data_mode} }, join(" ", $label, @rest);
    }
}

sub mk_regex {
    my ($href) = @_;

    return '(' . join('|', sort keys %$href) . ')';
}

sub pr_plt {
    # init ops
    process_opts($bool_opts, 1);
    process_opts($opts, 1);
    process_opts($arr_opts, 1);

    # defaults, some of which might have been overriden
    print "set style data histograms\n";
    my $hist_type = $gr_opts->{type};
    my $ht_str = $gr_types->{$hist_type}->{str}->();
    print "set style histogram $ht_str gap $bargap\n";
    print "set style fill $fill_style border lt -1\n";
    print "set xtics rotate by $xtics_rotate right\n" if $xtics_rotate;
    print "set yrange [$ymin:$ymax]\n";
    print "set title noenhanced\n";
    print "set xlabel noenhanced\n";
    print "set ylabel noenhanced\n";
    print "set xtics noenhanced\n";
    print "set ytics noenhanced\n";
    print "set boxwidth $boxwidth\n";
    print "set xtics format \"\"\n";
    print "set xtics scale 0\n";
    print "set grid ytics\n" if $gridy;
    if ($legend) {
	print "set key invert\n" if $key_invert;
    } else {
	print "set key off\n"
    }

    # opts
    process_opts($bool_opts, 0);
    process_opts($opts, 0);
    process_opts($arr_opts, 0);

    show_ignored_opts();

    # extra gnuplot arguments from command-line
    foreach my $arg (@extra_gnuplot_args) {
	print "$arg\n";
    }

    # data
    print "\$data << EOD\n";
    pr_data();
    print "EOD\n";

    # plot command
    my $n_sets = scalar(@histograms) ? scalar(@histograms) : 1;
    my @arr;
    my $n_groups = get_nr_groups();
    my $start = 2;
    my $step = defined($data->{yerrorbars}) ? 2 : 1;
    my $end = $start + $n_groups * $step;

    for (my $set = 0; $set < $n_sets; $set++) {
	my $hist = 'newhistogram';
	if (defined($histograms[$set])) {
	    $hist .= " '$histograms[$set]'";
	}
	if ($set && defined($patterns)) {
	    $hist .= " fs pattern $pattern_init";
	}
	push @arr, $hist;
	for (my $i = 0; $i < $n_groups; $i++) {
	    my $j = $start + $i * $step;
	    my $k = $j + 1;
	    my $ycol = defined($data->{yerrorbars}) ? ":$k" : '';
	    my $tic = $xlabels ? ':xticlabels(1)' : '';
	    my $datafile = $i == 0 ? '"$data"' : "''";
	    my $tit = "title '";
	    if ($set == $n_sets - 1 && defined($gr_opts->{titles})) {
		$tit .= "$gr_opts->{titles}->[$i]";
	    }
	    $tit .= "'";
	    my $lt = $i + 1;
	    if (@colorset) {
		$lt = 1 + $i % @colorset;
	    }
	    push @arr, "$datafile index $set using $j$ycol$tic $tit lt $lt";
	}
    }
    print "plot\t", join(", \\\n\t", @plot_default_lines, @arr), "\n";

}

# When not in cluster or stacked mode, there's no grouping
sub get_nr_groups {
    if (defined($gr_opts->{titles})) {
	return scalar(@{ $gr_opts->{titles} });
    }
    return 1;
}

sub should_process_opt {
    my ($elem, $init) = @_;

    return ($init && defined($elem->{init})) ||
	(!$init && !defined($elem->{init}));
}

sub process_opts {
    my ($options, $init) = @_;

    foreach my $k (sort keys %$options) {
	my $v = $options->{$k}->{val};
	if (defined($v) && should_process_opt($options->{$k}, $init)) {
	    my $f = $options->{$k}->{str};
	    if (defined($f)) {
		my $str = $f->($v);
		print "$str\n";
	    }
	    $f = $options->{$k}->{func};
	    if (defined($f)) {
		$f->($v);
	    }
	}
    }
}

sub pr_data {
    if (defined($data->{multi})) {
	my $n_groups = get_nr_groups();
	my @labels; # order labels as they show up
	my %seen;
	my $n_sets = scalar(@histograms) ? scalar(@histograms) : 1;
	my $set = 0; # only goes up with =multimulti
	my $group = 0;
	my $out;

	foreach my $line (@{ $data->{multi} }) {
	    if ($line eq '=multi') {
		$group++;
	    } elsif ($line eq '=multimulti') {
		pr_data_set__multi(\@labels, $n_groups, $out);
		$out = {};
		$set++;
		$group = 0;
	    } else {
		my ($label, @rest) = parse_data_line_column($line);
		if (!defined($seen{$label})) {
		    $seen{$label} = 1;
		    push @labels, $label;
		}
		$out->{$label}->{$group} = $rest[0];
	    }
	}
	pr_data_set__multi(\@labels, $n_groups, $out);
    } elsif (defined($data->{yerrorbars})) {
	foreach (my $i = 0; $i < scalar(@{ $data->{table} }); $i++) {
	    my ($label, @val) = parse_data_line($data->{table}->[$i]);
	    die "Malformed input" if !defined($data->{yerrorbars}->[$i]);
	    my (undef, @err) = parse_data_line($data->{yerrorbars}->[$i]);

	    my @arr;
	    for (my $j = 0; $j < scalar(@val); $j++) {
		push @arr, $val[$j], $err[$j];
	    }
	    print join(" ", $label, @arr), "\n";
	}
    } else { # table
	print join("\n", map {
	    (my $s = $_) =~ s/^=multimulti$/\n/; $s
		   } @{ $data->{table} }), "\n";
    }
}

sub pr_data_set__multi {
    my ($labels, $n_groups, $out) = @_;

    foreach my $label (@$labels) {
	# one line per label
	my @arr = ();
	foreach (my $i = 0; $i < $n_groups; $i++) {
	    # fill missing data points with '-'
	    my $v = $out->{$label}->{$i};
	    my $str = defined($v) ? $v : '-';
	    push @arr, $str;
	}
	print join(" ", $label, @arr), "\n";
    }
    print "\n\n";
}

# allow whitespace in the first column only if it's wrapped in double quotes.
# do not allow escaped double quotes inside -- gnuplot won't either.
sub parse_data_line {
    my $line = $_[0];
    my $label;
    my @rest;

    if ($line =~ /^("[^"]+")\s*(.*)/) {
	$label = $1;
	@rest = split(/\s+/, $2);
    } else {
	($label, @rest) = split(/\s+/, $line);
    }
    return ($label, @rest);
}

# Only used in =multi mode
sub parse_data_line_column {
    my ($label, @rest) = parse_data_line($_[0]);

    if (!defined($column)) {
	return $label, @rest;
    }
    my $col = $column;
    if ($col eq 'last') {
	$col = scalar(@rest) + 1;
    } elsif ($col <= 0) {
	die "Invalid column= value";
    }
    $col--; # do not count the label column (i.e. the first one)
    if ($col > scalar(@rest)) {
	return ($label, '-');
    }
    return ($label, $rest[$col - 1]);
}

sub show_ignored_opts {
    foreach my $k (sort keys %$unk_bool_opts) {
	print STDERR "warning: ignored parameter: =$k\n";
    }
    foreach my $k (sort keys %$unk_opts) {
	foreach my $v (@{ $unk_opts->{$k}->{val} }) {
	    print STDERR "warning: ignored parameter: $k=$v\n";
	}
    }
}

sub show_doc {
    my ($title, $intro, $h, $prefix, $suffix) = @_;

    print "$title\n\n";
    if ($intro) {
	print "$intro.\n\n";
    }

    foreach my $k (sort keys %$h) {
	my $doc = $h->{$k}->{doc};
	next if !defined($doc);

	$Text::Wrap::columns = 80;
	print Text::Wrap::wrap("$prefix$k$suffix: ", '  ', $doc), ".\n\n";
    }
}

sub show_help {
    print $man_name, "\n";
    print $man_synopsis;
    exit 0;
}

# If the string starts with double or single quotes, pass it verbatim.
# Otherwise, add double quotes.
sub quote_user_str {
    my ($str) = @_;

    if ($str =~ /^("|')/) {
	return $str;
    }
    return "\"$str\"";
}

sub show_man {
    print "# NAME\n\n";
    print $man_name, "\n";
    print "# SYNOPSIS\n\n";
    print $man_synopsis, "\n";
    print "# DESCRIPTION\n\n";
    pr_description_intro();

    print "### Control parameters\n\n";
    show_doc("#### Simple parameters",
	     "These are boolean parameters that do not require an argument",
	     $bool_opts, '* `=', '`');
    show_doc("#### Parameters with values", '', $opts, '* `', '=foo`');
    show_doc("#### Repeatable parameters with values",
	     "These parameters can be set several times", $arr_opts, '* `',
	     '=foo`');

    print "## Sample Charts\n\n";
    print "![Sample 1, PNG](gallery/gallery1.png)\n";
    print "***\n";
    print "![Sample 2, PNG](gallery/gallery2.png)\n";
    print "***\n";
    print "![Sample 3, PNG](gallery/gallery3.png)\n";

    print "\n# LICENSE\n\n";
    print "GNU GPL v2 or later.\n";

    print "\n# AUTHOR\n\n";
    print "Copyright (C) Emilio G. Cota\n\n";
    print "Some test input files are adapted from bargraph: Copyright (C) Derek Bruening\n";

    print "\n# SEE ALSO\n\n";
    print "* [bargraph](http://www.burningcutlery.com/derek/bargraph)\n";
    print "* [gnuplot](http://www.gnuplot.info)\n";
    print "\n";

    exit 0;
}

sub pr_description_intro {
    my $doc = <<'END';
This is a simple front-end for gnuplot to ease the generation of bar charts.
The script takes an input file with data and commands, and generates output
for gnuplot that includes both data and gnuplot commands.

The syntax of the input file is the almost the same as that of Derek Bruening's
[bargraph](http://http://www.burningcutlery.com/derek/bargraph/). Note,
however, that this script is not a drop-in replacement for bargraph; bargraph
has features such as data processing and legend placement that are unlikely to
ever be supported here. Instead, this script expects you to (1) prepare the
input data with other scripts, and (2) work directly with gnuplot to specify
the final size, aspect ratio and legend of the chart in your chosen terminal.
This can require extra work but it is more flexible than fiddling with fig
output like bargraph does.

This script only works with gnuplot v5.0 or above.

## File Format

The script takes in a single file that specifies the data to chart and control
parameters for customizing the chart. The parameters must precede the data in
the file. Comments can be included in an inputfile following the '#' character.
Empty/whitespace lines are ignored. Leading or trailing whitespace is also
ignored.

### Describing datasets

Either `=table` or `=multi` can be used to describe datasets.

#### `=table`
Indicates that the data will be listed in columns. The table is split by
whitespace. Example:

     =table
     age     37  9 22
     height  17 12 20
     weight  92 52 84

#### `=multi`
When data is not in table format, multiple datasets must be separated by
this marker. Example, equivalent to the `=table` above:

     age    37
     height 17
     weight 92
     =multi
     age     9
     height 12
     weight 52
     =multi
     age    22
     height 20
     weight 84

### Multiple datasets

Multiple datasets can be grouped to generate clustered, stacked or
stacked-clustered bar charts. The grouping is specified by the following
options:

#### `=cluster`
Indicates that there are multiple datasets that should be displayed as
clustered bars. This command also provides the names of the datasets. The
character following `=cluster` is taken as a delimiter separating the rest
of the line into strings naming each dataset. Some examples:

     =cluster;Irish elk;Dodo birds;Coelecanth
     =cluster Monday Tuesday Wednesday Thursday Friday
     =cluster+Fast; slow+Slow; fast

The data itself must either be in table format or each dataset must be
separated by `=multi`.

#### `=stacked`
Just like `=cluster`, this indicates that there are multiple datasets, but
to be displayed as stacked bars rather than clustered bars. The data must
be either in table format or delimited by `=multi`. The names of the datasets
are delimited as with `=cluster`:

     =stacked,Irish elk,Dodo birds,Coelecanth

#### `=stackcluster`
Just like `=cluster`, this indicates that there are multiple datasets, but here
we have an extra dimension and the data is displayed as clusters of stacked
bars. Each cluster is itself like a `=stacked` dataset, and must be either in
table format or delimited by `=multi`. The names of the stacked datasets are
delimited as with `=cluster` and are used in the legend:

     =stackcluster;Basic Blocks;Traces;Hashtables;Stubs

Clusters of stacked bars are separated with `multimulti=`, which optionally can
be used to name each cluster. For example:

     =stackcluster;Basic Blocks;Traces;Hashtables;Stubs
     =table
     multimulti=Private Caches
     ammp             25.635 23.094 14.780 5.543
     applu            25.035 27.375 14.974 4.913
     multimulti=Shared Caches
     ammp             27.863 18.913 15.536 5.404
     applu            24.501 18.657 11.689 4.720
     multimulti=Persistent Caches
     ammp             17.863 11.913 19.536 9.404
     applu            34.501 12.657 18.689 7.720

### Error bars with `=yerrorbars`

The `=yerrorbars` option can be used to specify that vertical error bars are
to be displayed for each datum. This option is not supported with `=stacked` or
`=stackcluster` charts. The error bar data follows this directive, in the same
format as `=table`. Note that non-table-format error bar data is not supported.
END
    print "$doc\n";
}

GetOptions(
    'extra=s' => \@extra_args,
    'extra-gnuplot=s' => \@extra_gnuplot_args,
    'h|help' => \&show_help,
    'man' => \&show_man,
    );

$file = $ARGV[0];

parse_input();
pr_plt();
