#!/usr/bin/perl

$PWD = $ENV{PWD};

# さいしょに, master に含まれている commit を得る。
# FIXME: Make sure index is clean.
($ch) = `git show-ref refs/heads/master` =~ /([0-9a-f]{40,})/;
system("git read-tree --reset $ch") && die;
open($F, "git ls-tree $ch |") || die;
while (<$F>) {
    next unless /^160000\s+commit\s+([0-9a-f]{40,})\s+(\S+)/;
    $h = $1;
    $repo = $2;
    push(@repos, $repo);
    $master_hash{$repo} = $h;
    print "$h $repo\n";
    chdir("$PWD/$repo");
    &get_commit($h);
#    &get_commits($repo);
    chdir($PWD);
}
close($F);

# 次に、各リポジトリ候補から結果を得て回る。
open($F, "find -depth -mindepth 2 -maxdepth 2 -type d -name .git |") || die;
while (<$F>) {
    print;
    chomp;
    s=^\./==;
    next unless m@^(.+)/\.git$@;
    print "*$1\n";
    chdir("$PWD/$1") || die $1;
    &get_commits($1);
    chdir($PWD);
}
close($F);

# write!
for $r (sort {$a <=> $b} keys %revs) {
    for $h (@{$revs{$r}}) {
        $msg = $commits{$h}{MSG};
        for (grep(/^GIT_/, keys %{$commits{$h}})) {
            $ENV{$_} = $commits{$h}{$_};
        }
        my $repo = $commits{$h}{REPO};
        system("git update-index --add --cacheinfo 160000 $h $repo\n")
            && die;
        if ($master_hash{$repo} eq '') {
            my $gitm = '';
            my ($mode, $mh)
                = `git ls-tree $ch .gitmodules`
                =~ /^(\d+)\s+blob\s+([0-9a-f]{40,})/;
            if ($mh eq '') {
                $mode = '100644';
            } else {
                $gitm = `git cat-file blob $mh`;
            }
            open($F, "| git hash-object -w --stdin > .git/_.bak") || die;
	    $X = $repo;
	    $X = "LLVM" if $X eq 'llvm';
            print $F "$gitm\[submodule \"$repo\"]\n\tpath = $repo\n\turl = git\@github.com:chapuni/$X.git\n";
            close($F);
            $mh = `cat .git/_.bak`;
            chomp $mh;
            system("git update-index --add --cacheinfo $mode $mh .gitmodules")
                && die;
            $master_hash{$repo} = $ch;
        }
    }
    open($F, "git write-tree |") || die;
    my $th = <$F>;
    chomp $th;
    close($F);
    open($F, "| git commit-tree $th -p $ch > .git/_.bak") || die "<$ch $th>";
    print $F "[r$r]$msg";
    close($F);
    $ch = `cat .git/_.bak`;
    chomp $ch;
    print "r$r:$ch\n";
}

die "Completed die!";

sub get_commits
{
    my ($dir) = @_;
    my $F;
    my $a;
    my $head = $master_hash{$dir};
    #die unless $commits{$head};
    open($F, "git show-ref master |") || die;
    while (<$F>) {
        next unless /^([0-9a-f]{40,})\s+(\S+)/;
        #print "$1($2)\n";
        if ($head ne '') {
            $a .= " $master_hash{$dir}..$1";
        } else {
            $a .= " $1";
        }
    }
    print "refs: $a\n";
    close($F);
    my $f = 0;
    open($F, "git log --pretty=raw $a |") || die;
    while (<$F>) {
        if ($f) {
            if (/^(\w+)\s+([0-9a-f]{40,})/) {
                $commits{$h}{$1} = $2;
            } elsif (/^(\w+)\s+(.*)\s+<(.+)>\s+(\d[^\r\n]*)/) {
                $commits{$h}{"GIT_".uc($1)."_NAME"} = $2;
                $commits{$h}{"GIT_".uc($1)."_EMAIL"} = $3;
                $commits{$h}{"GIT_".uc($1)."_DATE"} = $4;
            } else {
                die "XXX: $_" unless /^\s*$/;
                $f = 0;
                $msg = '';
            }
        } else {
            if (/^commit\s+([0-9a-f]{40,})/) {
                $h = $1;
                $f = 1;
                last if $commits{$h};
                $commits{$h}{REPO} = $dir;
                next;
            } elsif (/^    (\s*)$/) {
                $msg .= $1;
                next;
            } elsif (/git-svn-id:.+\@(\d+)/) {
                print "$dir $h r$1\n" unless $1 % 1000;
                $commits{$h}{REV} = $1;
                push(@{$revs{$1}}, $h);
                next;
            } elsif (/^    (.*)$/) {
                $commits{$h}{MSG} .= $msg . $1;
                $msg = '';
            }
        }
    }
    close($F);
}

# ($hash, $origin)
sub get_dag
{
    my ($h, $org) = @_;
    my @hashes = ();
    while (!$commits{$h}) {
        print "$h\n";
        my %c = &get_commit($h);
        die unless %c;
        push(@hashes, $h);
        $h = $c{'parent'};
        last if $h eq '';
    }
    return @hashes;
}

sub get_commit
{
    my ($h) = @_;
    my $F;
    my %c = ();
    open($F, "git cat-file commit $h |") || die;
    while (<$F>) {
        chomp;
        if (/^(\w+)\s+(.*)/) {
            $c{$1} = $2;
        } elsif (/^$/) {
            last;
        } else {
            die;
        }
    }
    my @msg = <$F>;
    close($F);

    if ($msg[$#msg] =~/git-svn-id:.+\@(\d+)/) {
        printf "rev:$1\n";
        pop(@msg);
    }
    while ($msg[$#msg] =~/^[\r\n]*$/) {
        pop(@msg);
        die unless @msg > 0;
    }
    $c{'msg'} = join('', @msg);
    $commits{$h} = {%c};
    return %c;
}

# tree 6ba6abd0fb4097764b11d5088d20823ee65a6eac
# parent 0a6ea83f393d06fb424c470777a1c3e8a8c50ab1
# author Devang Patel <dpatel@apple.com> 1303495797 +0000
# committer Devang Patel <dpatel@apple.com> 1303495797 +0000


for $sub (sort keys %mhash) {
    chdir("$PWD/$sub") || die "$PWD/$sub";
    open($F, "git log --oneline $mhash{$sub}..origin/master |") || die;
    while (<$F>) {
        die unless /^([0-9a-f]{6,})/;
        $h = $1;
        open($FC, "git cat-file commit $h |") || die;
        @c = <$FC>;
        close($FC);
        $an = $ad = $cn = $cd = '';
        if ($c[$#c] =~/git-svn-id:.+\@(\d+)/) {
            $r = $1;
            pop(@c);
        }
        while ($c[$#c] =~/^[\r\n]*$/) {
            pop(@c);
            die unless @c > 0;
        }
        while (1) {
            $l = shift(@c);
            if ($l =~ /^tree / || $l =~ /^parent /) {
                next;
            } elsif ($l =~ /^author\s+(.+)\s+(\d{10})/) {
                $an{$h} = $1;
                $ad{$h} = $2;
            } elsif ($l =~ /^committer\s+(.+)\s+(\d{10})/) {
                $cn{$h} = $1;
                $cd{$h} = $2;
            } else {
                chomp $l;
                die unless $l eq '';
                last;
            }
        }
        $revs{$r}{$h} = $sub;
        $c = join('', @c);
        die unless $msg{$h} eq '' || $msg{$h} eq $c;
        $msg{$h} = $c;
    }
    close($F);
}

chdir($PWD);
    
for (sort {$a <=> $b} keys %revs) {
    printf("%6d\n:", $rev);
    for $h (keys %{$revs{$rev}}) {
        $s = $revs{$rev}{$h};
        $c = $msg{$h};
        $cn = $cn{$h};
        $cd = $cd{$h};
        
        die;
        if (0) {
        print "$revs{$rev}{$h}\t$h\n";
        chdir("$PWD/$s") || die;
        system("git checkout -q -f $h");
        chdir($PWD);
        system("git add $s");
        }
    }
    chdir($PWD);
    open($F, "| git commit -F - --author \"$cn\" --date \"$cd\"") || die;
    print $F "[r$rev]".$c;
    close($F);
}

# $h
sub parse_gitmodules
{
    my ($h) = @_;
    my $F;
    my $h = '';
    open($F, "git-ls-tree $h |") | die;
    for (<$F>) {
        next unless /^([0-7]+)\s+(\w+)\s+([0-9A-Fa-f]{40,})\s+\.gitmodules/;
        $h = $3;
        last;
    }
    die unless $h ne '';
    die $h;
}

#EOF
