#!/usr/bin/perl

use FileHandle;
use IPC::Open2;

$verbose++ if grep(/VERBOSE/, @ARGV);

$m_master = 'm/master';
$t_master = 't/master';

$tree = {};
$subm = {};

# 現在の refs をすべて取得。
open($F, "git show-ref |") || die;
while (<$F>) {
	chomp;
	if (m=^([0-9a-f]{40})\s+refs/remotes/llvm.org/([^/]+)/master$=) {
		$repos{$2} = $1;
	} elsif (m=^([0-9a-f]{40})\s+refs/remotes/llvm.org/([^/]+)/(\S+)$=) {
		$branches{$3}{$2} = $1;
	} elsif (m=^[0-9a-f]{40}\s+refs/tags/([rt])(\d+)$=) {
		$tags{$2} .= " $1$2";
	} elsif (m=^([0-9a-f]{40})\s+refs/heads/$m_master$=) {
		# 各 submodule の最終 commit を得る。
		$last{'m/master'} = $1;
		open(my $F, "git ls-tree $1 |") || die;
		while (<$F>) {
			if (/^100644 blob ([0-9a-f]{40})\s+\.gitmodules$/) {
				$subm->{'.gitmodules'}{A} = '100644';
				$subm->{'.gitmodules'}{O} = 'blob';
				$subm->{'.gitmodules'}{H} = $1;
				$gitmodules = `git cat-file blob $1`;
				next;
			}
			next unless my ($h, $repo) = /^160000 commit ([0-9a-f]{40})\s+(\S+)/;
			$mins{$repo} = $h;
			$subm->{$repo}{A} = '160000';
			$subm->{$repo}{O} = 'commit';
			$subm->{$repo}{H} = $h;
			`git cat-file commit $h` =~ /^tree\s+([0-9a-f]{40})/;
			$tree->{$repo}{A} = '040000';
			$tree->{$repo}{O} = 'tree';
			$tree->{$repo}{H} = $1
		}
		close($F);
	}
}
close($F);

@dt = sort {$a <=> $b} keys %tags;
if (@dt > 2048) {
	system('git tag -d ' . join(' ', @tags{@dt[0..$#dt - 1024]})) && die;
}

$parent = '';
$parent_subm = '';

# 新規のサブモジュールがあった場合、あきらめてぜんぶ取得するものとする。
while (my ($repo, $h) = each %repos) {
	next unless ($mins{$repo} eq '');
	%mins = ();
}

@revs = ();

while (my ($repo, $h) = each %repos) {
	print STDERR "$repo=$h\n" if $verbose;
	$commits{$repo} = &get_commits2($h, $mins{$repo});
	push(@revs, keys %{$commits{$repo}});
}

@t{@revs} = @revs;
@revs = sort {$a <=> $b} keys %t;

$parent_subm = $last{'m/master'};
if ($parent_subm ne '') {
	$lastrev = `git describe --tags $parent_subm`;
	die unless $lastrev =~ m/^r(\d+)$/;
	$parent = `git show-ref --hash t$1`;
}

for my $rev (@revs) {
	my $orig_gitmodules = $gitmodules;
	my $msg = '';
	for my $repo (sort keys %repos) {
		my $r = $commits{$repo}{$rev};
		next unless defined $r;
		while (my ($k, $v) = each %$r) {
			if ($k =~ /^GIT_/) {
				$ENV{$k} = $v;
			} elsif ($k eq 'MSG') {
				die unless ($msg eq '' || $msg eq $v);
				$msg = $v;
			}
		}
		$tree->{$repo}{A} = '040000';
		$tree->{$repo}{O} = 'tree';
		$tree->{$repo}{H} = $r->{tree};
		if (!defined $subm->{$repo}) {
			$gitmodules .= "[submodule \"$repo\"]\n\tpath = $repo\n\turl = http://llvm.org/git/$repo.git\n";
		}
		$subm->{$repo}{A} = '160000';
		$subm->{$repo}{O} = 'commit';
		$subm->{$repo}{H} = $r->{commit};
	}

	# Subtree
	$parent = &make_commit($tree, $msg, $parent);
	print STDERR "t $parent $rev $ENV{GIT_AUTHOR_NAME}\n" if $verbose;

	# Submodule
	if ($gitmodules ne $orig_gitmodules) {
		my $gm = sub {
			my ($F) = @_;
			print $F $gitmodules;
		};
		$subm->{'.gitmodules'}{A} = '100644';
		$subm->{'.gitmodules'}{O} = 'blob';
		$subm->{'.gitmodules'}{H} = &sb_hash("git hash-object -w --stdin", $gm);
	}
	$parent_subm = &make_commit($subm, $msg, $parent_subm);
	print STDERR "m $parent_subm $rev $ENV{GIT_AUTHOR_NAME}\n" if $verbose;

	if ((++$nrevs & 255) == 0 || $rev >= $revs[$#revs - 100]) {
		system("git update-ref refs/tags/t$rev $parent") && die;
		system("git update-ref refs/heads/t/master $parent") && die;
		system("git update-ref refs/tags/r$rev $parent_subm") && die;
		system("git update-ref refs/heads/m/master $parent_subm") && die;
	}

}

exit;

sub make_commit {
	my ($tree, $msg, $parent) = @_;
	my $mktree = sub {
		my ($F) = @_;
		for my $repo (sort keys %$tree) {
			print $F "$tree->{$repo}{A} $tree->{$repo}{O} $tree->{$repo}{H}\t$repo\n";
		}
	};
	my $tree_hash = &sb_hash("git mktree", $mktree);
	my $com_tree = sub {
		my ($F) = @_;
		print $F $msg;
	};
	if ($parent ne '') {
		$parent = "-p $parent";
	}
	return &sb_hash("git commit-tree $tree_hash $parent", $com_tree);
}

sub subprocess {
	my ($cmd, $writer_proc) = @_;
	pipe(R, W) || die;
	my $pid = fork();
	if (!$pid) {
		open(STDOUT, ">&W") || die;
		close(R);
		open(my $F, "| " . $cmd) || die;
		$writer_proc->($F);
		close($F);
		exit 0;
	}
	close(W);
	my @r = <R>;
	close R;
	wait;
	return @r;
}

sub sb_hash {
	my @r = &subprocess(@_);
	my $r = shift @r;
	chomp $r;
	return $r;
}

sub get_commits2 {
	my ($h, $min) = @_;
	my $commits = {};
	if ($min ne '') {
		$h = "$min..$h";
	}
	open(my $F, "git log --pretty=raw --decorate=no $h |") || die;
	my @cm = ();
	my $t;
	while (<$F>) {
		if (@cm > 0 && /^commit\s+([0-9a-f]{40})/) {
			$t = &parse_commit(@cm);
			$commits->{$t->{REV}} = $t;
			@cm = ();
		}
		chomp;
		push(@cm, $_);
	}
	if (@cm > 0) {
		$t = &parse_commit(@cm);
		$commits->{$t->{REV}} = $t;
	}
	return $commits;
}

sub parse_commit {
	my %r = ();
	my @t = ();
	local $_;
	while ($_ = shift @_) {
		if (/^$/) {
			last;
		} elsif (/^(\w+)\s+(.+)\s+<(.+)>\s+(\d+)(\s+\+\d{4})?$/) {
			$r{$1} = "$2 <$3> $4$5";
			$r{"GIT_".uc($1)."_NAME"} = $2;
			$r{"GIT_".uc($1)."_EMAIL"} = $3;
			$r{"GIT_".uc($1)."_DATE"} = $4.$5;
		} elsif (/^(\w+)\s+([0-9a-f]{40})$/) {
			$r{$1} = $2;
		} else {
			die "$_";
		}
	}
	while ($_ = shift @_) {
		if (/git-svn-id:\s+\S+@(\d+)/) {
			$r{REV} = $1;
			last;
		} elsif (/^\s\s\s\s(.*)/) {
			push(@t, "$1\n");
		} else {
			die $_;
		}
	}
	while (@t > 0 && $t[$#t] =~ /^[\r\n]+$/) {
		pop(@t);
	}
	$r{MSG} = join('', @t);
	return \%r;
}

#	Local Variables:
#		tab-width: 4;
#	End:
#EOF
