* Helper scripts for the submodule-based "llvm-project"

You can win with;

  - Simple (easy! sometimes not easier) and fast update.
  - Selective update. You can track a part of projects.
  - Effective git-bisect-ing.
  - svn-like tags. You can see like "r127206".
    Try "git show r127206" and "git log --decorate --online".

You won't do;

  - Integrated branch handling. merge/cherry-pick/rebase
    won't work fine with submodules.
  - Integrated git-svn-dcommit.
  - Tagging all svn revisions. 100k of tags could choke Git.
    (You may see tags since r127206..)

* Getting started

 1. git clone git://github.com/chapuni/llvm-project.git
 2. Install 2 files in llvm-project-scripts/hooks/ into .git/hooks
 3. If you have corresponding repositories loally,
    git clone ../relative/path/to/git/of/llvm llvm
    (You may also move repositories under llvm-project.)
    Then make sure the branch "master" tracks upstream.
    (Assumed "git pull" works on master)
 4. Init submodule entries. If you have submodules "llvm" and "clang",
    git submodule init llvm clang
 5. If you want to track new project;
    git submodule init dragonegg
    git submodule update

* Life with llvm-project

 1. If you were working on another branches in submodules,
    commit or stash your changes.
 2. git checkout master
 3. git pull


NAKAMURA Takumi
