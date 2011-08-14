#!/usr/bin/perl

$PWD = $ENV{PWD};

# さいしょに, master に含まれている commit を得る。
# FIXME: Make sure index is clean.
($ch) = `git show-ref refs/heads/master` =~ /([0-9a-f]{40,})/;
system("git read-tree --reset $ch");
if ($ch ne '') {
    open($F, "git ls-tree $ch |") || die;
    while (<$F>) {
        next unless /^160000\s+commit\s+([0-9a-f]{40,})\s+(\S+)/;
        $h = $1;
        $repo = $2;
        push(@repos, $repo);
        $master_hash{$repo} = $h;
        print STDERR "$h $repo\n";
        chdir("$PWD/$repo");
        chdir($PWD);
    }
    close($F);
}

# 次に、各リポジトリ候補から結果を得て回る。
open($F, "find -depth -mindepth 2 -maxdepth 2 -type d -name .git |") || die;
while (<$F>) {
    chomp;
    s=^\./==;
    next unless m@^(.+)/\.git$@;
    chdir("$PWD/$1") || die $1;
    &get_commits($1);
    chdir($PWD);
}
close($F);

# write!
for $r (sort {$a <=> $b} keys %revs) {
    my @repos = ();
    @files = ();
    for $h (@{$revs{$r}}) {
        $hh = $h;
        push(@files, $commits{$h}{FILES});
        $msg = $commits{$h}{MSG};
        for (grep(/^GIT_/, keys %{$commits{$h}})) {
            $ENV{$_} = $commits{$h}{$_};
        }
        my $repo = $commits{$h}{REPO};
        system("git update-index --add --cacheinfo 160000 $h $repo\n")
            && die;
        my ($mode, $mh) = ('100644', '');
        if ($master_hash{$repo} eq '') {
            my $gitm = '';
            if ($ch ne '') {
                ($mode, $mh)
                    = `git ls-tree $ch .gitmodules`
                    =~ /^(\d+)\s+blob\s+([0-9a-f]{40,})/;
                if ($mh ne '') {
                    $gitm = `git cat-file blob $mh`;
                }
            }
            open($F, "| git hash-object -w --stdin > .git/_.bak") || die;
            $X = $repo;
            #$X = "LLVM" if $X eq 'llvm';
            print $F "$gitm\[submodule \"$repo\"]\n\tpath = $repo\n\turl = git\@github.com:chapuni/$X.git\n";
            close($F);
            $mh = `cat .git/_.bak`;
            chomp $mh;
            system("git update-index --add --cacheinfo $mode $mh .gitmodules")
                && die "git update-index --add --cacheinfo $mode $mh .gitmodules";
            $master_hash{$repo} = $mh;
        }
        push(@repos, $repo);
    }
    open($F, "git write-tree |") || die;
    my $th = <$F>;
    chomp $th;
    close($F);
    my $gitct;
    if ($ch ne '') {
        $gitct = "git commit-tree $th -p $ch";
    } else {
        $gitct = "git commit-tree $th";
    }
    open($F, "| $gitct > .git/_.bak") || die $gitct;
    #print $F "[r$r] $msg";
    print $F $msg;
    close($F);
    $ch = `cat .git/_.bak`;
    chomp $ch;
    system("git tag -f r$r $ch");
    if (++$ntags >= 1000) {
        system("git pack-refs");
        $ntags = 0;
    }
    #system("git tag -f $_/r$r $ch") for (@repos);

# revision=r136765&when=341778&who=xNAKAMURA+Takumi&branch=master&comments=XXX%0AYYY&files=%5B%22aaa%22,%22bbb%22%5D&revlink=xxxx&repository=rerere&links=%5B%22aaa%22,%22bbb%22%5D&project=llvm-project&xxx=yyy

    print STDERR "r$r:$ch\n";
    %js = (branch=>'master',
           project=>'llvm-project');
    $js{'revision'} = "r$r";
    $js{'repository'} = 'chapuni@192.168.1.194:/home/chapuni/llvm-project';
    $commits{$hh}{GIT_AUTHOR_DATE} =~ /^(\d+)/;
    $js{'when'} = $1;
    $js{'files'} = '['.join(',',@files).']';
    $js{'who'} = sprintf("%s <%s>",
                         $commits{$hh}{GIT_AUTHOR_NAME},
                         $commits{$hh}{GIT_AUTHOR_EMAIL});
    $js{'comments'} = $commits{$hh}{MSG};

    for (keys %js) {
        my @a = split(//, $js{$_});
        for (@a) {
            if ($_ eq ' ') {
                $_ = '+';
            } elsif (/^\r*\n$/) {
                $_ = '%0A';
            } elsif (/^[-0-9A-Z_a-z]$/) {
            } else {
                $_ = sprintf('%%%02X', ord);
            }
        }
        $js{$_} = join('', @a);
    }
    $js = join('&', map {"$_=$js{$_}"} sort keys %js);
    open($fj, "> .git/_.bak") || die;
    print $fj $js;
    close($fj);
    system('wget http://bb.pgr.jp/change_hook/base --post-file=.git/_.bak');
}

print STDERR "Completed.\n";

system("git checkout -q -f master");
system("git merge -q --ff-only $ch");
exit;

sub get_commits
{
    my ($dir) = @_;
    my $F;
    my $a;
    my $head = $master_hash{$dir};
    my $rem = '';

    # get upstream
    open($F, "git remote -v |") || die;
    while (<$F>) {
        next unless m=^(\S+)\s+http://llvm\.org/git/$dir\.git\s+=;
        $rem = $1."/master";
        last;
    }
    close($F);
    if ($rem eq '') {
        system("git remote -v");
        die "Why didn't you track http://llvm.org/git/$dir.git ?";
    }

    if ($head ne '') {
        $rem = "$head..$rem";
    }

    print STDERR "$dir\t$rem\n";

    my $f = 0;
    open($F, "git log --pretty=raw --decorate=no $rem |") || die;
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
                my $df;
                open($df, "git diff-tree --numstat $h |");
                $commits{$h}{FILES} = join(',', grep(s/^\d+\s+\d+\s+(.*)\r*\n*$/\"$dir\/\1\"/, <$df>));
                close($df);
                next;
            } elsif (/^    (\s*)$/s) {
                $msg .= $1;
                next;
            } elsif (/git-svn-id:.+\@(\d+)/) {
                print STDERR "$dir $h r$1\n" unless $1 % 1000;
                $commits{$h}{REV} = $1;
                push(@{$revs{$1}}, $h);
                next;
            } elsif (/^    (.*)$/s) {
                $commits{$h}{MSG} .= $msg . $1;
                $msg = '';
            }
        }
    }
    close($F);
}

#EOF
