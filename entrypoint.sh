#!/bin/bash

# fail whole script if any command fails
set -e

DEBUG=$4

if [[ -n $DEBUG  && $DEBUG = true ]]; then
    set -x
fi

target=$1
dictionary=$2
command=$3
case $target in
    repo-add)
        for pkg in `cat need-update`
        do
          cd coolapk-linux
          pkgname=$(ls ../pkgbuild/${pkg}/*.zst)
          mv ../pkgbuild/${pkg}/${pkgname}
          repo-add coolapk-linux/x86_64/coolapk-linux.db.tar.gz coolapk-linux/x86_64/${pkgname}
          done
          ;;
    *)
      for pkg in `cat need-update`
      do
      pkgname="$dictionary"/"$pkg"
      # assumes that package files are in a subdirectory
      # of the same name as "pkgname", so this works well
      # with "aurpublish" tool

      if [[ ! -d $pkgname ]]; then
         echo "$pkgname should be a directory."
         exit 1
      fi

      if [[ ! -e $pkgname/PKGBUILD ]]; then
         echo "$pkgname does not contain a PKGBUILD file."
         exit 1
      fi

      pkgbuild_dir=$(readlink "$pkgname" -f) # nicely cleans up path, ie. ///dsq/dqsdsq/my-package//// -> /dsq/dqsdsq/my-package

      getfacl -p -R "$pkgbuild_dir" /github/home > /tmp/arch-pkgbuild-builder-permissions.bak

      # '/github/workspace' is mounted as a volume and has owner set to root
      # set the owner of $pkgbuild_dir  to the 'build' user, so it can access package files.
      sudo chown -R build "$pkgbuild_dir"

      # needs permissions so '/github/home/.config/yay' is accessible by yay
      sudo chown -R build /github/home

      # use more reliable keyserver
      mkdir -p /github/home/.gnupg/
      echo "keyserver hkp://keyserver.ubuntu.com:80" | tee /github/home/.gnupg/gpg.conf

      cd "$pkgbuild_dir"

      pkgname="$(basename "$pkgbuild_dir")" # keep quotes in case someone passes in a directory path with whitespaces...

      install_deps() {
          # install make and regular package dependencies
          grep -E 'depends|makedepends' PKGBUILD | \
          sed -e 's/.*depends=//' -e 's/ /\n/g' | \
          tr -d "'" | tr -d "(" | tr -d ")" | \
          xargs yay -S --noconfirm
       }

       case $target in
         pkgbuild)
            namcap PKGBUILD
            install_deps
            makepkg --syncdeps --noconfirm
            namcap "${pkgname}"-*

            # shellcheck disable=SC1091
            source /etc/makepkg.conf # get PKGEXT

            pacman -Qip "${pkgname}"-*"${PKGEXT}"
            pacman -Qlp "${pkgname}"-*"${PKGEXT}"
            ;;
         run)
            install_deps
            makepkg --syncdeps --noconfirm --install
            eval "$command"
            ;;
         srcinfo)
            makepkg --printsrcinfo | diff .SRCINFO - || \
               { echo ".SRCINFO is out of sync. Please run 'makepkg --printsrcinfo' and commit the changes."; false; }
            ;;
         *)
            echo "Target should be one of 'pkgbuild', 'srcinfo', 'run'" ;;
       ;;
esac

sudo setfacl --restore=/tmp/arch-pkgbuild-builder-permissions.bak
done
esac
