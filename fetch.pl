#!/usr/bin/perl

$PWD = $ENV{PWD};

system("git checkout master");

open($F, "git submodule |") || die;
while (<$F>) {
    die "Unexpected: $_" unless /^([-+\s])([0-9A-F]{16,})\s+(\w+)\s+/i;
    if ($1 ne ' ') {
        system("git submodule update");
        die;
    }
    $mhash{$3} = $2;
}
close($F);

# tree 6ba6abd0fb4097764b11d5088d20823ee65a6eac
# parent 0a6ea83f393d06fb424c470777a1c3e8a8c50ab1
# author Devang Patel <dpatel@apple.com> 1303495797 +0000
# committer Devang Patel <dpatel@apple.com> 1303495797 +0000


for $sub (sort keys %mhash) {
    chdir("$PWD/$sub") || die "$PWD/$sub";
    open($F, "git log $mhash{$sub}..origin/master |") || die;

    while (<$F>) {
        if (/^commit\s+([0-9a-f]{16,})/) {
            #print "hash: $1\n";
            $rev = 0;
            $hash = $1;
        } elsif (/^\s+git-svn-id:.*\@(\d+)/) {
            $rev = $1;
            #print "$hash: $rev $sub\n";
            $revs{$rev}{$hash} = $sub;
        }
    }
    close($F);
}

chdir($PWD);

for $rev (sort keys %revs) {
    printf("%6d\n:", $rev);
    for $h (keys %{$revs{$rev}}) {
        $s = $revs{$rev}{$h};
        print "$revs{$rev}{$h}\t$h\n";
        chdir("$PWD/$s") || die;
        system("git checkout -q -f $h");
        chdir($PWD);
        system("git add $s");
    }
    chdir($PWD);
    system("git commit -m r$rev");
}
