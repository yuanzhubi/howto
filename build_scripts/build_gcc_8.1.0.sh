#/usr/bin/env bash

# Instructions for building gcc 8.1.0 from source.

# This gcc build script is free software; you can redistribute it and/or modify
# it under the terms of the MIT license.

#======================================================================
# User configuration
#======================================================================

# Version of gcc being built
gcc_version=8.1.0

# Additional makefile options.  E.g., "-j 4" for parallel builds.  Parallel
# builds are faster, however it can cause a build to fail if the project
# makefile does not support parallel build.
make_flags="-j 1"

# Architecture we are building for.
arch_flags="-march=x86-64"

# This is required during configuration of GCC.
build_target=x86_64-unknown-linux-gnu

# File locations.  Use 'install_dir' to specify where gcc will be installed.
# The other directories are used only during the build process, and can later be
# deleted.
#
# WARNING: do not make 'source_dir' and 'build_dir' the same, or
# subdirectory of each other! It will cause build problems.
install_dir=${HOME}/opt/gcc-${gcc_version}
build_dir=/var/tmp/$(whoami)/gcc_build
source_dir=/var/tmp/$(whoami)/gcc_source
tarfile_dir=/var/tmp/$(whoami)/gcc_taballs

# String which gets embedded into GCC verion info, can be accessed at
# runtime. Use to indicate who/what/when has built this compiler.
packageversion="$(whoami)-$(hostname -s)"

# GCC requires that various tools and packages be available for use in the build
# procedure, including several support libraries are necessary to build GCC. The
# versions below are close to (and higher than) the minimum recommended
# versions.  These libraries will all be build "in-source" with gcc, i.e., they
# will get unzipped into the gcc source code.

# mpfr: use mpfr > 3.1, so that we can use it with gcc in-source build ability
# mpc: 0.8.1 has bug, doesn't compile, so use 0.8.2

gmp_version=4.3.2
mpfr_version=3.1.4
mpc_version=0.8.2
isl_version=0.15


#======================================================================
# Support functions
#======================================================================


__die()
{
    echo $*
    exit 1
}


function __banner()
{
    echo "============================================================"
    echo $*
    echo "============================================================"
}


__untar()
{
    dir="$1";
    file="$2"
    case $file in
        *xz)
            tar xJ -C "$dir" -f "$file"
            ;;
        *bz2)
            tar xj -C "$dir" -f "$file"
            ;;
        *gz)
            tar xz -C "$dir" -f "$file"
            ;;
        *)
            __die "don't know how to unzip $file"
            ;;
    esac
}


__abort()
{
        cat <<EOF
***************
*** ABORTED ***
***************
An error occurred. Exiting...
EOF
        exit 1
}


function __wget()
{
    urlroot=$1; shift
    tarfile=$1; shift

    if [ ! -e "$tarfile_dir/$tarfile" ]; then
        wget --verbose ${urlroot}/$tarfile --directory-prefix="$tarfile_dir"
    else
        echo "already downloaded: $tarfile  '$tarfile_dir/$tarfile'"
    fi
}


# Set script to abort on any command that results an error status
trap '__abort' 0
set -e



#======================================================================
# Directory creation
#======================================================================


__banner Creating directories

for d in "$install_dir" "$build_dir" "$source_dir" "$tarfile_dir" ;
do
    test  -d "$d" || mkdir --verbose -p $d
done


#======================================================================
# Download source code
#======================================================================


# This step requires internet access.  If you dont have internet access, then
# obtain the tarfiles via an alternative manner, and place in the
# "$tarfile_dir"

__banner Downloading source code

gmp_tarfile=gmp-${gmp_version}.tar.bz2
mpfr_tarfile=mpfr-${mpfr_version}.tar.bz2
mpc_tarfile=mpc-${mpc_version}.tar.gz
isl_tarfile=isl-${isl_version}.tar.bz2
gcc_tarfile=gcc-${gcc_version}.tar.gz

__wget https://gmplib.org/download/gmp/archive      $gmp_tarfile
__wget https://ftp.gnu.org/gnu/mpfr                 $mpfr_tarfile
__wget http://www.multiprecision.org/downloads      $mpc_tarfile
__wget ftp://gcc.gnu.org/pub/gcc/infrastructure     $isl_tarfile
__wget ftp://ftp.gnu.org/gnu/gcc/gcc-${gcc_version} $gcc_tarfile

# Check tarfiles are found, if not found, dont proceed
for f in $gmp_tarfile $mpfr_tarfile $mpc_tarfile $isl_tarfile $gcc_tarfile
do
    if [ ! -f "$tarfile_dir/$f" ]; then
        __die tarfile not found: $tarfile_dir/$f
    fi
done


#======================================================================
# Unpack source tarfiles
#======================================================================


__banner Unpacking source code

# We are using gcc's feature of in-source builds.  If each dependency is placed
# within the gcc source directory, they will automatically get built during the
# build of gcc.

__untar  "$source_dir"  "$tarfile_dir/$gcc_tarfile"

__untar  "$source_dir/gcc-${gcc_version}"  "$tarfile_dir/$mpfr_tarfile"
mv $source_dir/gcc-${gcc_version}/mpfr-${mpfr_version} $source_dir/gcc-${gcc_version}/mpfr

__untar  "$source_dir/gcc-${gcc_version}"  "$tarfile_dir/$mpc_tarfile"
mv $source_dir/gcc-${gcc_version}/mpc-${mpc_version} $source_dir/gcc-${gcc_version}/mpc

__untar "$source_dir/gcc-${gcc_version}"  "$tarfile_dir/$gmp_tarfile"
mv $source_dir/gcc-${gcc_version}/gmp-${gmp_version} $source_dir/gcc-${gcc_version}/gmp

__untar "$source_dir/gcc-${gcc_version}"  "$tarfile_dir/$isl_tarfile"
mv $source_dir/gcc-${gcc_version}/isl-${isl_version} $source_dir/gcc-${gcc_version}/isl


#======================================================================
# Clean environment
#======================================================================


# Before beginning the configuration and build, clean the current shell of all
# environment variables, and set only the minimum that should be required. This
# prevents all sorts of unintended interactions between environment variables
# and the build process.

__banner Cleaning environment

# store USER, HOME and then completely clear environment
U=$USER
H=$HOME

for i in $(env | awk -F"=" '{print $1}') ;
do
    unset $i ;
done

# restore
export USER=$U
export HOME=$H
export PATH=/usr/local/bin:/usr/bin:/bin:/sbin:/usr/sbin

echo shell environment follows:
env


#======================================================================
# Configure
#======================================================================


__banner Configuring source code


cd ${build_dir}/gcc-${gcc_version}

CC=gcc
CXX=g++
OPT_FLAGS="-O2 $gflags -Wall  $arch_flags"
CC="$CC" CXX="$CXX" CFLAGS="$OPT_FLAGS" \
	CXXFLAGS="`echo " $OPT_FLAGS " | sed 's/ -Wall / /g'`" \
	$source_dir/gcc-${gcc_version}/configure --prefix=${install_dir} \
	--enable-bootstrap \
	--enable-shared \
    --enable-threads=posix \
    --enable-checking=release \
    --with-system-zlib \
    --enable-__cxa_atexit \
    --disable-libunwind-exceptions \
	--enable-linker-build-id \
	--enable-languages=c,c++,lto \
    --disable-vtable-verify \
	--with-default-libstdcxx-abi=new \
    --enable-libstdcxx-debug  \
    --without-included-gettext  \
	--enable-plugin \
	--disable-initfini-array \
	--disable-libgcj \
    --enable-plugin  \
    --disable-multilib \
	--with-tune=generic \
	--build=${build_target} \
	--target=${build_target} \
	--host=${build_target} \
    --with-pkgversion="$packageversion"


#======================================================================
# Compiling
#======================================================================


cd "$build_dir/gcc-${gcc_version}" && make BOOT_CFLAGS="$OPT_FLAGS" $make_flags bootstrap

# If desired, run the gcc test phase by uncommenting following line

#make check


#======================================================================
# Install
#======================================================================


__banner Installing

make install


#======================================================================
# Post build
#======================================================================


trap : 0
echo build script complete at `date`

#end
