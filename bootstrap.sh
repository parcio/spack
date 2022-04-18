#!/bin/sh

set -e

SELF_PATH="$(readlink --canonicalize-existing -- "$0")"
SELF_DIR="${SELF_PATH%/*}"
SELF_BASE="${SELF_PATH##*/}"

usage ()
{
	printf 'Usage: %s [prepare|build]\n' "${SELF_BASE}"
	exit 1
}

BOOTSTRAP_MIRROR="$(realpath "$(pwd)/../spack-mirror")"
#BOOTSTRAP_MIRROR=''
BOOTSTRAP_PHASE=''

bootstrap_in_phase ()
{
	local phase

	phase="$1"

	test -n "${phase}" || return 1
	test "${phase}" = 'prepare' -o "${phase}" = 'build' || return 1

	if test -z "${BOOTSTRAP_PHASE}" -o "${BOOTSTRAP_PHASE}" = "${phase}"
	then
		return 0
	else
		return 1
	fi
}

bootstrap_apply_pr ()
{
	local pr

	pr="$1"

	test -n "${pr}" || return 1

	rm --force "${pr}.patch"
	curl --fail --location --remote-name "https://github.com/spack/spack/pull/${pr}.patch"
	git apply --verbose "${pr}.patch"
}

bootstrap_install ()
{
	if bootstrap_in_phase prepare
	then
		if test -n "${BOOTSTRAP_MIRROR}"
		then
			echo "Mirroring $*"
			./bin/spack mirror create --directory "${BOOTSTRAP_MIRROR}" --dependencies "$@"
		fi
	fi

	if bootstrap_in_phase build
	then
		echo "Installing $*"
		./bin/spack install "$@"
	fi
}

bootstrap_install_compiler ()
{
	local location

	bootstrap_install "$@"

	if bootstrap_in_phase build
	then
		location="$(./bin/spack location --install-dir "$@")"
		./bin/spack compiler find "${location}"
	fi
}

bootstrap_create_env ()
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

BOOTSTRAP_PHASE="$1"

test -z "${BOOTSTRAP_PHASE}" -o "${BOOTSTRAP_PHASE}" = 'prepare' -o "${BOOTSTRAP_PHASE}" = 'build' || usage

if test -f /etc/profile.d/modules.sh
then
	. /etc/profile.d/modules.sh
fi

module purge || true

cd spack

export SPACK_DISABLE_LOCAL_CONFIG=1

if bootstrap_in_phase prepare
then
	git checkout --force

	# FIXME Find a better way to do this
	git apply --verbose ../patches/env.patch

	# FIXME sysstat does not build
	bootstrap_apply_pr 30121

	# FIXME hyperfine does not build
	bootstrap_apply_pr 30123

	rm --force --recursive "${HOME}/.spack"

	rm --force etc/spack/mirrors.yaml
	rm --force --recursive etc/spack/linux

	cp ../config/config.yaml etc/spack
	cp ../config/modules.yaml etc/spack
	cp ../config/packages.yaml etc/spack

	if test -n "${BOOTSTRAP_MIRROR}"
	then
		mkdir --parents "${BOOTSTRAP_MIRROR}"
		./bin/spack mirror add local "file://${BOOTSTRAP_MIRROR}"
	fi
fi

# Keep in sync with packages.yaml and modules.yaml
bootstrap_install_compiler gcc@11.2.0 %gcc@8.5.0

# Modules might not be installed system-wide
bootstrap_install environment-modules target=x86_64

# MPI
bootstrap_install mpich

# I/O
bootstrap_install adios
bootstrap_install adios2
bootstrap_install fio
bootstrap_install hdf5
bootstrap_install libfuse
bootstrap_install netcdf-c

# Tracing
bootstrap_install cube
bootstrap_install likwid
bootstrap_install otf
bootstrap_install otf2
bootstrap_install scalasca
bootstrap_install scorep

# Compression
bootstrap_install c-blosc
bootstrap_install lz4
bootstrap_install lzma
bootstrap_install lzo
bootstrap_install snappy
bootstrap_install zfp
bootstrap_install zstd

# Math
bootstrap_install gsl
bootstrap_install netlib-scalapack
bootstrap_install openblas

# Development
bootstrap_install autoconf
bootstrap_install automake
bootstrap_install bison
bootstrap_install boost
bootstrap_install cmake
bootstrap_install doxygen
bootstrap_install flex
bootstrap_install glib
bootstrap_install hwloc
bootstrap_install intel-tbb
bootstrap_install json-c
bootstrap_install libtool
bootstrap_install m4
bootstrap_install meson
bootstrap_install ninja
bootstrap_install pkgconf

# Tools
bootstrap_install emacs
bootstrap_install gdb
bootstrap_install git
bootstrap_install hyperfine
bootstrap_install numactl
bootstrap_install sysstat
bootstrap_install tmux
bootstrap_install valgrind
bootstrap_install vim

# Languages
bootstrap_install go
bootstrap_install julia
bootstrap_install llvm
bootstrap_install rust

# Visualization
bootstrap_install gnuplot
bootstrap_install graphviz

# Python
bootstrap_install python
bootstrap_install py-flake8
bootstrap_install py-matplotlib
bootstrap_install py-numpy
bootstrap_install py-pandas
bootstrap_install py-pip
bootstrap_install py-scikit-learn
bootstrap_install py-sphinx
bootstrap_install py-virtualenv

# R
bootstrap_install r

if bootstrap_in_phase build
then
	# Remove all unneeded packages
	./bin/spack gc --yes-to-all

	# Precreate the variables for our hack in setup-env.sh
	./bin/spack --print-shell-vars sh,modules > share/spack/setup-env.vars

	# This is required for chaining to work
	./bin/spack module tcl refresh --delete-tree --yes-to-all

	bootstrap_create_env
fi
