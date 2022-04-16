#!/bin/sh

set -e

SPACK_MIRROR="$(realpath "$(pwd)/../spack-mirror")"
#SPACK_MIRROR=
SPACK_MIRROR_ONLY=

spack_mirror ()
{
	test -n "${SPACK_MIRROR}" || return 0
	test -d "${SPACK_MIRROR}" || mkdir "${SPACK_MIRROR}"

	./bin/spack mirror add local "file://${SPACK_MIRROR}"
}

spack_install ()
{
	if test -n "${SPACK_MIRROR}"
	then
		echo "Mirroring $*"
		./bin/spack mirror create --directory "${SPACK_MIRROR}" --dependencies "$@"
	fi

	if test -z "${SPACK_MIRROR_ONLY}"
	then
		echo "Installing $*"
		./bin/spack install "$@"
	fi
}

spack_install_compiler ()
{
	local location

	spack_install "$@"

	if test -z "${SPACK_MIRROR_ONLY}"
	then
		location="$(./bin/spack location --install-dir "$@")"
		./bin/spack compiler find "${location}"
	fi
}

spack_env ()
{
	local env_file

	env_file='../env.sh'

	{
		printf 'test "$(id -u)" -eq 0 && return 0\n'
		printf '\n'
		printf 'export SPACK_DISABLE_LOCAL_CONFIG=1\n'
		printf '\n'
		printf '. %s/share/spack/setup-env.sh\n' "$(pwd)"
		printf '\n'
		printf 'module load gcc\n'
		printf 'module load mpich\n'
		printf '\n'
		printf 'module load gdb\n'
		printf 'module load git\n'
		printf 'module load valgrind\n'
		printf 'module load vim\n'
		printf '\n'
		# FIXME Make system man pages accessible
		printf 'export MANPATH="${MANPATH}:"\n'
	} > "${env_file}"
}

if test -f /etc/profile.d/modules.sh
then
	. /etc/profile.d/modules.sh
fi

module purge || true

rm --force --recursive "${HOME}/.spack"

rm --force spack/etc/spack/mirrors.yaml
rm --force --recursive spack/etc/spack/linux

cp config/config.yaml spack/etc/spack
cp config/modules.yaml spack/etc/spack
cp config/packages.yaml spack/etc/spack

cd spack

if test -z "${SPACK_MIRROR_ONLY}"
then
	# FIXME Find a better way to do this
	patch --strip=1 --forward --reject-file=- < ../patches/env.patch || true
fi

export SPACK_DISABLE_LOCAL_CONFIG=1

spack_mirror

# Keep in sync with packages.yaml and modules.yaml
spack_install_compiler gcc@11.2.0 %gcc@8.5.0

# Modules might not be installed system-wide
spack_install environment-modules target=x86_64

# MPI
spack_install mpich

# I/O
spack_install adios
spack_install adios2
spack_install fio
spack_install hdf5
spack_install libfuse
spack_install netcdf-c

# Tracing
spack_install cube
spack_install likwid
spack_install otf
spack_install otf2
spack_install scalasca
spack_install scorep

# Compression
spack_install c-blosc
spack_install lz4
spack_install lzma
spack_install lzo
spack_install snappy
spack_install zfp
spack_install zstd

# Math
spack_install gsl
spack_install netlib-scalapack
spack_install openblas

# Development
spack_install autoconf
spack_install automake
spack_install bison
spack_install boost
spack_install cmake
spack_install doxygen
spack_install flex
spack_install glib
spack_install hwloc
spack_install intel-tbb
spack_install json-c
spack_install libtool
spack_install m4
spack_install meson
spack_install ninja
spack_install pkgconf

# Tools
spack_install emacs
spack_install gdb
spack_install git
spack_install hyperfine
spack_install numactl
spack_install sysstat
spack_install tmux
spack_install valgrind
spack_install vim

# Languages
spack_install go
spack_install julia
spack_install llvm
spack_install rust

# Visualization
spack_install gnuplot
spack_install graphviz

# Python
spack_install python
spack_install py-flake8
spack_install py-matplotlib
spack_install py-numpy
spack_install py-pandas
spack_install py-pip
spack_install py-scikit-learn
spack_install py-sphinx
spack_install py-virtualenv

# R
spack_install r

if test -z "${SPACK_MIRROR_ONLY}"
then
	# Remove all unneeded packages
	./bin/spack gc --yes-to-all
	# Precreate the variables for our hack in setup-env.sh
	./bin/spack --print-shell-vars sh,modules > share/spack/setup-env.vars
	# This is required for chaining to work
	./bin/spack module tcl refresh --delete-tree --yes-to-all

	spack_env
fi
